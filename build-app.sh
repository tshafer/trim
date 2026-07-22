#!/bin/bash
# Builds Trim.app into a destination directory. Shared by make-app.sh (local
# install) and the release workflow (which packages the result into a .dmg).
#
#   ./build-app.sh [--version 0.2] [--dest DIR]
#
# Prints the path of the assembled bundle on stdout.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
DEST=""
UNIVERSAL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="${2:-}"; shift 2 ;;
    --dest)      DEST="${2:-}";    shift 2 ;;
    --universal) UNIVERSAL=1;      shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# A tag like "v0.2" is the usual input; the plist wants a bare "0.2".
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
[ -n "$DEST" ] || DEST="$(mktemp -d)"

# Local installs build for this machine; anything shipped is universal so it
# runs on Intel Macs too.
if [ -n "$UNIVERSAL" ]; then
  echo "› Building universal release binary…" >&2
  swift build -c release --arch arm64 --arch x86_64 >&2
  BIN=".build/apple/Products/Release/Trim"
else
  echo "› Building release binary…" >&2
  swift build -c release >&2
  BIN=".build/release/Trim"
fi

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…" >&2
  swift make-icon.swift >&2
fi

APP="$DEST/Trim.app"
echo "› Assembling $APP (version $VERSION, build $BUILD)…" >&2
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN"           "$APP/Contents/MacOS/Trim"
cp AppIcon.icns        "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Trim</string>
    <key>CFBundleDisplayName</key>          <string>Trim</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.trim</string>
    <key>CFBundleVersion</key>              <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleExecutable</key>           <string>Trim</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>   <array><string>MacOSX</string></array>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Tom Shafer</string>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
