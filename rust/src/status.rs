// SPDX-License-Identifier: GPL-3.0-or-later
use crate::{Error, Result};
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Status {
    pub words: [u16; 7],
    pub decoding: u16,
    pub printing: u16,
    pub out: u16,
    pub completed: u16,
    pub received: u16,
}
impl Status {
    pub fn update(&mut self, data: &[u8], extended: bool) -> Result<()> {
        if if extended {
            data.len() < 40
        } else {
            data.len() != 2 && data.len() != 10
        } {
            return Err(Error::InvalidStatus);
        }
        let word = |i| u16::from_le_bytes([data[i], data[i + 1]]);
        self.words[0] = word(0);
        if data.len() == 2 {
            return Ok(());
        }
        self.words[1] = word(8);
        if !extended {
            return Ok(());
        }
        for (i, offset) in [(2, 10), (3, 12), (4, 24), (5, 30), (6, 38)] {
            self.words[i] = word(offset);
        }
        self.decoding = word(14);
        self.printing = word(16);
        self.out = word(18);
        self.completed = word(20);
        self.received = word(34);
        Ok(())
    }
    pub fn busy(self) -> bool {
        self.words[0] & (1 << 7) != 0
    }
    pub fn uninitialized(self) -> bool {
        self.words[0] & 0x30 != 0
    }
    pub fn buffer_full(self) -> bool {
        self.words[0] & 4 != 0
    }
    pub fn no_paper(self) -> bool {
        self.words[0] & 2 != 0 || self.words[1] & 0x4000 != 0
    }
    pub fn processing(self) -> bool {
        self.words[1] & 0x84 != 0
    }
    pub fn button(self) -> bool {
        self.words[1] & 0x20 != 0
    }
}
