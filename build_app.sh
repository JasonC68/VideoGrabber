#!/bin/bash
# 构建自包含的 VideoGrabber.app：
#   - 编译成 arm64 + x86_64 通用二进制（任何 Mac 都能跑）
#   - 把 yt-dlp、ffmpeg 打进 App 内部（无需 Homebrew / Python）
#   - ad-hoc 代码签名
#
# 用法：  ./build_app.sh              正常构建（首次会联网下载 yt-dlp/ffmpeg）
#         ./build_app.sh --refresh   强制重新下载内置的 yt-dlp/ffmpeg
#
# 产物：  ./VideoGrabber.app
set -euo pipefail

APP_NAME="VideoGrabber"
BUNDLE_ID="com.videograbber.app"
MIN_OS="13.0"
REFRESH=0
[[ "${1:-}" == "--refresh" ]] && REFRESH=1

# 内置二进制缓存目录（放在项目里，避免每次都重新下载）
VENDOR_DIR="vendor/bin"
mkdir -p "$VENDOR_DIR"

# ---------- 1. 下载并准备内置二进制 ----------

# 把下载内容规整成“可执行的 Mach-O 二进制”：识别 gzip / zip / 裸文件。
# 用法：normalize_binary <下载得到的文件> <期望的可执行名，仅 zip 内查找用>
# 成功则把结果原地留在 <文件> 路径并 chmod +x，返回 0；否则返回 1。
normalize_binary() {
  local f="$1" wantname="${2:-}"
  [[ -s "$f" ]] || return 1
  local kind; kind="$(file -b "$f" 2>/dev/null || true)"
  if echo "$kind" | grep -qi gzip; then
    mv "$f" "$f.gz"; gunzip -f "$f.gz" || return 1
  elif echo "$kind" | grep -qi 'Zip archive'; then
    local tmp; tmp="$(mktemp -d)"
    unzip -o -q "$f" -d "$tmp" || return 1
    local found; found="$(find "$tmp" -type f -name "${wantname:-*}" ! -name '*.txt' | head -1)"
    [[ -z "$found" ]] && found="$(find "$tmp" -type f -perm -u+x | head -1)"
    [[ -z "$found" ]] && return 1
    cp "$found" "$f"; rm -rf "$tmp"
  fi
  file -b "$f" 2>/dev/null | grep -qi 'Mach-O' || return 1
  chmod +x "$f"; return 0
}

# 依次尝试多个下载源，第一个得到有效 Mach-O 的就用它。
# 用法：dl_first <目标路径> <zip内可执行名> <url1> <url2> ...
dl_first() {
  local dest="$1" wantname="$2"; shift 2
  local url
  for url in "$@"; do
    echo "   尝试：$url"
    if curl -fL --retry 2 --progress-bar -o "$dest.tmp" "$url" 2>/dev/null && \
       normalize_binary "$dest.tmp" "$wantname"; then
      mv "$dest.tmp" "$dest"; echo "   ✓ 成功"; return 0
    fi
    rm -f "$dest.tmp"
  done
  return 1
}

echo "==> 准备内置二进制（yt-dlp / ffmpeg）…"

# yt-dlp（官方 macOS 独立版，自带 Python，通用二进制）
if [[ "$REFRESH" == "1" || ! -s "$VENDOR_DIR/yt-dlp" ]]; then
  dl_first "$VENDOR_DIR/yt-dlp" "yt-dlp" \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    || echo "   ⚠️  yt-dlp 下载失败，请检查网络后重试（或 ./build_app.sh --refresh）。"
fi

# ffmpeg：arm64 + x86_64 各取一份，lipo 合成通用；多源容错。
prepare_ffmpeg() {
  [[ "$REFRESH" == "0" && -s "$VENDOR_DIR/ffmpeg" ]] && return 0
  local arm="$VENDOR_DIR/ffmpeg-arm64" x64="$VENDOR_DIR/ffmpeg-x64"
  local egw="https://github.com/eugeneware/ffmpeg-static/releases/latest/download"

  dl_first "$arm" "ffmpeg" \
    "$egw/ffmpeg-darwin-arm64" "$egw/darwin-arm64" || rm -f "$arm"
  dl_first "$x64" "ffmpeg" \
    "$egw/ffmpeg-darwin-x64" "$egw/darwin-x64" \
    "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" || rm -f "$x64"

  if [[ -s "$arm" && -s "$x64" ]]; then
    lipo -create "$arm" "$x64" -output "$VENDOR_DIR/ffmpeg" 2>/dev/null || cp "$arm" "$VENDOR_DIR/ffmpeg"
  elif [[ -s "$arm" ]]; then cp "$arm" "$VENDOR_DIR/ffmpeg"
  elif [[ -s "$x64" ]]; then cp "$x64" "$VENDOR_DIR/ffmpeg"
  else
    echo "   ⚠️  ffmpeg 全部下载源失败：高清合并暂不可用（仍可下带声音的单文件）。稍后可 ./build_app.sh --refresh 重试。"
    return 0
  fi
  chmod +x "$VENDOR_DIR/ffmpeg"
  echo "   ✓ ffmpeg 就绪：$(lipo -archs "$VENDOR_DIR/ffmpeg" 2>/dev/null || echo 单架构)"
}
prepare_ffmpeg

# ---------- 2. 编译通用二进制 ----------
echo "==> 编译 release（arm64 + x86_64 通用）…"
swift build -c release --arch arm64 --arch x86_64
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "找不到编译产物：$BIN_PATH" >&2; exit 1
fi

# ---------- 3. 组装 .app ----------
APP_DIR="./$APP_NAME.app"
echo "==> 组装 $APP_DIR …"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# 内置二进制放入 Resources/bin
for b in yt-dlp ffmpeg; do
  if [[ -s "$VENDOR_DIR/$b" ]]; then
    cp "$VENDOR_DIR/$b" "$APP_DIR/Contents/Resources/bin/$b"
    chmod +x "$APP_DIR/Contents/Resources/bin/$b"
  fi
done

# 图标
ICON_OK=0
if [[ -d "Icon/AppIcon.iconset" ]] && command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "Icon/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns" && ICON_OK=1
elif [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns" && ICON_OK=1
fi
ICON_PLIST=""
[[ "$ICON_OK" == "1" ]] && ICON_PLIST="    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleIconName</key>            <string>AppIcon</string>"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>            <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>LSMinimumSystemVersion</key>     <string>$MIN_OS</string>
$ICON_PLIST
    <key>NSAppleEventsUsageDescription</key>
    <string>用于读取浏览器当前标签页的网址，以检测你正在观看的视频。</string>
</dict>
</plist>
PLIST

# ---------- 4. ad-hoc 代码签名 ----------
echo "==> ad-hoc 签名…"
# 先签内置二进制，再签整个 app（顺序不能反）
for b in "$APP_DIR/Contents/Resources/bin/"*; do
  [[ -f "$b" ]] && codesign --force --sign - --timestamp=none "$b" 2>/dev/null || true
done
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
# 去掉 quarantine，方便本机直接打开
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
touch "$APP_DIR"

echo "==> 完成：$APP_DIR"
echo "   运行： open \"$APP_DIR\""
echo "   打包安装器： ./make_dmg.sh"
