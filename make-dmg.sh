#!/bin/bash
# Builds Trim.app and packages it into a distributable disk image with an
# /Applications drop target. Used by the release workflow; runs locally too.
#
#   ./make-dmg.sh [--version 0.2] [--out DIR]
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
OUT="dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}";     shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

VERSION="${VERSION#v}"
[ -n "$VERSION" ] || VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/root"
mkdir -p "$ROOT"

APP="$(./build-app.sh --version "$VERSION" --dest "$ROOT" --universal)"
ln -s /Applications "$ROOT/Applications"

mkdir -p "$OUT"
DMG="$OUT/Trim-$VERSION.dmg"
rm -f "$DMG"
echo "› Creating ${DMG}…" >&2
hdiutil create \
  -volname "Trim $VERSION" \
  -srcfolder "$ROOT" \
  -fs HFS+ \
  -format UDZO \
  -ov "$DMG" >/dev/null

echo "$DMG"
