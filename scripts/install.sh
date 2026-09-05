#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_APP="${1:-$PROJECT_DIR/dist/AngerRate.app}"
INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/AngerRate.app"

if [[ ! -d "$SOURCE_APP" || ! -x "$SOURCE_APP/Contents/MacOS/AngerRate" ]]; then
    echo "AngerRate.app not found or incomplete: $SOURCE_APP" >&2
    echo "Run scripts/package.sh first, or pass the app bundle path." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
STAGED_APP="$(mktemp -d "$INSTALL_DIR/.AngerRate-install.XXXXXX")/AngerRate.app"
cleanup() {
    if [[ -d "$(dirname "$STAGED_APP")" ]]; then
        /bin/rm -rf "$(dirname "$STAGED_APP")"
    fi
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"

if [[ -e "$TARGET_APP" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_APP="$INSTALL_DIR/AngerRate.app.backup-$TIMESTAMP"
    SUFFIX=1
    while [[ -e "$BACKUP_APP" ]]; do
        BACKUP_APP="$INSTALL_DIR/AngerRate.app.backup-$TIMESTAMP-$SUFFIX"
        SUFFIX=$((SUFFIX + 1))
    done
    /bin/mv "$TARGET_APP" "$BACKUP_APP"
    echo "Previous app backed up to $BACKUP_APP"
fi

/bin/mv "$STAGED_APP" "$TARGET_APP"
if [[ "${ANGER_RATE_DIAGNOSE:-0}" == "1" ]]; then
    /usr/bin/open "$TARGET_APP" --args --diagnose
else
    /usr/bin/open "$TARGET_APP"
fi
echo "Installed $TARGET_APP"
