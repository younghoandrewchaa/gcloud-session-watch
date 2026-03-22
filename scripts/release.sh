#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/GcloudSessionWatch.xcodeproj/project.pbxproj" | awk -F' = ' '{gsub(/[; ]/, "", $2); print $2}')
TAG="v${VERSION}"
DMG="$ROOT/build/GcloudSessionWatch-${VERSION}.dmg"

if [ ! -f "$DMG" ]; then
    echo "Error: DMG not found at $DMG"
    echo "Run ./scripts/build-dmg.sh first."
    exit 1
fi

if git rev-parse "$TAG" &>/dev/null; then
    echo "Error: Tag $TAG already exists. Bump MARKETING_VERSION before releasing."
    exit 1
fi

echo "==> Tagging $TAG..."
git tag "$TAG"

echo "==> Pushing tag..."
git push origin "$TAG"

echo "==> Creating GitHub release $TAG..."
gh release create "$TAG" \
    "$DMG" \
    --title "$TAG" \
    --generate-notes

echo ""
echo "Done: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
