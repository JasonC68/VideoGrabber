import Foundation

/// 封装对 yt-dlp / ffmpeg 命令行的调用。
final class YTDLPService {

    enum ServiceError: LocalizedError {
        case binaryNotFound
        case probeFailed(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "未找到 yt-dlp。正常打包的 App 已内置；若从源码运行，请确保系统中装有 yt-dlp。"
            case .probeFailed(let m):
                return "解析视频信息失败：\(m)"
            }
        }
    }

    /// App 内置的二进制目录（Contents/Resources/bin），自包含分发的关键。
    static var bundledBinDir: String? {
        Bundle.main.resourceURL?.appendingPathComponent("bin").path
    }

    /// 常见的二进制安装位置（Apple Silicon 与 Intel）。
    private static let commonBinDirs = [
        "/opt/homebrew/bin",   // Apple Silicon Homebrew
        "/usr/local/bin",      // Intel Homebrew
        "/usr/bin",
        "/opt/local/bin"       // MacPorts
    ]

    /// 查找可执行文件：内置版本优先 → 手动指定 → 常见目录 → PATH。
    static func locate(_ name: String, override: String? = nil) -> String? {
        // 1) App 内置（自包含），优先，保证无 Homebrew 也能用
        if let binDir = bundledBinDir {
            let p = (binDir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        // 2) 用户在设置里手动指定
        if let override, !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        // 3) 常见安装目录
        for dir in commonBinDirs {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        // 4) 兜底：登录 shell 的 PATH
        if let p = which(name) { return p }
        return nil
    }

    /// 解析出 ffmpeg 所在“目录”，用于显式传给 yt-dlp（--ffmpeg-location）。
    /// override 可以是目录，也可以是 ffmpeg 二进制文件本身。
    static func resolvedFFmpegDir(override: String?) -> String? {
        if let override, !override.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: override, isDirectory: &isDir) {
                return isDir.boolValue ? override : (override as NSString).deletingLastPathComponent
            }
        }
        if let bin = locate("ffmpeg") {
            return (bin as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// 图形界面启动的进程 PATH 很精简，这里补上常见的二进制目录，
    /// 保证 yt-dlp 能调用到 ffmpeg / ffprobe。
    static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var dirs = commonBinDirs
        if let binDir = bundledBinDir { dirs.insert(binDir, at: 0) }   // 内置目录优先
        let extra = dirs.joined(separator: ":")
        if let path = env["PATH"], !path.isEmpty {
            env["PATH"] = extra + ":" + path
        } else {
            env["PATH"] = extra
        }
        return env
    }

    private static func which(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let out, !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) {
                return out
            }
        } catch { }
        return nil
    }

    // MARK: - 探测视频信息

    /// 用 `yt-dlp -J` 探测。会阻塞，请在后台线程调用。
    static func probe(url: String, ytdlpPath: String?) throws -> VideoInfo {
        guard let bin = locate("yt-dlp", override: ytdlpPath) else {
            throw ServiceError.binaryNotFound
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.environment = augmentedEnvironment()
        // --flat-playlist：播放列表只取概要，避免展开成百上千条目卡住
        task.arguments = ["-J", "--no-warnings", "--flat-playlist", url]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        try task.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0, !outData.isEmpty else {
            let msg = String(data: errData, encoding: .utf8) ?? "未知错误"
            throw ServiceError.probeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            throw ServiceError.probeFailed("返回内容无法解析为 JSON")
        }

        let type = json["_type"] as? String
        let isPlaylist = (type == "playlist")
        let title = (json["title"] as? String) ?? (json["id"] as? String) ?? "未命名视频"
        let uploader = json["uploader"] as? String
        let duration = json["duration"] as? Double
        let thumb = json["thumbnail"] as? String
        var entryCount: Int? = nil
        if let entries = json["entries"] as? [[String: Any]] {
            entryCount = entries.count
        } else if let n = json["playlist_count"] as? Int {
            entryCount = n
        }

        return VideoInfo(
            url: url,
            title: title,
            uploader: uploader,
            durationSeconds: duration,
            thumbnailURL: thumb,
            isPlaylist: isPlaylist,
            entryCount: entryCount
        )
    }

    // MARK: - 下载

    /// 构造下载参数。
    private static func buildDownloadArgs(
        url: String,
        quality: QualityPreference,
        outputDir: String,
        ffmpegDir: String?
    ) -> [String] {
        var args: [String] = ["--newline", "--no-warnings", "--restrict-filenames"]

        // 输出模板：目录/标题.扩展名
        let template = (outputDir as NSString).appendingPathComponent("%(title)s [%(id)s].%(ext)s")
        args += ["-o", template]

        let hasFFmpeg = (ffmpegDir?.isEmpty == false)
        if let ffmpegDir, hasFFmpeg {
            args += ["--ffmpeg-location", ffmpegDir]
        }

        if quality.isAudioOnly {
            if hasFFmpeg {
                args += ["-f", quality.formatSelector, "-x", "--audio-format", "mp3", "--audio-quality", "0"]
            } else {
                // 无 ffmpeg 时无法转码，直接下最佳音频原格式（通常 m4a/webm）
                args += ["-f", "ba/b"]
            }
        } else if hasFFmpeg {
            // 有 ffmpeg：分离的高清视频轨 + 音频轨，下载后合并成 mp4
            args += ["-f", quality.formatSelector, "--merge-output-format", "mp4"]
        } else {
            // 无 ffmpeg：只能选“已经带声音的单文件”，避免下出没声音的画面。
            // 这类预合成格式在 YouTube 上通常最高 720p。
            let heightCap: String
            switch quality {
            case .p480: heightCap = "[height<=480]"
            case .p720, .p1080, .best: heightCap = "[height<=720]"
            case .audioMP3: heightCap = ""
            }
            args += ["-f", "b\(heightCap)[acodec!=none][vcodec!=none]/b[acodec!=none][vcodec!=none]/b"]
        }

        args.append(url)
        return args
    }

    /// 启动下载。进度回调在后台线程触发，UI 更新需自行切回主线程。
    /// - Returns: 启动的 Process（便于取消）。
    @discardableResult
    static func download(
        task modelTask: DownloadTask,
        ytdlpPath: String?,
        ffmpegDir: String?,
        outputDir: String,
        onProgress: @escaping (Double, String, String) -> Void,
        onMerging: @escaping () -> Void,
        onFinished: @escaping (String) -> Void,
        onFailed: @escaping (String) -> Void
    ) -> Process? {
        guard let bin = locate("yt-dlp", override: ytdlpPath) else {
            onFailed(ServiceError.binaryNotFound.localizedDescription)
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.environment = augmentedEnvironment()
        // 总是自动定位 ffmpeg 目录并显式传给 yt-dlp，避免 GUI 启动时因 PATH
        // 精简而找不到 ffmpeg，导致音视频无法合并（mp4 无声 / webm 无画面）。
        let ffmpegLocation = resolvedFFmpegDir(override: ffmpegDir)
        process.arguments = buildDownloadArgs(
            url: modelTask.url,
            quality: modelTask.quality,
            outputDir: outputDir,
            ffmpegDir: ffmpegLocation
        )

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var lastDestination: String = ""
        var collectedError = ""

        // 逐行读取 stdout 解析进度
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = String(rawLine)
                if let dest = ProgressParser.destination(from: line) {
                    lastDestination = dest
                }
                if line.contains("[Merger]") || line.contains("[ExtractAudio]") || line.contains("Merging formats") {
                    onMerging()
                }
                if let p = ProgressParser.parse(line: line) {
                    onProgress(p.percent, p.speed, p.eta)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collectedError += text
        }

        process.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            if proc.terminationStatus == 0 {
                let finalPath = lastDestination.isEmpty ? outputDir : lastDestination
                onFinished(finalPath)
            } else {
                let msg = collectedError.trimmingCharacters(in: .whitespacesAndNewlines)
                onFailed(friendlyError(msg, exitCode: proc.terminationStatus))
            }
        }

        do {
            try process.run()
            modelTask.process = process
            return process
        } catch {
            onFailed("无法启动 yt-dlp：\(error.localizedDescription)")
            return nil
        }
    }

    /// 把 yt-dlp 的英文报错翻成看得懂、能操作的提示。
    static func friendlyError(_ raw: String, exitCode: Int32) -> String {
        let lower = raw.lowercased()
        if lower.contains("unsupported url") {
            return "这个链接里没有可下载的视频（可能是首页、频道页或非视频页面）。请打开具体的视频页面，再复制那一页的地址。"
        }
        if lower.contains("unable to extract") || lower.contains("no video formats") {
            return "解析失败：可能该视频需要登录/会员、有地区限制，或站点近期改版。可稍后重试，或等待 App 更新内置的 yt-dlp。"
        }
        if lower.contains("private") || lower.contains("members-only") || lower.contains("sign in") || lower.contains("login") {
            return "该视频需要登录或会员权限才能访问，当前版本尚未支持传入浏览器 Cookie。"
        }
        if lower.contains("drm") {
            return "该内容受 DRM 加密保护，无法下载（如 Netflix 等付费流媒体）。"
        }
        if lower.contains("geo") && lower.contains("restrict") || lower.contains("not available in your country") {
            return "该视频在当前地区不可用（地区限制）。"
        }
        if lower.contains("ffmpeg") {
            return "需要 ffmpeg 才能完成合并/转码。正常打包的 App 已内置 ffmpeg；若从源码运行，请确保系统中装有 ffmpeg。"
        }
        if raw.isEmpty {
            return "下载失败（退出码 \(exitCode)）。"
        }
        // 兜底：截断过长的原始英文报错
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ")
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }
}

// MARK: - 进度解析

enum ProgressParser {
    // 例：[download]  42.7% of 120.34MiB at  3.21MiB/s ETA 00:23
    private static let progressRegex = try! NSRegularExpression(
        pattern: #"\[download\]\s+([0-9.]+)%.*?(?:at\s+([0-9.]+\s*[KMG]?i?B/s))?.*?(?:ETA\s+([0-9:]+))?"#,
        options: []
    )
    // 例：[download] Destination: /path/to/file.mp4
    private static let destRegex = try! NSRegularExpression(
        pattern: #"\[download\]\s+Destination:\s+(.+)$"#,
        options: []
    )
    // 例：[Merger] Merging formats into "/path/to/file.mp4"
    private static let mergeDestRegex = try! NSRegularExpression(
        pattern: #"Merging formats into\s+"(.+)""#,
        options: []
    )

    struct Progress { let percent: Double; let speed: String; let eta: String }

    static func parse(line: String) -> Progress? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = progressRegex.firstMatch(in: line, range: range) else { return nil }
        guard let pr = Range(m.range(at: 1), in: line), let percent = Double(line[pr]) else { return nil }
        var speed = ""
        var eta = ""
        if m.range(at: 2).location != NSNotFound, let sr = Range(m.range(at: 2), in: line) {
            speed = line[sr].trimmingCharacters(in: .whitespaces)
        }
        if m.range(at: 3).location != NSNotFound, let er = Range(m.range(at: 3), in: line) {
            eta = String(line[er])
        }
        return Progress(percent: percent / 100.0, speed: speed, eta: eta)
    }

    static func destination(from line: String) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let m = destRegex.firstMatch(in: line, range: range),
           let r = Range(m.range(at: 1), in: line) {
            return line[r].trimmingCharacters(in: .whitespaces)
        }
        if let m = mergeDestRegex.firstMatch(in: line, range: range),
           let r = Range(m.range(at: 1), in: line) {
            return line[r].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
