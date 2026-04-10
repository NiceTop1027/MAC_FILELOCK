#!/bin/bash
set -euo pipefail

APP="FileLock"
DIST="dist"
BUNDLE="$DIST/$APP.app"
DMG="$DIST/$APP.dmg"
STAGE="$DIST/dmg-root"

if [ ! -d "$BUNDLE" ]; then
  echo "앱 번들을 먼저 빌드해야 합니다: $BUNDLE"
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo "✓ DMG 생성 완료: $DMG"
