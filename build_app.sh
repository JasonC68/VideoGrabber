#!/bin/bash
# 构建自包含的 VideoGrabber.app：
#   - 编译成 arm64 + x86_64 通用二进制（任何 Mac 都能跑）
#   - 把 yt-dlp、ffmpeg 打进 App 内部（无需 Homebrew / Python）
#   - ad-hoc 代码签名
#
# 内置二进制的来源（按优先级）：
#   1) 你手动放到 vendor/bin/ 里的文件（推荐国内用户用，避免直连 GitHub 慢）
#   2) 联网下载（自动尝试 GitHub 原站 + 国内加速镜像）
#
# 用法：  ./build_app.sh              正常构建
#         ./build_app.sh --refresh   强制重新获取内置的 yt-dlp/ffmpeg
#
# 产物：  ./VideoGrabber.app
set -euo pipefail

APP_NAME="VideoGrabber"
BUNDLE_ID="com.videograbber.app"
MIN_OS="13.0"
REFRESH=0
[[ "${1:-}" == "--refresh" ]] && REFRESH=1

VENDOR_DIR="vendor/bin"
mkdir -p "$VENDOR_DIR"

# ---------- 1. 准备内置二进制（yt-dlp / ffmpeg）----------

is_macho() { file -b "$1" 2>/dev/null | grep -qi 'Mach-O'; }

# 把下载/放置的文件规整成“可执行 Mach-O”：识别 gzip / zip / 裸文件。
normalize_binary() { # <文件> <zip内可执行名>
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
    [[ -z "$found" ]] && { rm -rf "$tmp"; return 1; }
    cp "$found" "$f"; rm -rf "$tmp"
  fi
  is_macho "$f" || return 1
  chmod +x "$f"; return 0
}

# 给 GitHub 地址生成候选：原站 + 国内加速镜像
mirror_urls() { # <url>
  local u="$1"; echo "$u"
  case "$u" in
    https://github.com/*|https://raw.githubusercontent.com/*|https://objects.githubusercontent.com/*)
      echo "https://ghfast.top/$u"
      echo "https://ghproxy.net/$u"
      echo "https://mirror.ghproxy.com/$u"
      echo "https://gh-proxy.com/$u" ;;
  esac
}

dl_first() { # <目标> <zip内名> <url...>
  local dest="$1" wantname="$2"; shift 2
  local url m
  for url in "$@"; do
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      echo "   尝试：$m"
      if curl -fL --retry 2 --connect-timeout 15 --progress-bar -o "$dest.tmp" "$m" 2>/dev/null \
         && normalize_binary "$dest.tmp" "$wantname"; then
        mv "$dest.tmp" "$dest"; echo "   ✓ 成功"; return 0
      fi
      rm -f "$dest.tmp"
    done < <(mirror_urls "$url")
  done
  return 1
}

# 把 vendor/bin 里“手动放置/别的命名”的文件规整成目标名
ingest() { # <目标名> <候选文件名...>
  local target="$1"; shift
  [[ -s "$VENDOR_DIR/$target" ]] && is_macho "$VENDOR_DIR/$target" && return 0
  local c
  for c in "$@"; do
    [[ -s "$VENDOR_DIR/$c" ]] || continue
    cp "$VENDOR_DIR/$c" "$VENDOR_DIR/.ingest.tmp"
    if normalize_binary "$VENDOR_DIR/.ingest.tmp" "$target"; then
      mv "$VENDOR_DIR/.ingest.tmp" "$VENDOR_DIR/$target"
      echo "   ✓ 采用手动放置的 $c → $target"; return 0
    fi
    rm -f "$VENDOR_DIR/.ingest.tmp"
  done
  return 1
}

echo "==> 准备内置二进制（yt-dlp / ffmpeg）…"

