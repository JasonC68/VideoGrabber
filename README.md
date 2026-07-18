# VideoGrabber

macOS 上的一个视频下载器，普通桌面窗口应用。底层是 yt-dlp 加 ffmpeg，YouTube、B 站、Twitter/X、TikTok、抖音、微博、小红书、微信公众号文章里的视频等一千多个网站都能下。

往下载队列里加视频有三种方式：复制视频页的链接会自动识别并弹提示；也能读浏览器（Safari、Chrome、Edge、Brave、Arc、Vivaldi）当前标签页在看的视频；再不然直接在输入框粘贴链接回车。

yt-dlp 和 ffmpeg 都打包进了 App 里，用的人不用装 Homebrew、Python 或者别的什么，双击就能用。

## 构建

需要 macOS 13 以上、装了 Xcode 或 Command Line Tools，头一次构建得联网。

```bash
./build_app.sh
```

脚本干三件事：把程序编译成 arm64 加 Intel 的通用二进制，两种芯片的 Mac 都能跑；下载 yt-dlp 和 ffmpeg 放进 `VideoGrabber.app/Contents/Resources/bin`；最后做一次 ad-hoc 签名。跑完得到的 `VideoGrabber.app` 是自包含的，拷到别的 Mac 上也能直接开。

想更新里面的 yt-dlp / ffmpeg，加 `--refresh` 再跑一次。

国内直连 GitHub 下这两个依赖可能很慢甚至断。脚本里备了几个加速镜像；要是还下不动，就自己去 GitHub 下好丢进 `vendor/bin/`（文件名保持 `yt-dlp_macos`、`ffmpeg-darwin-arm64`、`ffmpeg-darwin-x64` 就行），再跑一次 `build_app.sh`，它会自己认出来，不再联网。想让打出来的包在 Intel Mac 上也能合并高清，记得把 `ffmpeg-darwin-x64` 也放进去。

## 打包成安装器

```bash
./make_dmg.sh
```

得到 `VideoGrabber.dmg`，双击打开就是常见那种安装窗口，把图标拖到「应用程序」就装好了。这个 dmg 发给谁都行，对方不用装任何东西。

## 签名和门禁

现在用的是 ad-hoc 签名，没有 Apple 开发者账号，所以：

自己这台构建机上，`build_app.sh` 已经清掉了 quarantine，双击能直接开。

发给别人、或者拷到另一台 Mac，第一次打开会被系统门禁拦一下，提示"无法验证开发者"。让对方右键点 App 选「打开」，再确认一次就行，之后就正常了。没做公证的 App 都这样，不是坏了。

想做到对方双击零提示，得有 Apple Developer 账号（一年 99 美元），用 Developer ID 证书签名再走一遍公证。有账号的话，把 `build_app.sh` 里的 `codesign --sign -` 换成自己的证书，再补上 `notarytool` 公证和 `stapler` 装订那几步就行。

## 用法

打开是主窗口，右上角选清晰度：最佳、1080p、720p、480p，或者只要音频的 MP3。

下载入口三选一：复制链接等它弹提示、浏览器打开视频页、或者直接粘贴链接回车。下的过程里能看到进度、速度和剩余时间，下完点文件夹图标能在访达里定位到文件。

设置在菜单栏 VideoGrabber → 设置，或者按 Cmd+,，也可以点窗口右下角的齿轮。里面能改下载目录、开关那几种检测方式。

浏览器标签检测头一次用会让你授权「自动化」权限（允许控制 Safari/Chrome），点允许。不给也能用，只是少了这一路。

系统是 macOS 26 的话，窗口背景会用液态玻璃材质；更早的系统就是普通纯色窗口。

## 有些情况下不了

DRM 加密的付费流媒体，Netflix、Disney+、爱奇艺和腾讯视频客户端这些，下不了。是加密流，抓不到也解不开，跟工具没关系。

微信视频号支持得很不稳定，经常被风控挡掉；公众号文章里的普通视频一般能下。

需要登录或会员才能看的视频暂时下不了，得给 yt-dlp 传浏览器 cookie，这个还没做进界面。

只有浏览器里播放的能检测到，原生客户端播放器里的检测不到。

## 许可

代码是 MIT，见 `LICENSE`。App 里捆绑的 yt-dlp（Unlicense）和 ffmpeg（GPL）是当独立程序调用的，不进仓库（`vendor/` 已经在 `.gitignore` 里排掉了）。分发带 ffmpeg 的 dmg 时的 GPL 说明写在 `THIRD_PARTY_NOTICES.md`。

只下你自己有版权、拿到授权、或者平台允许下载的东西。下有版权的内容、或者违反平台条款，后果自己担。

## 代码结构

| 文件 | 作用 |
|------|------|
| `App.swift` | 入口，主窗口和设置命令 |
| `AppDelegate.swift` | 启动检测器，关窗即退出 |
| `MainView.swift` | 主窗口界面 |
| `DownloadRow.swift` | 单条下载任务的行 |
| `SettingsView.swift` | 设置页 |
| `GlassBackground.swift` | 按系统版本切换玻璃/纯色背景 |
| `DownloadManager.swift` | 全局状态、设置持久化、下载队列 |
| `YTDLPService.swift` | 调 yt-dlp/ffmpeg：定位、探测、下载、进度解析 |
| `URLDetector.swift` | 从文本里抽链接、判断是不是视频页 |
| `ClipboardMonitor.swift` | 剪贴板轮询 |
| `BrowserWatcher.swift` | AppleScript 读浏览器当前标签 |
| `Models.swift` | 数据模型 |
| `build_app.sh` | 构建、内置依赖、签名 |
| `make_dmg.sh` | 生成 dmg 安装器 |

## 还没做的

- 传浏览器 cookie 下会员/登录内容
- 播放列表、多分 P 批量下载
- 缩略图预览、字幕下载
