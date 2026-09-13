#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
flags=(-D_DARWIN_C_SOURCE -std=gnu11 -g -O1 -Wall -Wextra -fsanitize=address,undefined -fno-omit-frame-pointer -Icaptdriver/src -Icaptdriver/tests)
cc "${flags[@]}" tests/protocol.c captdriver/src/capt-command.c captdriver/src/capt-status.c captdriver/src/runtime.c -o build/tests/protocol
cc "${flags[@]}" tests/codec.c captdriver/src/hiscoa-compress.c captdriver/src/hiscoa-common.c captdriver/src/paper.c captdriver/src/runtime.c captdriver/tests/hiscoa-decompress.c -o build/tests/codec
cc "${flags[@]}" tests/device-id.c captdriver/src/printer.c captdriver/src/runtime.c -o build/tests/device-id
python3 tests/run.py
if [ "$(uname -s)" = Darwin ]; then
  xcrun swiftc -module-cache-path build/swift-cache menubar/ProgressModel.swift tests/menu-model.swift -o build/tests/menu-model
  build/tests/menu-model
fi
