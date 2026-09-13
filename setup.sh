#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build as the normal user; opening setup does not install a driver.
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  --help|-h) echo 'Usage: ./setup.sh [--rust] — build and open the printer-selection window.'; exit 0;;
  --rust) [ "$#" -eq 1 ] || exit 2; ./build.sh --menubar --with-rust;;
  '') ./build.sh --menubar;;
  *) echo 'Use install.sh for CLI installation; setup.sh [--rust] opens graphical setup.' >&2; exit 2;;
esac
/usr/bin/open -n build/LBP2900Progress.app --args --setup-only
