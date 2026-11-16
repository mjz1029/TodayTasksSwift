#!/bin/bash
# 把 swift build 产物打成一个可双击的 macOS .app，方便直接看界面/截图。
# 用法：./bundle_mac.sh [debug|release]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "${CONFIG}" --product TodayTasksMac

case "${CONFIG}" in
  debug)   STEP="Debug" ;;
  release) STEP="Release" ;;
  *)       STEP="Debug" ;;
esac

BIN=".build/out/Products/${STEP}/TodayTasksMac"
[ -f "$BIN" ] || BIN=".build/${CONFIG}/TodayTasksMac"

APP="build/今日待办.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/TodayTasksMac"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>今日待办</string>
  <key>CFBundleDisplayName</key><string>今日待办</string>
  <key>CFBundleExecutable</key><string>TodayTasksMac</string>
  <key>CFBundleIdentifier</key><string>com.mojizhou.todaytasks</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || true
echo "打包完成：$(pwd)/${APP}"
