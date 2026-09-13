// SPDX-License-Identifier: GPL-3.0-or-later
// Protocol and codec derived from captdriver by Alexey Galakhov (2013)
// and Alexei Gordeev (2016); see ../docs/PROVENANCE.md and repository LICENSE.
#![forbid(unsafe_code)]
pub mod codec;
pub mod job;
pub mod page;
pub mod protocol;
pub mod status;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidPacket,
    UnexpectedCommand,
    Truncated,
    Capacity,
    InvalidStatus,
    InvalidRaster,
    UnsupportedPrinter,
    Io,
    Timeout,
    Cancelled,
    NoPages,
    RetryLimit,
}
pub type Result<T> = std::result::Result<T, Error>;
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for Error {}
