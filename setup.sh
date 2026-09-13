#!/bin/bash
# Compatibility entry point: show explicit choices rather than install everything.
set -euo pipefail
exec /bin/bash "$(dirname "$0")/install.sh" "$@"
