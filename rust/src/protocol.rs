// SPDX-License-Identifier: GPL-3.0-or-later
use crate::{Error, Result};
use std::time::Duration;
pub const MAX_PACKET: usize = u16::MAX as usize;
pub const CHKSTATUS: u16 = 0xe0a0;
pub const CHKXSTATUS: u16 = 0xa0a8;

/// Backend operations must honor deadlines and cancellation, including writes.
/// No raw pointers or CUPS types cross into the protocol core.
pub trait Transport {
    fn write(&mut self, packet: &[u8]) -> Result<()>;
    fn read(&mut self, buffer: &mut [u8], timeout: Duration) -> Result<usize>;
    fn device_id(&mut self) -> Result<Vec<u8>>;
    fn now(&self) -> Duration;
    fn check(&self) -> Result<()>;
    fn delay(&mut self, duration: Duration) -> Result<()>;
    /// Local calendar: years since 1900, zero-based month, day, hour, minute, second.
    fn timestamp(&self) -> Result<[u16; 6]>;
}
pub fn packet(command: u16, payload: &[u8]) -> Result<Vec<u8>> {
    let length = payload
        .len()
        .checked_add(4)
        .filter(|n| *n <= MAX_PACKET)
        .ok_or(Error::Capacity)?;
    let mut out = Vec::with_capacity(length);
    out.extend_from_slice(&command.to_le_bytes());
    out.extend_from_slice(&(length as u16).to_le_bytes());
    out.extend_from_slice(payload);
    Ok(out)
}
pub fn combined(command: u16, records: &[(u16, &[u8])]) -> Result<Vec<u8>> {
    let mut out = packet(command, &[])?;
    for (cmd, data) in records {
        if data
            .len()
            .checked_add(4)
            .and_then(|n| n.checked_add(out.len()))
            .is_none_or(|n| n > MAX_PACKET)
        {
            return Err(Error::Capacity);
        }
        out.extend_from_slice(&packet(*cmd, data)?);
    }
    let len = (out.len() as u16).to_le_bytes();
    out[2..4].copy_from_slice(&len);
    Ok(out)
}
pub fn identify(data: &[u8]) -> Result<()> {
    if data.len() > 4096 || data.contains(&0) {
        return Err(Error::UnsupportedPrinter);
    }
    let text = std::str::from_utf8(data).map_err(|_| Error::UnsupportedPrinter)?;
    for part in text
        .trim_matches(|c: char| c.is_ascii_whitespace())
        .split(';')
    {
        if let Some((key, value)) = part.split_once(':')
            && (key == "MDL" || key == "MODEL")
        {
            return if value == "LBP2900" {
                Ok(())
            } else {
                Err(Error::UnsupportedPrinter)
            };
        }
    }
    Err(Error::UnsupportedPrinter)
}
pub struct Link<T> {
    pub io: T,
}
impl<T: Transport> Link<T> {
    pub fn send(&mut self, command: u16, payload: &[u8]) -> Result<()> {
        self.io.check()?;
        self.io.write(&packet(command, payload)?)
    }
    pub fn request(&mut self, command: u16, payload: &[u8], capacity: usize) -> Result<Vec<u8>> {
        self.send(command, payload)?;
        let deadline = self.io.now() + Duration::from_secs(15);
        let mut data = vec![0; MAX_PACKET];
        let mut size = 0;
        self.fragment(&mut data, &mut size, 6, deadline)?;
        if u16::from_le_bytes([data[0], data[1]]) != command {
            return Err(Error::UnexpectedCommand);
        }
        // LBP2900 framed replies use binary little-endian total lengths.
        // Never infer an encoding from read boundaries; see PROTOCOL-LENGTHS.md.
        let length = u16::from_le_bytes([data[2], data[3]]) as usize;
        if length < 6 {
            return Err(Error::InvalidPacket);
        }
        if length - 4 > capacity {
            return Err(Error::Capacity);
        }
        self.fragment(&mut data, &mut size, length, deadline)?;
        let payload = &data[4..size];
        if payload.len() > capacity {
            return Err(Error::Capacity);
        }
        Ok(payload.to_vec())
    }
    fn fragment(
        &mut self,
        data: &mut [u8],
        size: &mut usize,
        end: usize,
        deadline: Duration,
    ) -> Result<()> {
        while *size < end {
            self.read_once(data, size, end - *size, deadline)?;
        }
        Ok(())
    }
    fn read_once(
        &mut self,
        data: &mut [u8],
        size: &mut usize,
        wanted: usize,
        deadline: Duration,
    ) -> Result<()> {
        self.io.check()?;
        let remaining = deadline
            .checked_sub(self.io.now())
            .filter(|n| !n.is_zero())
            .ok_or(Error::Timeout)?;
        let slice = data
            .get_mut(*size..size.checked_add(wanted).ok_or(Error::Capacity)?)
            .ok_or(Error::Capacity)?;
        let n = self.io.read(slice, remaining)?;
        self.io.check()?;
        if self.io.now() >= deadline {
            return Err(Error::Timeout);
        }
        if n == 0 || n > wanted {
            return Err(Error::Truncated);
        }
        *size += n;
        Ok(())
    }
}
