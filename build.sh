#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(id -u)" -eq 0 ]; then echo 'Build as your normal user, without sudo.' >&2; exit 1; fi
case "${1:---driver}" in --driver|--menubar|--all) component="${1:---driver}";; *) echo 'Usage: ./build.sh [--driver|--menubar|--all]'; exit 2;; esac
[ "$#" -le 1 ] || exit 2
[ "$(uname -s)" = Darwin ] || { echo 'macOS is required to build the distributable.' >&2; exit 1; }
# Never infer or download dependencies. Apple's installed tools are sufficient.
xcrun --find clang >/dev/null
mkdir -p build
if [ "$component" != --menubar ]; then
  xcrun clang -D_DARWIN_C_SOURCE -std=gnu11 -O2 -Wall -Wextra -Werror \
    -fstack-protector-strong -D_FORTIFY_SOURCE=2 -ftrivial-auto-var-init=zero \
    -arch arm64 -mmacosx-version-min=15.0 -ffile-prefix-map="$PWD"=. \
    captdriver/src/*.c -lcups -o build/rastertocapt-lbp2900
  /usr/bin/codesign --verify --strict build/rastertocapt-lbp2900
  echo 'Built build/rastertocapt-lbp2900 (Apple Silicon, macOS 15+). Nothing installed.'
fi
if [ "$component" != --driver ]; then
  app=build/LBP2900Progress.app
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp LICENSE "$app/Contents/Resources/LICENSE.txt"
  printf 'GPLv3 source: https://github.com/slpixe/canon-lbp2900-driver\nBuild commit: %s\nLocal edits, if any, are described in the build metadata.\n' "$(git rev-parse HEAD)" > "$app/Contents/Resources/SOURCE.txt"
  cp menubar/Info.plist "$app/Contents/Info.plist"
  xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path build/swift-cache \
    menubar/ProgressModel.swift menubar/main.swift -o "$app/Contents/MacOS/LBP2900Progress"
  # Local build identity only; not Developer ID or notarization.
  /usr/bin/codesign --force --sign - "$app"
  /usr/bin/codesign --verify --strict "$app"
  echo "Built $app (local ad hoc signature). Nothing installed or launched."
fi
