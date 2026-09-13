// SPDX-License-Identifier: GPL-3.0-or-later
use crate::{Error, Result, codec};
/// CUPS metadata, copied by the adapter into a fixed ABI-independent array.
/// See adapter/cups.c for the field index map. This is not a CUPS struct layout.
#[derive(Clone, Debug)]
pub struct Header {
    pub values: [u32; 20],
    pub media: [u8; 64],
}
#[derive(Clone, Debug)]
pub struct Page {
    height: usize,
    line_size: usize,
    band_rows: usize,
    input_line_size: usize,
    manual_duplex: bool,
    params: [u8; 40],
}
pub trait Raster {
    fn header(&mut self) -> Result<Option<Header>>;
    fn read_line(&mut self, out: &mut [u8]) -> Result<()>;
}
impl Page {
    pub fn from_header(h: &Header) -> Result<Self> {
        let v = &h.values;
        if !(1..=8192).contains(&v[0])
            || !(1..=12000).contains(&v[1])
            || !(1..=1024).contains(&v[2])
            || !(1..=1440).contains(&v[3])
            || !(1..=256).contains(&v[4])
            || v[5] != 1
            || v[6] != 1
            || v[7] != 0
            || v[8] != 3
            || v[9] != 1
            || v[10] != v[0].div_ceil(8)
            || v[11] != 600
            || v[12] != 600
            || v[13] > 6
            || v[14] > 1
            || v[15] > 63
            || v[16] > 1
            || v[17] > 65535
            || v[18] > 65535
        {
            return Err(Error::InvalidRaster);
        }
        let mut params = [0u8; 40];
        params[..22].copy_from_slice(&[
            0,
            0,
            0x30,
            0x2a,
            2,
            0,
            0,
            0,
            (v[15] as u8) << 2,
            0x1c,
            0x1c,
            0x1c,
            v[13] as u8,
            0x11,
            4,
            0,
            1,
            1,
            2,
            v[14] as u8,
            0,
            0,
        ]);
        for (name, value) in [
            ("A4", 2),
            ("A5", 3),
            ("B5", 7),
            ("Executive", 10),
            ("Legal", 12),
            ("Letter", 13),
            ("EnvC5", 21),
            ("Env10", 22),
            ("EnvMonarch", 23),
            ("EnvDL", 24),
            ("3x5", 64),
            ("PRC16K", 212),
        ] {
            if h.media.starts_with(name.as_bytes()) {
                params[4] = value;
                break;
            }
        }
        for (i, value) in [v[17], v[18], v[2], v[1], v[0], v[1]].iter().enumerate() {
            params[22 + i * 2..24 + i * 2].copy_from_slice(&(*value as u16).to_le_bytes());
        }
        params[36] = [1, 1, 1, 2, 0x13, 0x14, 0x1c][v[13] as usize];
        Ok(Self {
            height: v[1] as usize,
            line_size: v[2] as usize,
            band_rows: v[4] as usize,
            input_line_size: v[10] as usize,
            manual_duplex: v[16] != 0,
            params,
        })
    }
    pub fn manual_duplex(&self) -> bool {
        self.manual_duplex
    }
    pub fn parameters(&self) -> &[u8] {
        &self.params
    }
    pub fn cache(
        &self,
        raster: &mut impl Raster,
        mut check: impl FnMut() -> Result<()>,
    ) -> Result<Vec<Vec<u8>>> {
        let mut bands = Vec::new();
        let mut total = 0usize;
        let mut line = vec![0; self.input_line_size];
        let ncopy = self.line_size.min(self.input_line_size);
        let source = (self.input_line_size - ncopy) / 2;
        let dest = (self.line_size - ncopy) / 2;
        for start in (0..self.height).step_by(self.band_rows) {
            check()?;
            let rows = self.band_rows.min(self.height - start);
            let mut band = vec![0; self.line_size * rows];
            for row in 0..rows {
                check()?;
                raster.read_line(&mut line)?;
                band[row * self.line_size + dest..row * self.line_size + dest + ncopy]
                    .copy_from_slice(&line[source..source + ncopy]);
            }
            // C emits NORMAL for every band, including the last band of a page.
            let compressed = codec::compress(&band, self.line_size, rows, false)?;
            total = total
                .checked_add(compressed.len())
                .filter(|n| *n <= 32 * 1024 * 1024)
                .ok_or(Error::Capacity)?;
            bands.push(compressed);
        }
        Ok(bands)
    }
}
