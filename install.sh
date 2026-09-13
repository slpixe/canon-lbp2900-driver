#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")"
usage() { cat <<'HELP'
Usage:
  ./install.sh --driver [--uri 'usb://Canon/LBP2900?...'] [--dry-run]
  ./install.sh --menubar [--dry-run]

Each component is optional and built locally before installation. Driver-only
installation needs administrator access; the menu app installs in ~/Applications.
No background root service, automatic login item, or security-setting change.
Omit --uri to install driver files without creating a printer queue.
Use /usr/sbin/lpinfo -v to read the exact URI of your connected printer.
HELP
}
[ "$#" -gt 0 ] || { usage; exit 0; }
[ "$(id -u)" -ne 0 ] || { echo 'Run without sudo; only driver installation requests it.' >&2; exit 1; }
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then echo "Installation requires Apple Silicon macOS." >&2; exit 1; fi
version="$(sw_vers -productVersion)"
[ "${version%%.*}" -ge 15 ] || { echo "Installation requires macOS 15 or later." >&2; exit 1; }
component='' uri='' dry=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --driver|--menubar) [ -z "$component" ] || { usage; exit 2; }; component="$1";;
    --uri) [ "$#" -ge 2 ] || exit 2; shift; uri="$1";;
    --dry-run) dry=true;;
    --help|-h) usage; exit 0;;
    *) usage; exit 2;;
  esac
  shift
done
[ -n "$component" ] || { usage; exit 2; }
if [ "$component" = --driver ]; then
  if ! $dry; then ./build.sh --driver; fi
  args=(install "$PWD/build/rastertocapt-lbp2900" "$PWD/ppd/CanonLBP-2900-3000.ppd" "$uri")
  if $dry; then /bin/bash scripts/install-driver.sh --dry-run "${args[@]}";
  else /usr/bin/sudo /bin/bash "$PWD/scripts/install-driver.sh" "${args[@]}"; fi
else
  [ -z "$uri" ] || { echo '--uri only applies to --driver.' >&2; exit 2; }
  if $dry; then echo 'Would build and copy LBP2900Progress.app into ~/Applications. No auto-start.'; exit 0; fi
  ./build.sh --menubar
  target="$HOME/Applications"
  [ ! -L "$target" ] || { echo 'Refusing a symlinked Applications directory.' >&2; exit 1; }
  mkdir -p "$target"
  [ "$(stat -f %u "$target")" = "$(id -u)" ] || exit 1
  destination="$target/LBP2900Progress.app"
  if [ -e "$destination" ] || [ -L "$destination" ]; then echo 'An app already exists there. Quit and move it to Trash before installing a replacement.' >&2; exit 1; fi
  /usr/bin/ditto build/LBP2900Progress.app "$destination"
  echo "Installed $destination. Open it when needed; login startup is optional in its menu."
fi
