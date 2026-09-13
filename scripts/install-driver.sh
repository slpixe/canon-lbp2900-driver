#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Narrow privileged helper. No builds, downloads, discovery fallback or services.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 022
rust=false
if [ "${1:-}" = --rust ]; then rust=true; shift; fi
dry=false
if [ "${1:-}" = --dry-run ]; then dry=true; shift; fi
fail() { echo "Installation stopped: $*" >&2; exit 1; }
run() { if $dry; then printf 'Would run:'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
filter=/usr/libexec/cups/filter/rastertocapt-lbp2900
ppd=/Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Slpixe.ppd
queue=Canon_LBP2900_Slpixe
description='Canon LBP2900 (community driver)'
if $rust; then
  filter=/usr/libexec/cups/filter/rastertocapt-lbp2900-rust
  ppd=/Library/Printers/PPDs/Contents/Resources/CanonLBP2900-Rust-Experimental.ppd
  queue=Canon_LBP2900_Rust_Experiment
  description='Canon LBP2900 (Rust experiment)'
fi
verb="${1:-}"
[ "$verb" = install ] || [ "$verb" = remove ] || fail 'Unknown operation.'
shift
if [ "$verb" = install ]; then
  [ "$#" -eq 3 ] || fail 'Expected filter, PPD and optional USB URI.'
  source_filter="$1"; source_ppd="$2"; uri="$3"
  case "$source_filter:$source_ppd" in /*:/*) ;; *) fail 'Source paths must be absolute.';; esac
  if [ -n "$uri" ]; then
    case "$uri" in usb://Canon/LBP2900\?*|usb://Canon/LBP2900|usb://Canon/LBP%202900\?*) ;; *) fail 'An exact Canon LBP2900 USB URI is required.';; esac
    if [[ "$uri" =~ [[:space:][:cntrl:]] ]]; then fail 'URI contains whitespace/control characters.'; fi
    if ! $dry; then
      found=false
      while read -r kind address rest; do
        if [ "$kind" = direct ] && [ "$address" = "$uri" ]; then found=true; fi
      done < <(/usr/sbin/lpinfo --include-schemes usb --timeout 5 -v)
      $found || fail 'That exact printer is not connected. Install without --uri, or reconnect it.'
    fi
  fi
else
  [ "$#" -eq 0 ] || fail 'remove takes no further arguments.'
fi
# Refuse symlinked, non-root-owned or group/world-writable installation paths,
# checking every ancestor (not only the final destination).
check_directory() {
  local path="$1" parent mode
  [ "$path" = / ] && return
  parent="${path%/*}"; [ -n "$parent" ] || parent=/
  check_directory "$parent"
  [ ! -L "$path" ] || fail "Symlink in system path: $path"
  if [ ! -e "$path" ]; then run /usr/bin/install -d -o root -g wheel -m 0755 "$path"; return; fi
  [ -d "$path" ] || fail "Not a directory: $path"
  [ "$(stat -f %u "$path")" = 0 ] || fail "Directory is not root-owned: $path"
  mode="$(stat -f %Lp "$path")"
  (( (8#$mode & 0022) == 0 )) || fail "Directory is writable by other users: $path"
}
check_target() {
  [ ! -L "$1" ] || fail "Symlink destination: $1"
  if [ -e "$1" ]; then
    if [ ! -f "$1" ] || [ "$(stat -f %u "$1")" != 0 ]; then fail "Unexpected destination: $1"; fi
  fi
}
if ! $dry; then [ "$(id -u)" -eq 0 ] || fail 'This helper needs administrator privileges.'; fi
# Refuse replacement/removal if either variant reports outstanding jobs.
# Inspect existence first; do not mistake a failed job query for an empty queue.
if ! $dry; then
  for q in Canon_LBP2900_Slpixe Canon_LBP2900_Rust_Experiment; do
    if /usr/bin/lpstat -p "$q" >/dev/null 2>&1; then
      jobs="$(/usr/bin/lpstat -o "$q")" || fail 'Could not check queued jobs.'
      [ -z "$jobs" ] || fail 'Finish or cancel jobs in both Canon queues before installation or removal.'
    fi
  done
fi
check_directory "${filter%/*}"
check_directory "${ppd%/*}"
check_target "$filter"; check_target "$ppd"
if [ "$verb" = remove ]; then
  if $dry || /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then run /usr/sbin/lpadmin -x "$queue"; fi
  run /bin/rm -f "$filter" "$ppd"
  if ! $rust && ! $dry && /usr/sbin/pkgutil --pkg-info com.slpixe.canon-lbp2900.driver >/dev/null 2>&1; then
    /usr/sbin/pkgutil --forget com.slpixe.canon-lbp2900.driver
  fi
  if $dry; then echo 'Dry run complete. Nothing removed.'; else echo 'Driver removal complete. The optional menu app is separate.'; fi
  exit 0
fi
if ! $dry; then
  for input in "$source_filter" "$source_ppd"; do
    if [ ! -f "$input" ] || [ -L "$input" ]; then fail "Not a regular source file: $input"; fi
    owner="$(stat -f %u "$input")"
    [ "$owner" = "${SUDO_UID:-0}" ] || [ "$owner" = 0 ] || fail 'Source belongs to another user.'
  done
  /usr/bin/codesign --verify --strict "$source_filter"
fi
# Create each replacement in its root-controlled destination directory, then
# rename it atomically. A failure never publishes a partially copied executable.
atomic_install() {
  local source="$1" destination="$2" mode="$3" temporary
  if $dry; then run /usr/bin/install -o root -g wheel -m "$mode" "$source" "$destination"; return; fi
  temporary="$(mktemp "${destination}.XXXXXXXX")"
  if /usr/bin/install -o root -g wheel -m "$mode" "$source" "$temporary" && /bin/mv -f "$temporary" "$destination"; then :
  else /bin/rm -f "$temporary"; fail "Could not install $destination"; fi
}
atomic_install "$source_filter" "$filter" 0755
atomic_install "$source_ppd" "$ppd" 0644
if [ -n "$uri" ]; then
  run /usr/sbin/lpadmin -p "$queue" -v "$uri" -P "$ppd" -E \
    -D "$description" -o printer-is-shared=false -o printer-error-policy=stop-printer
fi
if $dry; then echo 'Dry run complete. Nothing installed.'; else echo 'Driver installed. No daemon or login application was added.'; fi
