#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
EXPORT_OPTIONS="$ROOT/ExportOptions.plist"
VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/GcloudSessionWatch.xcodeproj/project.pbxproj" | awk -F' = ' '{gsub(/[; ]/, "", $2); print $2}')
ARCHIVE="$ROOT/build/GcloudSessionWatch.xcarchive"
EXPORT_DIR="$ROOT/build/export"
DMG="$ROOT/build/GcloudSessionWatch-${VERSION}.dmg"

if [ ! -f "$EXPORT_OPTIONS" ]; then
    echo "Error: ExportOptions.plist not found."
    echo "Copy ExportOptions.plist.template to ExportOptions.plist and fill in your Team ID."
    exit 1
fi

echo "==> Cleaning previous archive..."
rm -rf "$ARCHIVE" "$EXPORT_DIR"

TEAM_ID=$(plutil -extract teamID raw "$EXPORT_OPTIONS")
if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "YOUR_TEAM_ID" ]; then
    echo "Error: teamID in ExportOptions.plist is missing or not set."
    exit 1
fi

echo "==> Archiving (team: $TEAM_ID)..."
xcodebuild archive \
    -scheme GcloudSessionWatch \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    SKIP_INSTALL=NO \
    INSTALL_PATH=/Applications

echo "==> Exporting and notarizing..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR"

echo "==> Staging DMG contents..."
STAGING="$ROOT/build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$EXPORT_DIR/Gcloud Session Watch.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "GcloudSessionWatch" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"

echo ""
echo "Done: $DMG"
