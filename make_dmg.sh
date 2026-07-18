#!/bin/bash
# 生成拖拽式安装器 VideoGrabber.dmg：
# 打开后是一个窗口，把 App 图标拖到「应用程序」文件夹即可安装。
#
# 用法：  ./make_dmg.sh
# 前置：  先跑 ./build_app.sh 生成 VideoGrabber.app
set -euo pipefail

APP_NAME="VideoGrabber"
VOL="$APP_NAME"
APP_DIR="./$APP_NAME.app"
OUT="./$APP_NAME.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  echo "未找到 $APP_DIR，先运行 ./build_app.sh 构建。" >&2
  exit 1
fi

echo "==> 准备安装器内容…"
STAGING="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 依据内容大小决定临时读写盘大小
MB=$(( $(du -sm "$STAGING" | cut -f1) + 80 ))
RW="$(mktemp -u).dmg"

echo "==> 创建临时磁盘映像（${MB}MB）…"
rm -f "$OUT"
hdiutil create -srcfolder "$STAGING" -volname "$VOL" -fs HFS+ \
  -format UDRW -size ${MB}m "$RW" >/dev/null

echo "==> 挂载并布局窗口…"
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | sed 1q | awk '{print $1}')"
sleep 1

# 默认外观：只摆好 App 图标和「应用程序」文件夹的位置，不用自定义背景。
osascript <<EOF || true
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 120, 900, 480}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 120
    set position of item "$APP_NAME.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
sync

echo "==> 卸载并压缩为最终 DMG…"
hdiutil detach "$DEV" >/dev/null || hdiutil detach "$DEV" -force >/dev/null || true
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
rm -rf "$STAGING"

# ad-hoc 签名 DMG
codesign --force --sign - "$OUT" 2>/dev/null || true

echo "==> 完成：$OUT"
echo "   双击打开后，把 VideoGrabber 拖到「应用程序」即可。"
