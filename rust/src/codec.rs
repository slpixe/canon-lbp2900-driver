// SPDX-License-Identifier: GPL-3.0-or-later
// Safe Rust translation of Alexey Galakhov's Hi-SCoA encoder (2013).
use crate::{Error, Result};
pub const PARAMS: [u8; 8] = [1, 4, 1, 1, 0, 249, 0, 0];
struct Bits {
    bytes: Vec<u8>,
    position: usize,
    limit: usize,
}
impl Bits {
    fn push(&mut self, value: u32, count: u32) -> Result<()> {
        if count > 32 {
            return Err(Error::Capacity);
        }
        for bit in (0..count).rev() {
            if self.position / 8 >= self.limit {
                return Err(Error::Capacity);
            }
            if self.position.is_multiple_of(8) {
                self.bytes.push(0x43);
            }
            if value & (1 << bit) != 0 {
                self.bytes[self.position / 8] ^= 1 << (7 - self.position % 8);
            }
            self.position += 1;
        }
        Ok(())
    }
}
pub fn compress(input: &[u8], width: usize, rows: usize, last: bool) -> Result<Vec<u8>> {
    compress_bounded(
        input,
        width,
        rows,
        last,
        input.len().saturating_mul(2).saturating_add(16),
    )
}
pub fn compress_bounded(
    input: &[u8],
    width: usize,
    rows: usize,
    last: bool,
    capacity: usize,
) -> Result<Vec<u8>> {
    if !(1..=1024).contains(&width)
        || !(1..=256).contains(&rows)
        || width.checked_mul(rows) != Some(input.len())
    {
        return Err(Error::InvalidRaster);
    }
    let mut bits = Bits {
        bytes: Vec::new(),
        position: 0,
        limit: capacity.min(2 * input.len() + 16),
    };
    let mut origins = [width, 0, width.wrapping_sub(7), 1, 0, 4];
    let mut history = [0u8; 16];
    let mut used = 0usize;
    let mut pos = 0;
    while pos < input.len() {
        let mut best = (0usize, 0usize);
        for (cmd, &diff) in origins.iter().enumerate() {
            if diff == 0 || pos < diff {
                continue;
            }
            let mut end = pos;
            while input[end] == input[end - diff] {
                end += 1;
                if end == input.len() || end == pos + 639 || end.is_multiple_of(width) {
                    break;
                }
            }
            if end - pos > best.1 {
                best = (cmd, end - pos);
            }
        }
        if best.1 > 1 {
            let mut len = best.1 as u32;
            if len > 127 {
                let val = len / 128;
                let n = 31 - val.leading_zeros();
                bits.push(0xfc, 8)?;
                bits.push(n, 2)?;
                bits.push(!val, n)?;
                len %= 128;
            }
            bits.push(0xffff_fffe, best.0 as u32 + 1)?;
            if best.0 == 2 {
                bits.push(0, 1)?;
            }
            match len {
                0 => bits.push(0x3f, 6)?,
                1 => bits.push(0, 2)?,
                2 => bits.push(3, 3)?,
                3 => bits.push(2, 3)?,
                _ => {
                    let n = 31 - len.leading_zeros();
                    bits.push(0xffff_fffe, n)?;
                    bits.push(!len, n)?;
                }
            }
            if best.0 == 2 {
                origins.swap(2, 0);
            }
            if best.0 == 5 {
                origins.swap(5, 3);
            }
            pos += best.1;
            continue;
        }
        let byte = input[pos];
        if let Some(i) = history[..used].iter().position(|b| *b == byte) {
            history.copy_within(0..i, 1);
            history[0] = byte;
            bits.push(0x20 | (15 - i as u32), 6)?;
        } else {
            used = (used + 1).min(16);
            history.copy_within(0..used - 1, 1);
            history[0] = byte;
            if byte == 0 {
                bits.push(0xfd, 8)?;
            } else {
                bits.push(0xd00 | byte as u32, 12)?;
            }
        }
        pos += 1;
    }
    bits.push(0xfe, 8)?;
    bits.push(u32::from(last), 2)?;
    if !bits.position.is_multiple_of(32) {
        bits.push(u32::MAX, 32 - (bits.position % 32) as u32)?;
    }
    Ok(bits.bytes)
}
