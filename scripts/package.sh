#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/AngerRate.app"
DMG_PATH="$DIST_DIR/AngerRate-0.1.1.dmg"

cd "$PROJECT_DIR"
swift build -c release --product AngerRate
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_DIR/AngerRate"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Release executable was not produced: $EXECUTABLE" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
if [[ -e "$APP_BUNDLE" ]]; then
    /bin/rm -rf "$APP_BUNDLE"
fi
if [[ -e "$DMG_PATH" ]]; then
    /bin/rm -f "$DMG_PATH"
fi

CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"
"$SCRIPT_DIR/build-icon.sh" "$CONTENTS/Resources/AppIcon.icns"
/usr/bin/ditto "$EXECUTABLE" "$MACOS_DIR/AngerRate"
chmod 755 "$MACOS_DIR/AngerRate"

PLIST="$CONTENTS/Info.plist"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
/usr/bin/plutil -insert CFBundleLocalizations -json '["en","ko"]' "$PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string AngerRate "$PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string AngerRate "$PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string app.angerrate.desktop "$PLIST"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
/usr/bin/plutil -insert CFBundleName -string AngerRate "$PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.1 "$PLIST"
/usr/bin/plutil -insert CFBundleVersion -string 2 "$PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$PLIST"
/usr/bin/plutil -insert LSUIElement -bool true "$PLIST"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$PLIST"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    /usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/AngerRate-DMG.XXXXXX")"
cleanup() {
    /bin/rm -rf "$DMG_STAGE"
}
trap cleanup EXIT
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGE/AngerRate.app"
/bin/ln -s /Applications "$DMG_STAGE/Applications"
/usr/bin/hdiutil create \
    -volname AngerRate \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

echo "Created $APP_BUNDLE"
echo "Created $DMG_PATH"
