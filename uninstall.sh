#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  --driver)
    if [ "${2:-}" = --dry-run ]; then exec /bin/bash scripts/install-driver.sh --dry-run remove; fi
    [ "$#" -eq 1 ] || exit 2
    exec /usr/bin/sudo /bin/bash "$PWD/scripts/install-driver.sh" remove;;
  --menubar)
    echo 'In the app menu, disable Start at Login, then Quit. Move ~/Applications/LBP2900Progress.app to Trash.';;
  *) echo 'Usage: ./uninstall.sh --driver [--dry-run] | --menubar';;
esac
