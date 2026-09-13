#!/bin/bash
# Read-only diagnostics. No document names, serial numbers or network changes.
set -uo pipefail
sw_vers
uname -m
filter=/usr/libexec/cups/filter/rastertocapt-lbp2900
if [ -f "$filter" ]; then
  stat -f '%Su:%Sg %Lp %N' "$filter"
  codesign --verify --strict --verbose=2 "$filter"
  otool -L "$filter"
else echo 'Fork driver is not installed.'; fi
lpstat -p Canon_LBP2900_Slpixe 2>/dev/null || echo 'Fork queue is not configured.'
for path in /Library/LaunchDaemons/com.lbp2900.heal.plist "$HOME/Library/LaunchAgents/com.lbp2900.progress.plist"; do
  if [ -e "$path" ]; then echo 'An original-upstream background service remains. See docs/MIGRATION.md.'; fi
done
