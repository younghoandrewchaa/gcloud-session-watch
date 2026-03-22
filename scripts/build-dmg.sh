#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
EXPORT_OPTIONS="$ROOT/ExportOptions.plist"
ARCHIVE="$ROOT/build/GcloudSessionWatch.xcarchive"
EXPORT_DIR="$ROOT/build/export"
DMG="$ROOT/build/GcloudSessionWatch.dmg"

if [ ! -f "$EXPORT_OPTIONS" ]; then
    echo "Error: ExportOptions.plist not found."
    echo "Copy ExportOptions.plist.template to ExportOptions.plist and fill in your Team ID."
    exit 1
fi

echo "==> Archiving..."
xcodebuild archive \
    -scheme GcloudSessionWatch \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic

echo "==> Exporting and notarizing..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR"

echo "==> Creating DMG..."
hdiutil create \
    -volname "GcloudSessionWatch" \
    -srcfolder "$EXPORT_DIR/GcloudSessionWatch.app" \
    -ov -format UDZO \
    "$DMG"

echo ""
echo "Done: $DMG"
