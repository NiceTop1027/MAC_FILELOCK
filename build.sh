#!/bin/bash
# FileLock 빌드 스크립트
# 사용법: bash build.sh
set -e

APP="FileLock"
SRC="src"
DIST="dist"
BUNDLE="$DIST/$APP.app"
ASSETS="assets"

echo "=== $APP 빌드 시작 ==="

mkdir -p "$DIST"

# 로고 / 앱 아이콘 생성
clang -framework Cocoa -fobjc-arc make_icon.m -o make_icon
./make_icon
iconutil -c icns "$ASSETS/$APP.iconset" -o "$ASSETS/$APP.icns"
echo "✓ 아이콘 생성 완료"

# 컴파일
clang \
  -fmodules \
  -framework Cocoa \
  -framework Security \
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
  <key>CFBundleVersion</key>         <string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key>      <string>FileLock</string>
  <key>CFBundleIconFile</key>        <string>FileLock.icns</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>    <string>FileLock Protected File</string>
      <key>CFBundleTypeRole</key>    <string>Viewer</string>
      <key>LSHandlerRank</key>       <string>Owner</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>lock</string>
      </array>
    </dict>
  </array>
  <key>NSPrincipalClass</key>        <string>NSApplication</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
</dict>
</plist>
PLIST

# PkgInfo 생성 (필수)
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# ad-hoc 코드 서명 (Gatekeeper 없이 로컬 실행)
xattr -cr "$BUNDLE"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null && echo "✓ 코드 서명 완료" || true

# DMG 패키징
bash package_dmg.sh

echo ""
echo "=== 빌드 성공 ==="
echo "실행: open $BUNDLE"
echo "또는: $DIST/$APP"
