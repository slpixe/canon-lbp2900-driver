// SPDX-License-Identifier: GPL-3.0-or-later
//! The only Rust unsafe boundary. See docs/RUST.md for its ownership contract.
use lbp2900_rust::{
    Error, Result,
    page::{Header, Raster},
    protocol::Transport,
};
use std::{
    ffi::c_void,
    fs::File,
    os::fd::AsRawFd,
    ptr::NonNull,
    time::{Duration, Instant},
};
unsafe extern "C" {
    fn lbp_initialize() -> i32;
    fn lbp_cancelled() -> i32;
    fn lbp_raster_open(fd: i32) -> *mut c_void;
    fn lbp_raster_close(raster: *mut c_void);
    fn lbp_raster_header(
        raster: *mut c_void,
        values: *mut u32,
        count: usize,
        media: *mut u8,
        capacity: usize,
    ) -> i32;
    fn lbp_raster_line(raster: *mut c_void, data: *mut u8, size: usize) -> i32;
    fn lbp_device_id(data: *mut u8, capacity: usize) -> i32;
    fn lbp_back_read(data: *mut u8, capacity: usize, timeout: f64) -> i32;
    fn lbp_write(data: *const u8, size: usize) -> i32;
    fn lbp_timestamp(out: *mut u16, count: usize) -> i32;
}
pub fn check() -> Result<()> {
    // SAFETY: No pointers. Reads only the adapter's sig_atomic_t flag.
    if unsafe { lbp_cancelled() } != 0 {
        Err(Error::Cancelled)
    } else {
        Ok(())
    }
}
pub struct Cups {
    start: Instant,
}
impl Cups {
    pub fn new() -> Result<Self> {
        // SAFETY: Called once in the single-threaded filter before any I/O.
        if unsafe { lbp_initialize() } != 0 {
            return Err(Error::Io);
        }
        Ok(Self {
            start: Instant::now(),
        })
    }
}
impl Transport for Cups {
    fn write(&mut self, packet: &[u8]) -> Result<()> {
        check()?;
        // SAFETY: Immutable slice is live for the call; adapter does not retain it.
        match unsafe { lbp_write(packet.as_ptr(), packet.len()) } {
            0 => Ok(()),
            -2 => Err(Error::Timeout),
            -3 => Err(Error::Cancelled),
            _ => Err(Error::Io),
        }
    }
    fn read(&mut self, buffer: &mut [u8], timeout: Duration) -> Result<usize> {
        let deadline = Instant::now() + timeout;
        loop {
            check()?;
            let left = deadline
                .checked_duration_since(Instant::now())
                .filter(|d| !d.is_zero())
                .ok_or(Error::Timeout)?;
            // SAFETY: Exclusive initialized slice; adapter honors its exact capacity,
            // writes at most that many bytes, and does not retain the pointer.
            let n = unsafe {
                lbp_back_read(
                    buffer.as_mut_ptr(),
                    buffer.len(),
                    left.as_secs_f64().min(1.0),
                )
            };
            check()?;
            if n > 0 {
                return Ok(n as usize);
            }
            if n != 0 && n != -2 {
                return Err(Error::Io);
            }
        }
    }
    fn device_id(&mut self) -> Result<Vec<u8>> {
        let deadline = Instant::now() + Duration::from_secs(60);
        let mut data = vec![0; 4097];
        loop {
            check()?;
            if Instant::now() >= deadline {
                return Err(Error::Timeout);
            }
            // SAFETY: Exclusive 4097-byte initialized allocation, live throughout call.
            let n = unsafe { lbp_device_id(data.as_mut_ptr(), data.len()) };
            check()?;
            if n > 0 {
                let n = usize::try_from(n).map_err(|_| Error::Io)?;
                if n > 4096 {
                    return Err(Error::Capacity);
                }
                data.truncate(n);
                return Ok(data);
            }
            if n != 0 && n != -2 {
                return Err(Error::Io);
            }
            self.delay(Duration::from_millis(100))?;
        }
    }
    fn now(&self) -> Duration {
        self.start.elapsed()
    }
    fn check(&self) -> Result<()> {
        check()
    }
    fn delay(&mut self, duration: Duration) -> Result<()> {
        let deadline = Instant::now() + duration;
        loop {
            check()?;
            let Some(left) = deadline.checked_duration_since(Instant::now()) else {
                return Ok(());
            };
            std::thread::sleep(left.min(Duration::from_millis(25)));
        }
    }
    fn timestamp(&self) -> Result<[u16; 6]> {
        let mut time = [0; 6];
        // SAFETY: Exclusive six-element u16 array; adapter checks element count.
        if unsafe { lbp_timestamp(time.as_mut_ptr(), time.len()) } != 0 {
            return Err(Error::Io);
        }
        Ok(time)
    }
}
pub struct CupsRaster {
    handle: NonNull<c_void>,
    _file: File,
}
impl CupsRaster {
    pub fn open(file: File) -> Result<Self> {
        // SAFETY: Owned File keeps fd live until after cupsRasterClose in Drop.
        let handle = NonNull::new(unsafe { lbp_raster_open(file.as_raw_fd()) }).ok_or(Error::Io)?;
        Ok(Self {
            handle,
            _file: file,
        })
    }
}
impl Raster for CupsRaster {
    fn header(&mut self) -> Result<Option<Header>> {
        check()?;
        let mut header = Header {
            values: [0; 20],
            media: [0; 64],
        };
        // SAFETY: Handle is uniquely owned and live. Both output arrays have the
        // exact element capacities passed. No pointers escape the synchronous call.
        let result = unsafe {
            lbp_raster_header(
                self.handle.as_ptr(),
                header.values.as_mut_ptr(),
                header.values.len(),
                header.media.as_mut_ptr(),
                header.media.len(),
            )
        };
        check()?;
        match result {
            1 => Ok(Some(header)),
            0 => Ok(None),
            _ => Err(Error::InvalidRaster),
        }
    }
    fn read_line(&mut self, out: &mut [u8]) -> Result<()> {
        check()?;
        // SAFETY: Live handle and exclusive initialized output slice. The adapter
        // rejects lengths outside 1..=1024 and CUPS receives the same byte count.
        let result = unsafe { lbp_raster_line(self.handle.as_ptr(), out.as_mut_ptr(), out.len()) };
        check()?;
        if result == 0 {
            Ok(())
        } else {
            Err(Error::Truncated)
        }
    }
}
impl Drop for CupsRaster {
    fn drop(&mut self) {
        // SAFETY: This is the unique successful open handle, closed exactly once.
        // cupsRasterClose releases the raster object, not the caller-owned fd.
        unsafe { lbp_raster_close(self.handle.as_ptr()) };
    }
}
