#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 0 ] || { echo 'Usage: ./scripts/build-rust.sh' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Build without sudo.' >&2; exit 1; }
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo 'Native Apple Silicon macOS required.' >&2; exit 1
fi
export RUSTUP_AUTO_INSTALL=0
cd rust
# This command never installs a toolchain or fetches crates. Install the pinned
# toolchain yourself first; cd rust makes rustup honor rust-toolchain.toml.
[ "$(rustc --version | awk '{print $2}')" = 1.98.1 ] || { echo 'Rust 1.98.1 is required.' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=15.0
cargo build --release --locked --offline --features cups --bin rastertocapt-lbp2900-rust
mkdir -p ../build/rust
cp target/release/rastertocapt-lbp2900-rust ../build/rust/
/usr/bin/codesign --verify --strict ../build/rust/rastertocapt-lbp2900-rust
/usr/bin/sed \
  -e 's/rastertocapt-lbp2900"/rastertocapt-lbp2900-rust"/' \
  -e 's/Canon Inc LBP2900\/LBP3000 r2c/Canon LBP2900 Rust EXPERIMENTAL/g' \
  ../ppd/CanonLBP-2900-3000.ppd > ../build/rust/CanonLBP2900-Rust-Experimental.ppd
echo 'Built Rust filter and separate experimental PPD in build/rust/. Nothing installed.'
