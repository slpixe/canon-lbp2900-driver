#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# No installation. Signing identities remain in the caller's Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
development=false
case "${1:-}" in --development) development=true;; '') ;; *) echo 'Usage: scripts/package.sh [--development]'; exit 2;; esac
[ "$#" -le 1 ] || exit 2
if ! $development; then
  : "${DEVELOPER_ID_APPLICATION:?Set your Developer ID Application identity, or use --development}"
  : "${DEVELOPER_ID_INSTALLER:?Set your Developer ID Installer identity, or use --development}"
fi
./build.sh --all
version="$(cat VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || exit 2
mkdir -p dist
stage="$(mktemp -d "$PWD/build/package.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/usr/libexec/cups/filter" "$stage/root/Library/Printers/PPDs/Contents/Resources"
install -m 0755 build/rastertocapt-lbp2900 "$stage/root/usr/libexec/cups/filter/rastertocapt-lbp2900"
install -m 0644 ppd/CanonLBP-2900-3000.ppd "$stage/root/Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Slpixe.ppd"
suffix=UNSIGNED

if ! $development; then
  suffix=SIGNED
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$stage/root/usr/libexec/cups/filter/rastertocapt-lbp2900"
  # Sign the embedded setup payload before sealing the outer app.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/LBP2900Progress.app/Contents/Resources/DriverPayload/rastertocapt-lbp2900
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/LBP2900Progress.app

fi
package_signed() {
  local tool="$1"; shift
  if $development; then "$tool" "$@"; else "$tool" --sign "$DEVELOPER_ID_INSTALLER" "$@"; fi
}
pkg="dist/canon-lbp2900-driver-$version-$suffix.pkg"
# Payload only: no preinstall/postinstall scripts, daemons or queue discovery.
package_signed pkgbuild --root "$stage/root" --ownership recommended --install-location / \
  --identifier com.slpixe.canon-lbp2900.driver --version "${version%%-*}" \
  "$stage/driver.pkg"
# A distribution wrapper gates the supported CPU/OS before installation.
cat > "$stage/distribution.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
<title>Canon LBP2900 — community driver (preview)</title>
<options customize="never" require-scripts="false" hostArchitectures="arm64"/>
<volume-check><allowed-os-versions><os-version min="15.0"/></allowed-os-versions></volume-check>
<readme file="README.html"/>
<license file="LICENSE.txt"/>
<choices-outline><line choice="driver"/></choices-outline>
<choice id="driver" title="Printer driver only"><pkg-ref id="com.slpixe.canon-lbp2900.driver"/></choice>
<pkg-ref id="com.slpixe.canon-lbp2900.driver" version="${version%%-*}">driver.pkg</pkg-ref>
</installer-gui-script>
EOF
package_signed productbuild --distribution "$stage/distribution.xml" --resources docs/package-resources \
  --package-path "$stage" "$pkg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/LBP2900Progress.app "dist/LBP2900Progress-$version-$suffix.zip"
python3 - "$pkg" "$development" <<'PY'
import json, platform, subprocess, sys
from pathlib import Path
info = {
 'source_commit': subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'source_dirty': bool(subprocess.check_output(['git','status','--porcelain'],text=True)),
 'version': Path('VERSION').read_text().strip(),
 'architecture': 'arm64', 'minimum_macos': '15.0', 'development_unsigned': sys.argv[2]=='true',
 'build_host': platform.platform(),
 'clang': subprocess.check_output(['xcrun','clang','--version'],text=True).splitlines()[0],
 'swift': subprocess.check_output(['xcrun','swiftc','--version'],text=True).splitlines()[0],
 'sdk': subprocess.check_output(['xcrun','--show-sdk-version'],text=True).strip(),
 'printer_hardware_tested': False,
}
Path('dist/build-info.json').write_text(json.dumps(info,indent=2)+'\n')
PY
(cd dist && shasum -a 256 "${pkg#dist/}" "LBP2900Progress-$version-$suffix.zip" build-info.json > SHA256SUMS)
echo 'Packages created; nothing installed. See docs/RELEASES.md before distribution.'
