#!/bin/bash
# 새 버전 릴리스용 appcast.xml 자동 생성
# 사용법: bash publish_update.sh <버전> <DMG경로>
# 예시:   bash publish_update.sh 1.0.4 dist/FileLock.dmg
set -e

VERSION="$1"
DMG_PATH="$2"
VENDOR_DIR="vendor"
APPCAST_FILE="docs/appcast.xml"
RELEASE_URL_PREFIX="https://github.com/NiceTop1027/MAC_FILELOCK/releases/download/v$VERSION/"
PRODUCT_LINK="https://github.com/NiceTop1027/MAC_FILELOCK"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$VERSION" ] || [ -z "$DMG_PATH" ]; then
    echo "사용법: bash publish_update.sh <버전> <DMG경로>"
    exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "오류: $DMG_PATH 파일이 없습니다."
    exit 1
fi

if [ ! -x "$VENDOR_DIR/bin/generate_appcast" ]; then
    echo "오류: Sparkle generate_appcast 도구가 없습니다. 먼저 bash setup_sparkle.sh 를 실행하세요."
    exit 1
fi

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cp "$DMG_PATH" "$TMP_DIR/"
if [ -f "$APPCAST_FILE" ]; then
    cp "$APPCAST_FILE" "$TMP_DIR/appcast.xml"
fi

echo "▸ appcast.xml 생성 중…"
"$ROOT_DIR/$VENDOR_DIR/bin/generate_appcast" \
    --download-url-prefix "$RELEASE_URL_PREFIX" \
    --link "$PRODUCT_LINK" \
    -o "$TMP_DIR/appcast.xml" \
    "$TMP_DIR"

mkdir -p "$(dirname "$APPCAST_FILE")"
cp "$TMP_DIR/appcast.xml" "$APPCAST_FILE"
echo "✓ appcast 갱신 완료: $APPCAST_FILE"
