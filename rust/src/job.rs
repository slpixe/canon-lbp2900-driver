// SPDX-License-Identifier: GPL-3.0-or-later
// LBP2900 sequence translated from prn_lbp2900.c; other printer models are
// deliberately not advertised by the experiment.
use crate::{
    Error, Result, codec,
    page::{Page, Raster},
    protocol::{self, Link, Transport},
    status::Status,
};
use std::time::Duration;
const IDENT: u16 = 0xa1a1;
const START0: u16 = 0xa3a2;
const BEGIN: u16 = 0xa2a0;
const GPIO: u16 = 0xe1a2;
const SETUP: u16 = 0xe1a1;
const END: u16 = 0xe0a9;
const GPIO_INIT: [u8; 12] = [0; 12];
// Preserve the original LBP2900 job prologue's 3010-style GPIO initialization.
const JOB_GPIO: [u8; 16] = [0x13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const BLINK: [u8; 12] = [0, 0, 1, 2, 1, 0, 0, 0, 0, 0, 1, 0];
#[derive(Debug, PartialEq, Eq)]
pub enum Event {
    MediaEmpty(bool),
    PageCompleted(u16),
}
pub struct Driver<T> {
    pub link: Link<T>,
    status: Status,
    job: u16,
}
impl<T: Transport> Driver<T> {
    pub fn new(io: T) -> Self {
        Self {
            link: Link { io },
            status: Status::default(),
            job: 0,
        }
    }
    fn ack(&mut self, cmd: u16, data: &[u8]) -> Result<()> {
        self.link
            .request(cmd, data, protocol::MAX_PACKET - 4)
            .map(|_| ())
    }
    fn status(&mut self, extended: bool) -> Result<Status> {
        let data = self.link.request(
            if extended {
                protocol::CHKXSTATUS
            } else {
                protocol::CHKSTATUS
            },
            &[],
            protocol::MAX_PACKET - 4,
        )?;
        self.status.update(&data, extended)?;
        Ok(self.status)
    }
    fn poll(
        &mut self,
        seconds: u64,
        extended: bool,
        predicate: impl Fn(Status) -> bool,
    ) -> Result<Status> {
        let deadline = self.link.io.now() + Duration::from_secs(seconds);
        loop {
            self.link.io.check()?;
            if self.link.io.now() >= deadline {
                return Err(Error::Timeout);
            }
            let status = self.status(extended)?;
            if self.link.io.now() >= deadline {
                return Err(Error::Timeout);
            }
            if predicate(status) {
                return Ok(status);
            }
            self.link.io.delay(Duration::from_millis(100))?;
        }
    }
    fn ready(&mut self) -> Result<()> {
        self.poll(30, true, |s| !s.busy()).map(|_| ())
    }
    fn setup(&mut self, flag: u8, page: u16) -> Result<()> {
        let time = self.link.io.timestamp()?;
        let mut data = [0u8; 72];
        data[4..6].copy_from_slice(&page.to_le_bytes());
        data[16] = flag;
        data[17] = 1;
        data[18..20].copy_from_slice(&self.job.to_le_bytes());
        data[20..24].copy_from_slice(&[0xc4, 0xff, 0x88, 0xff]);
        data[24..26].copy_from_slice(&time[0].to_le_bytes());
        for i in 1..6 {
            data[25 + i] = u8::try_from(time[i]).map_err(|_| Error::Io)?;
        }
        data[31] = 1;
        self.ack(SETUP, &data)
    }
    fn begin(&mut self) -> Result<()> {
        self.ack(IDENT, &[])?;
        self.link.io.delay(Duration::from_secs(1))?;
        self.status = Status::default();
        self.status(true)?;
        self.ack(START0, &[])?;
        let reply = self.link.request(BEGIN, &[0, 0, 30, 0, 0, 0, 0, 0], 8)?;
        let job = reply.get(2..4).ok_or(Error::Truncated)?;
        self.job = u16::from_le_bytes([job[0], job[1]]);
        self.ack(GPIO, &JOB_GPIO)?;
        self.ready()?;
        self.setup(1, 0)?;
        self.ready()
    }
    fn page_begin(&mut self, page: &Page) -> Result<()> {
        if self.status(true)?.uninitialized() {
            for cmd in [0xe0a3, 0xe0a2, 0xe0a4] {
                self.ack(cmd, &[])?;
            }
            self.ready()?;
            self.ack(
                0xe0a5,
                &[0xee, 0xdb, 0xea, 0xad, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            )?;
            self.ready()?;
        }
        self.poll(30, true, |s| !s.buffer_full())?;
        let packet = protocol::combined(
            0xd0a9,
            &[
                (0xd0a0, page.parameters()),
                (0xd0a4, &codec::PARAMS),
                (0xd0a1, &[]),
                (0xd0a2, &[]),
            ],
        )?;
        self.link.io.write(&packet)
    }
    fn page_end(&mut self, emit: &mut impl FnMut(Event)) -> Result<bool> {
        self.link.send(0xc0a4, &[])?;
        let status = self.poll(30, true, |s| s.received == s.decoding)?;
        self.setup(2, status.decoding)?;
        self.ready()?;
        self.ack(0xe0a7, &self.status.decoding.to_le_bytes())?;
        self.ready()?;
        self.setup(6, self.status.decoding)?;
        let deadline = self.link.io.now() + Duration::from_secs(30);
        let mut blinking = false;
        loop {
            self.link.io.check()?;
            if self.link.io.now() >= deadline {
                return Err(Error::Timeout);
            }
            let status = self.status(true)?;
            if self.link.io.now() >= deadline {
                return Err(Error::Timeout);
            }
            if status.out == status.decoding {
                emit(Event::MediaEmpty(false));
                return Ok(true);
            }
            if status.no_paper() {
                emit(Event::MediaEmpty(true));
                if !blinking {
                    self.ack(GPIO, &BLINK)?;
                    blinking = true;
                }
                if !status.processing() {
                    return Ok(false);
                }
            }
            self.link.io.delay(Duration::from_millis(100))?;
        }
    }
    fn wait_user(&mut self) -> Result<()> {
        self.ack(GPIO, &BLINK)?;
        self.ready()?;
        self.poll(300, true, Status::button)?;
        self.ack(GPIO, &GPIO_INIT)?;
        self.ready()
    }
    fn finish(&mut self) -> Result<()> {
        let status = self.poll(30, true, |s| s.completed == s.decoding)?;
        self.setup(4, status.completed)?;
        self.ack(END, &self.job.to_le_bytes())
    }
    pub fn print(&mut self, raster: &mut impl Raster, mut emit: impl FnMut(Event)) -> Result<()> {
        self.link.io.check()?;
        protocol::identify(&self.link.io.device_id()?)?;
        let mut pages = 0u16;
        while let Some(header) = raster.header()? {
            self.link.io.check()?;
            pages = pages.checked_add(1).ok_or(Error::Capacity)?;
            let page = Page::from_header(&header)?;
            let bands = page.cache(raster, || self.link.io.check())?;
            if pages == 1 {
                emit(Event::MediaEmpty(false));
                self.begin()?;
            }
            let mut retries = 0;
            loop {
                if page.manual_duplex() && pages > 1 {
                    self.wait_user()?;
                }
                self.page_begin(&page)?;
                let mut sends = 0usize;
                for band in &bands {
                    for chunk in band.chunks(0xff00) {
                        sends += 1;
                        if sends.is_multiple_of(16) {
                            // LBP2900 requires extended status here too; hardware rejected
                            // the legacy basic-status variant at the 16th chunk.
                            self.poll(30, true, |s| !s.busy())?;
                        }
                        self.link.send(0xc0a0, chunk)?;
                    }
                }
                if self.page_end(&mut emit)? {
                    emit(Event::PageCompleted(pages));
                    break;
                }
                retries += 1;
                if retries > 3 {
                    return Err(Error::RetryLimit);
                }
                self.wait_user()?;
            }
        }
        if pages == 0 {
            return Err(Error::NoPages);
        }
        self.finish()
    }
}