# --- yt-dlp ---
if [[ "$REFRESH" == "1" ]] || ! { [[ -s "$VENDOR_DIR/yt-dlp" ]] && is_macho "$VENDOR_DIR/yt-dlp"; }; then
  ingest yt-dlp yt-dlp_macos yt-dlp_macos_legacy \
    || dl_first "$VENDOR_DIR/yt-dlp" "yt-dlp" \
         "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    || echo "   ⚠️  yt-dlp 未就绪（见下方手动放置指引）。"
fi

# --- ffmpeg ---
prepare_ffmpeg() {
  if [[ "$REFRESH" == "0" && -s "$VENDOR_DIR/ffmpeg" ]] && is_macho "$VENDOR_DIR/ffmpeg"; then return 0; fi
  # 手动放置优先：单文件 ffmpeg，或 arm64/x64 分开两份
  ingest ffmpeg ffmpeg ffmpeg-darwin-arm64 darwin-arm64 ffmpeg-darwin-x64 darwin-x64 && return 0
  local arm="$VENDOR_DIR/ffmpeg-arm64" x64="$VENDOR_DIR/ffmpeg-x64"
  local egw="https://github.com/eugeneware/ffmpeg-static/releases/latest/download"
  dl_first "$arm" "ffmpeg" "$egw/ffmpeg-darwin-arm64" "$egw/darwin-arm64" || rm -f "$arm"
  dl_first "$x64" "ffmpeg" "$egw/ffmpeg-darwin-x64" "$egw/darwin-x64" \
           "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" || rm -f "$x64"
  if [[ -s "$arm" && -s "$x64" ]]; then
    lipo -create "$arm" "$x64" -output "$VENDOR_DIR/ffmpeg" 2>/dev/null || cp "$arm" "$VENDOR_DIR/ffmpeg"
  elif [[ -s "$arm" ]]; then cp "$arm" "$VENDOR_DIR/ffmpeg"
  elif [[ -s "$x64" ]]; then cp "$x64" "$VENDOR_DIR/ffmpeg"
  else echo "   ⚠️  ffmpeg 未就绪（高清合并暂不可用，仍可下带声音的单文件）。"; return 0; fi
  chmod +x "$VENDOR_DIR/ffmpeg"
  echo "   ✓ ffmpeg：$(lipo -archs "$VENDOR_DIR/ffmpeg" 2>/dev/null || echo 单架构)"
}
prepare_ffmpeg

# 缺依赖时打印手动放置指引，然后中止（避免构建出残缺的 App）
YT_OK=0; [[ -s "$VENDOR_DIR/yt-dlp" ]] && is_macho "$VENDOR_DIR/yt-dlp" && YT_OK=1
if [[ "$YT_OK" == "0" ]]; then
  cat <<TIP

────────────────────────────────────────────────────────────
 需要手动准备 yt-dlp（网络下载失败时最省事）：
 1) 用浏览器/下载工具下载这个文件（任选其一）：
      原站  https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
      加速  https://ghfast.top/https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
 2) 改名为 yt-dlp，放到：
      $(pwd)/$VENDOR_DIR/yt-dlp
 3) （可选）ffmpeg 同理，Apple 芯片下载 arm64 版：
      https://ghfast.top/https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64
      改名为 ffmpeg 放到 $(pwd)/$VENDOR_DIR/ffmpeg
 4) 重新运行 ./build_app.sh
 放好后脚本会自动识别，不再联网下载。
────────────────────────────────────────────────────────────
TIP
  exit 1
fi

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

for b in yt-dlp ffmpeg; do
  if [[ -s "$VENDOR_DIR/$b" ]]; then
    cp "$VENDOR_DIR/$b" "$APP_DIR/Contents/Resources/bin/$b"
    chmod +x "$APP_DIR/Contents/Resources/bin/$b"
  fi
done

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
for b in "$APP_DIR/Contents/Resources/bin/"*; do
  [[ -f "$b" ]] && codesign --force --sign - --timestamp=none "$b" 2>/dev/null || true
done
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
touch "$APP_DIR"

echo "==> 完成：$APP_DIR"
echo "   运行： open \"$APP_DIR\""
echo "   打包安装器： ./make_dmg.sh"
