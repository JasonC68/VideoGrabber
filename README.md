# VideoGrabber (macOS)

一个桌面视频下载器（独立窗口应用，带 Dock 图标）。三种方式发现视频并下载：

1. **剪贴板检测** —— 复制任意视频页面链接，自动识别并提示下载。
2. **浏览器标签检测** —— 读取 Safari / Chrome / Edge / Brave / Arc / Vivaldi 当前正在看的页面 URL。
3. **手动粘贴** —— 菜单里直接粘贴链接下载。

底层用 [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) + `ffmpeg`，支持 YouTube、Bilibili、Twitter/X、TikTok、抖音、微博、小红书、微信公众号文章视频等 1000+ 站点。

**自包含分发**：`yt-dlp` 和 `ffmpeg` 会被打进 App 内部，最终用户**无需安装 Homebrew、Python 或任何东西**，双击即用。

---

## 一、构建自包含 App（开发者，一次）

需要 macOS 13+、Xcode（或 Command Line Tools）、能联网。

```bash
cd VideoGrabber
./build_app.sh        # 首次会联网下载 yt-dlp / ffmpeg 并打进 App
```

`build_app.sh` 做了三件事：把程序编译成 **arm64 + Intel 通用二进制**（任何 Mac 都能跑）；下载官方 `yt-dlp`（自带 Python 的独立版）和通用 `ffmpeg` 放进 `VideoGrabber.app/Contents/Resources/bin`；做 ad-hoc 代码签名。产物 `VideoGrabber.app` 就是自包含的，拷到别的 Mac 也能直接跑。

想更新内置的 yt-dlp / ffmpeg：`./build_app.sh --refresh`。

## 二、打包成拖拽式安装器 .dmg

```bash
./make_dmg.sh         # 生成 VideoGrabber.dmg
```

生成的 `VideoGrabber.dmg` 双击打开后是经典的安装窗口：把 VideoGrabber 图标拖到「应用程序」文件夹即可安装。把这个 `.dmg` 发给任何人，对方无需装任何依赖。

## 三、关于代码签名 / 门禁（重要）

本项目用的是 **ad-hoc 签名**（无 Apple 开发者账号）。这意味着：

- **在你自己这台构建机上**：`build_app.sh` 已清除 quarantine，直接双击就能开。
- **发给别人 / 拷到别的 Mac**：首次打开会被 macOS 门禁拦一下（提示"无法验证开发者"）。让对方**右键点 App ▸ 打开 ▸ 再确认打开**，或在「系统设置 ▸ 隐私与安全性」里点"仍要打开"，之后就正常了。这是所有未公证 App 的通用现象，不是坏了。
- **想做到对方双击零提示**：需要 99 美元/年的 Apple Developer 账号，用 Developer ID 证书签名并做 **公证(notarization)**。有账号后可在 `build_app.sh` 里把 `codesign --sign -` 换成你的证书，并加 `xcrun notarytool` 公证 + `xcrun stapler staple` 步骤。需要时我可以帮你补上。

## 四、开发调试（可选）

直接 `swift run` 可快速调试（此模式不走内置二进制、会退回系统 PATH 里的 yt-dlp/ffmpeg，且不发通知）。用 Xcode 打开文件夹（识别 `Package.swift`）也可以。

启动后会打开主窗口，Dock 里会出现应用图标。设置在菜单栏「VideoGrabber ▸ 设置…」或按 `Cmd + ,` 打开，也可点窗口右下角的齿轮。关闭窗口即退出。

## 三、授权

- **自动化权限**：第一次开启「浏览器标签检测」时，macOS 会弹窗问是否允许 VideoGrabber 控制 Safari/Chrome，点允许。之后可在 系统设置 ▸ 隐私与安全性 ▸ 自动化 里管理。不授权也能用，只是少了“检测正在看的视频”这一路。
- **通知权限**：下载完成时弹通知，可选。

## 四、使用

1. 打开应用主窗口。
2. 右上角选清晰度（最佳 / 1080p / 720p / 480p / 仅音频 MP3）。
3. 三选一：复制链接等它弹提示 → 点「下载」；或浏览器打开视频页；或直接在输入框粘贴链接回车。
4. 下载进度、速度、剩余时间实时显示；完成后点文件夹图标可在访达中定位。
5. 设置里可改下载目录、是否“检测到即自动下载”等。

---

## 已知限制

- **DRM 加密内容下载不了**：Netflix、Disney+、爱奇艺/腾讯视频客户端等付费流媒体是加密流，技术上无法抓取。
- **微信视频号（Channels）**：`yt-dlp` 对视频号支持有限、且经常因风控失效；公众号文章里的普通视频通常可下。抖音等平台偶尔需要更新 `yt-dlp` 或配置 cookies 才能下高清。
- **需要登录/会员的视频**：可通过给 `yt-dlp` 传浏览器 cookies 解决。
- **原生 App 里播放的视频**：本工具只检测浏览器标签，不检测原生播放器。

## 常见问题

**下出来 mp4 没声音、webm 没画面?**
正常构建的 App 已内置 ffmpeg，不会出现这问题。若你用 `swift run` 调试且系统没有 ffmpeg，会自动降级为“已带声音的单文件”(通常最高 720p)。要内置最新 ffmpeg，用 `./build_app.sh --refresh` 重新构建。

**发给别人打不开、提示"已损坏"或"无法验证开发者"?**
这是未公证 App 的门禁提示，不是真的损坏。让对方右键 App ▸ 打开 ▸ 确认，或系统设置里"仍要打开"。彻底免提示需 Apple 公证（见上文第三节）。

## 合规提示

请仅用于下载你拥有版权、已获授权、或平台允许的内容（如你自己的作品、公开授权素材、个人存档）。下载受版权保护的内容或违反平台服务条款可能带来法律风险，请自行判断与承担。

---

## 代码结构

| 文件 | 作用 |
|------|------|
| `App.swift` | 应用入口，主窗口 + 设置命令 |
| `AppDelegate.swift` | 启动检测器、关窗即退出 |
| `build_app.sh` | 构建通用 + 内置依赖 + 签名 |
| `make_dmg.sh` | 生成拖拽式 .dmg 安装器 |
| `Models.swift` | 数据模型：视频信息、清晰度、下载任务与状态 |
| `YTDLPService.swift` | 封装 yt-dlp/ffmpeg：定位、探测、下载、进度解析 |
| `URLDetector.swift` | 从文本抽取链接、判断是否视频站点 |
| `ClipboardMonitor.swift` | 剪贴板轮询检测 |
| `BrowserWatcher.swift` | AppleScript 读取浏览器当前标签 URL |
| `DownloadManager.swift` | 全局状态、设置持久化、下载队列调度 |
| `MainView.swift` | 主窗口界面 |
| `DownloadRow.swift` | 单条下载任务的行视图 |
| `SettingsView.swift` | 设置页 |

## 后续功能

- 传入浏览器 cookies 以下载会员/登录内容
- 播放列表 / 多分P 批量下载与勾选
- 内嵌下载缩略图预览、字幕下载
- 打包成签名的 .app 便于分发（目前是开发者本地运行）
