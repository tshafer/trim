#!/bin/bash
# Builds Trim.app, installs it to /Applications, and launches it.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(mktemp -d)"
APP="$(./build-app.sh --dest "$STAGE" "$@")"

DEST="/Applications/Trim.app"
echo "› Installing to $DEST"
/usr/bin/pkill -x Trim 2>/dev/null || true
/bin/sleep 0.3
rm -rf "$DEST"
/bin/mv "$APP" "$DEST"
rm -rf "$STAGE"
open "$DEST"
echo "› Installed and launched: $DEST"
