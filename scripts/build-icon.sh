#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="${1:-$PROJECT_DIR/dist/AppIcon.icns}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/AngerRate-Icon.XXXXXX")"
trap '/bin/rm -rf "$STAGE"' EXIT
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"
for SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$SIZE" "$SIZE" "$PROJECT_DIR/assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    /usr/bin/sips -z "$DOUBLE" "$DOUBLE" "$PROJECT_DIR/assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
