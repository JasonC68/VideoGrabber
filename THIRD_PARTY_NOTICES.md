# 第三方组件与许可（Third-Party Notices）

VideoGrabber 自身代码以 MIT 许可开源（见 `LICENSE`）。
但本应用**在构建时会下载、并在分发的 .app / .dmg 中捆绑**以下第三方程序。
它们作为**独立的可执行文件被调用（子进程）**，不与本应用代码静态/动态链接。
这些组件不随本 Git 仓库分发（见 `.gitignore` 排除 `vendor/`），仅在构建时获取。

---

## yt-dlp

- 用途：视频信息解析与下载核心。
- 许可：**The Unlicense**（公有领域，无限制）。
- 项目主页 / 源码：https://github.com/yt-dlp/yt-dlp
- 使用的构建：官方 `yt-dlp_macos` 独立可执行文件（自带 Python 运行时）。

## FFmpeg

- 用途：将分离的音频轨与视频轨合并为 mp4、音频转码等。
- 许可：**GPL**（本项目采用的静态构建启用了 GPL 组件，因此整体为 GPL v2 或更高版本）。
  FFmpeg 本体为 LGPL v2.1+，但含 GPL 编解码器的构建整体受 GPL 约束。
- 项目主页 / 源码：https://ffmpeg.org  （源码：https://git.ffmpeg.org/ffmpeg.git）
- 使用的构建来源：https://github.com/eugeneware/ffmpeg-static
  （该仓库的打包脚本为 MIT，但其产出的 ffmpeg 二进制为 GPL）。

### 关于 GPL 合规（当你分发 .dmg / .app 时）

1. 本应用通过 `Process`/exec 以**独立进程**方式调用 ffmpeg，不与之链接，
   因此本应用自身的源代码可继续以 MIT 许可发布。
2. 分发含 ffmpeg 的二进制时，应：
   - 保留本文件（FFmpeg 的许可与版权声明）；
   - 提供对应源码的获取途径。由于捆绑的是**未经修改的上游二进制**，
     指向上述 FFmpeg 官方源码与 `eugeneware/ffmpeg-static` 发布页即可满足；
     如你自行修改过 ffmpeg，则须一并提供你的修改源码。
3. 如需彻底避免 GPL 义务，可改为捆绑 **LGPL 版**的 ffmpeg（不启用 GPL 编解码器），
   或不捆绑、改为运行时让用户自行提供 ffmpeg。

---

## 应用图标

`Icon/` 下的应用图标为作者提供的原创/自有素材，不属于上述第三方组件。

## 免责声明

本工具仅应用于下载你拥有版权、已获授权或平台允许的内容。
下载受版权保护的内容或违反平台服务条款的行为由使用者自行承担责任。
