#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
export RUSTUP_AUTO_INSTALL=0
mkdir -p build/tests
clang -D_DARWIN_C_SOURCE -std=gnu11 -g -O1 -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer -Icaptdriver/src \
  tests/rust-oracle.c captdriver/src/hiscoa-compress.c captdriver/src/hiscoa-common.c \
  -o build/tests/rust-oracle
export LBP_C_ORACLE="$PWD/build/tests/rust-oracle"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
export MACOSX_DEPLOYMENT_TARGET=15.0
cd rust
cargo fmt --check
cargo test --locked --offline -- --include-ignored
cargo test --release --locked --offline -- --include-ignored
cargo clippy --all-targets --locked --offline -- -D warnings
cargo test --locked --offline --features cups -- --include-ignored
cargo clippy --all-targets --features cups --locked --offline -- -D warnings
cargo build --release --locked --offline --features cups --bin rastertocapt-lbp2900-rust
cd ..
clang -D_DARWIN_C_SOURCE -std=gnu11 -O2 -Wall -Wextra -Werror tests/rust-raster.c -lcups -o build/tests/rust-raster
clang -D_DARWIN_C_SOURCE -std=gnu11 -O2 -Wall -Wextra -Werror captdriver/src/*.c -lcups -o build/tests/c-reference
clang -D_DARWIN_C_SOURCE -D_POSIX_C_SOURCE=200809L -std=c11 -g -O1 -Wall -Wextra -Werror \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  tests/rust-adapter.c rust/adapter/cups.c -lcups -o build/tests/rust-adapter
python3 tests/rust-integration.py
