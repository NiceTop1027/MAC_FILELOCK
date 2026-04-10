#!/bin/bash
# Sparkle 프레임워크 다운로드 및 공개키 준비
# 사용법: bash setup_sparkle.sh
set -e

SPARKLE_VERSION="2.6.4"
VENDOR_DIR="vendor"
SPARKLE_FW="$VENDOR_DIR/Sparkle.framework"
KEYS_DIR="$VENDOR_DIR/sparkle-keys"
FRAMEWORK_ONLY=0

if [ "${1:-}" = "--framework-only" ]; then
    FRAMEWORK_ONLY=1
fi

echo "=== Sparkle $SPARKLE_VERSION 설정 ==="

# 1. Sparkle 다운로드
if [ ! -d "$SPARKLE_FW" ]; then
    echo "▸ Sparkle 다운로드 중…"
    mkdir -p "$VENDOR_DIR"
    TMP_TAR="/tmp/Sparkle-$SPARKLE_VERSION.tar.xz"
    curl -fL \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        -o "$TMP_TAR"
    tar -xf "$TMP_TAR" -C "$VENDOR_DIR"
    rm -f "$TMP_TAR"
    echo "✓ Sparkle.framework 준비 완료"
else
    echo "✓ Sparkle.framework 이미 있음"
fi

if [ "$FRAMEWORK_ONLY" = "1" ]; then
    echo ""
    echo "✓ 프레임워크 준비만 완료"
    exit 0
fi

# 2. Ed25519 공개키 추출/생성
mkdir -p "$KEYS_DIR"
if [ ! -f "$KEYS_DIR/sparkle_public_key" ]; then
    echo ""
    echo "▸ Ed25519 키 생성 중…"
    "$VENDOR_DIR/bin/generate_keys" 2>&1 | tee "$KEYS_DIR/keygen_output.txt"

    PUB_KEY=$(sed -n 's/.*<string>\\(.*\\)<\\/string>.*/\\1/p' "$KEYS_DIR/keygen_output.txt" | head -n 1)
    if [ -z "$PUB_KEY" ]; then
        echo "오류: 공개키를 추출하지 못했습니다."
        exit 1
    fi

    echo "$PUB_KEY" > "$KEYS_DIR/sparkle_public_key"
    echo ""
    echo "✓ 공개키 저장 완료: $KEYS_DIR/sparkle_public_key"
    echo "⚠️  비공개키는 파일이 아니라 macOS Keychain(ed25519 계정)에 저장됩니다."
else
    echo ""
    echo "✓ 공개키 이미 존재: $KEYS_DIR/sparkle_public_key"
fi

echo ""
echo "공개키:"
cat "$KEYS_DIR/sparkle_public_key"
