// SPDX-License-Identifier: GPL-3.0-or-later
mod cups;
use lbp2900_rust::{
    Error, Result,
    job::{Driver, Event},
};
use std::{fs::File, os::fd::AsFd};
fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 6 && args.len() != 7 {
        eprintln!(
            "Usage: rastertocapt-lbp2900-rust job-id user title copies options [raster-file]"
        );
        return Err(Error::InvalidRaster);
    }
    let io = cups::Cups::new()?;
    let file = if args.len() == 7 {
        File::open(&args[6]).map_err(|_| Error::Io)?
    } else {
        File::from(
            std::io::stdin()
                .as_fd()
                .try_clone_to_owned()
                .map_err(|_| Error::Io)?,
        )
    };
    let mut raster = cups::CupsRaster::open(file)?;
    Driver::new(io).print(&mut raster, |event| match event {
        Event::MediaEmpty(empty) => {
            eprintln!("STATE: {}media-empty", if empty { "+" } else { "-" })
        }
        Event::PageCompleted(page) => eprintln!("PAGE: {page} 1"),
    })
}
fn main() {
    if let Err(error) = run() {
        eprintln!("ERROR: experimental Rust CAPT filter: {error}");
        std::process::exit(1);
    }
}
