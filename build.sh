#!/bin/bash
# FileLock 빌드 스크립트
# 사용법: bash build.sh
#
# 사전 준비: bash setup_sparkle.sh 를 먼저 실행하세요.
set -e

APP="FileLock"
SRC="src"
DIST="dist"
BUNDLE="$DIST/$APP.app"
ASSETS="assets"
LOCK_EXT="filelock"
VENDOR_DIR="vendor"
SPARKLE_FW="$VENDOR_DIR/Sparkle.framework"

# ── Sparkle 설정 ──────────────────────────────────────────────────────────────
SPARKLE_PUBLIC_KEY="avNwBpeP/RVGu/DC3V6wuvYrgs/kyNb0c/Ovml6oMbY="
SPARKLE_FEED_URL="https://raw.githubusercontent.com/NiceTop1027/MAC_FILELOCK/main/docs/appcast.xml"
# ─────────────────────────────────────────────────────────────────────────────

echo "=== $APP 빌드 시작 ==="

mkdir -p "$DIST"

# Sparkle 프레임워크 확인
if [ ! -d "$SPARKLE_FW" ]; then
    echo "오류: Sparkle.framework 가 없습니다."
    echo "  bash setup_sparkle.sh 를 먼저 실행하세요."
    exit 1
fi

# 로고 / 앱 아이콘 생성
clang -framework Cocoa -fobjc-arc make_icon.m -o make_icon
./make_icon
iconutil -c icns "$ASSETS/$APP.iconset" -o "$ASSETS/$APP.icns"
echo "✓ 아이콘 생성 완료"

# 컴파일 (Sparkle 연동, Updater.m 제외)
clang \
  -fmodules \
  -framework Cocoa \
  -framework CoreServices \
  -framework Security \
  -framework UniformTypeIdentifiers \
  -F "$VENDOR_DIR" -framework Sparkle \
  -rpath "@executable_path/../Frameworks" \
  -fobjc-arc \
  -O2 \
  -o "$DIST/$APP" \
  "$SRC/Crypto.m" \
  "$SRC/Vault.m" \
  "$SRC/AppDelegate.m"

echo "✓ 컴파일 완료"

# .app 번들 구조 생성
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$DIST/$APP" "$BUNDLE/Contents/MacOS/$APP"
chmod +x "$BUNDLE/Contents/MacOS/$APP"
cp "$ASSETS/$APP.icns" "$BUNDLE/Contents/Resources/$APP.icns"
cp "$ASSETS/$APP.iconset/icon_512x512.png" "$BUNDLE/Contents/Resources/$APP-mark.png"

# Sparkle.framework 번들에 포함
mkdir -p "$BUNDLE/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$BUNDLE/Contents/Frameworks/"
echo "✓ Sparkle.framework 복사 완료"

# Info.plist 생성
cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>FileLock</string>
  <key>CFBundleDisplayName</key>     <string>FileLock</string>
  <key>CFBundleIdentifier</key>      <string>com.filelock.app</string>
  <key>CFBundleVersion</key>         <string>1.0.4</string>
  <key>CFBundleShortVersionString</key><string>1.0.4</string>
  <key>CFBundleExecutable</key>      <string>FileLock</string>
  <key>CFBundleIconFile</key>        <string>FileLock.icns</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>    <string>com.filelock.protected-file</string>
      <key>UTTypeDescription</key>   <string>FileLock Protected File</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>__LOCK_EXT__</string>
        </array>
        <key>public.mime-type</key>
        <string>application/x-filelock</string>
      </dict>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>    <string>FileLock Protected File</string>
      <key>CFBundleTypeRole</key>    <string>Viewer</string>
      <key>LSHandlerRank</key>       <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.filelock.protected-file</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>__LOCK_EXT__</string>
      </array>
    </dict>
  </array>
  <key>NSPrincipalClass</key>        <string>NSApplication</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>SUFeedURL</key>               <string>__SPARKLE_FEED_URL__</string>
  <key>SUPublicEDKey</key>           <string>__SPARKLE_PUBLIC_KEY__</string>
</dict>
</plist>
PLIST

sed -i '' "s|__LOCK_EXT__|$LOCK_EXT|g" "$BUNDLE/Contents/Info.plist"
sed -i '' "s|__SPARKLE_FEED_URL__|$SPARKLE_FEED_URL|g" "$BUNDLE/Contents/Info.plist"
sed -i '' "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_PUBLIC_KEY|g" "$BUNDLE/Contents/Info.plist"

# PkgInfo 생성 (필수)
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# ad-hoc 코드 서명 (Gatekeeper 없이 로컬 실행)
# 배포용이라면 Developer ID로 서명하고 notarize 하세요.
xattr -cr "$BUNDLE"
codesign --force --sign - "$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
codesign --force --sign - "$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
codesign --force --sign - "$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null && echo "✓ 코드 서명 완료" || true

# DMG 패키징
bash package_dmg.sh

echo ""
echo "=== 빌드 성공 ==="
echo "실행: open $BUNDLE"
echo "또는: $DIST/$APP"
