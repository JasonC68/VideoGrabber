import AppKit
import SwiftUI
import Combine
import UserNotifications

/// 全局状态与业务中枢：管理设置、检测器、下载队列。
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    // MARK: - 发布状态
    @Published var tasks: [DownloadTask] = []
    /// 最近检测到、尚未处理的候选链接（来源：剪贴板 / 浏览器）
    @Published var pendingSuggestion: Suggestion?
    @Published var statusMessage: String = ""
    /// 控制设置面板显示（sheet）
    @Published var showSettings: Bool = false

    struct Suggestion: Equatable {
        let url: String
        let source: String   // "剪贴板" / "Safari" 等
    }

    // MARK: - 设置（@Published + UserDefaults 持久化）
    private let defaults = UserDefaults.standard

    @Published var downloadDir: String {
        didSet { defaults.set(downloadDir, forKey: "downloadDir") }
    }
    @Published var quality: QualityPreference {
        didSet { defaults.set(quality.rawValue, forKey: "quality") }
    }
    @Published var ytdlpPath: String {
        didSet { defaults.set(ytdlpPath, forKey: "ytdlpPath") }
    }
    @Published var ffmpegDir: String {
        didSet { defaults.set(ffmpegDir, forKey: "ffmpegDir") }
    }
    @Published var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: "clipboardEnabled"); refreshMonitors() }
    }
    @Published var browserEnabled: Bool {
        didSet { defaults.set(browserEnabled, forKey: "browserEnabled"); refreshMonitors() }
    }
    @Published var autoDownload: Bool {   // 检测到即自动下载
        didSet { defaults.set(autoDownload, forKey: "autoDownload") }
    }

    // MARK: - 检测器
    private let clipboard = ClipboardMonitor()
    private let browser = BrowserWatcher()

    var activeCount: Int { tasks.filter { $0.state.isActive }.count }

    private init() {
        let defaultDownloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
        downloadDir = defaults.string(forKey: "downloadDir") ?? defaultDownloads
        quality = QualityPreference(rawValue: defaults.string(forKey: "quality") ?? "") ?? .best
        ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? ""
        ffmpegDir = defaults.string(forKey: "ffmpegDir") ?? ""
        clipboardEnabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        browserEnabled = defaults.object(forKey: "browserEnabled") as? Bool ?? true
        autoDownload = defaults.object(forKey: "autoDownload") as? Bool ?? false

        // 通知中心需要正规 app bundle；用 `swift run` 直接跑裸可执行文件时没有
        // bundleIdentifier，调用会崩溃，这里做保护。
        if Self.notificationsAvailable {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// 是否处于可用通知的环境（有正规 bundle）。
    private static let notificationsAvailable: Bool = (Bundle.main.bundleIdentifier != nil)

    // MARK: - 检测器生命周期

    func startMonitors() {
        clipboard.onVideoURLDetected = { [weak self] url in
            Task { @MainActor in self?.handleDetected(url: url, source: "剪贴板") }
        }
        browser.onVideoURLDetected = { [weak self] url, name in
            Task { @MainActor in self?.handleDetected(url: url, source: name) }
        }
        if clipboardEnabled { clipboard.start() }
        if browserEnabled { browser.start() }
    }

    func stopMonitors() {
        clipboard.stop()
        browser.stop()
    }

    func refreshMonitors() {
        clipboardEnabled ? clipboard.start() : clipboard.stop()
        browserEnabled ? browser.start() : browser.stop()
    }

    private func handleDetected(url: String, source: String) {
        // 已在队列里的就不重复提示
        if tasks.contains(where: { $0.url == url && !$0.state.isTerminal }) { return }
        if autoDownload {
            enqueue(url: url)
        } else {
            pendingSuggestion = Suggestion(url: url, source: source)
        }
    }

    // MARK: - 队列

    /// 用户手动粘贴 / 点击建议 / 自动下载 都走这里。
    func enqueue(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pendingSuggestion?.url == trimmed { pendingSuggestion = nil }

        let task = DownloadTask(url: trimmed, title: trimmed, quality: quality, state: .probing)
        tasks.insert(task, at: 0)

        // 后台探测标题，再开始下载
        let ytdlp = ytdlpPath.isEmpty ? nil : ytdlpPath
        DispatchQueue.global(qos: .userInitiated).async {
            let info = try? YTDLPService.probe(url: trimmed, ytdlpPath: ytdlp)
            Task { @MainActor in
                if let info { task.title = info.title }
                self.performDownload(task)
            }
        }
    }

    private func performDownload(_ task: DownloadTask) {
        let ytdlp = ytdlpPath.isEmpty ? nil : ytdlpPath
        let ffmpeg = ffmpegDir.isEmpty ? nil : ffmpegDir
        let dir = downloadDir

        task.state = .downloading(progress: 0, speed: "", eta: "")

        DispatchQueue.global(qos: .userInitiated).async {
            YTDLPService.download(
                task: task,
                ytdlpPath: ytdlp,
                ffmpegDir: ffmpeg,
                outputDir: dir,
                onProgress: { percent, speed, eta in
                    Task { @MainActor in
                        task.state = .downloading(progress: percent, speed: speed, eta: eta)
                    }
                },
                onMerging: {
                    Task { @MainActor in task.state = .merging }
                },
                onFinished: { path in
                    Task { @MainActor in
                        task.state = .finished(path: path)
                        self.notify(title: "下载完成", body: task.title)
                    }
                },
                onFailed: { message in
                    Task { @MainActor in
                        task.state = .failed(message: message)
                    }
                }
            )
        }
    }

    func cancel(_ task: DownloadTask) {
        task.process?.terminate()
        task.state = .failed(message: "已取消")
    }

    func removeFromList(_ task: DownloadTask) {
        if task.state.isActive { task.process?.terminate() }
        tasks.removeAll { $0.id == task.id }
    }

    func clearFinished() {
        tasks.removeAll { $0.state.isTerminal }
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 通知

    private func notify(title: String, body: String) {
        guard Self.notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - 环境自检

    /// 返回 (yt-dlp 是否就绪, ffmpeg 是否就绪)
    func checkEnvironment() -> (ytdlp: Bool, ffmpeg: Bool) {
        let y = YTDLPService.locate("yt-dlp", override: ytdlpPath.isEmpty ? nil : ytdlpPath) != nil
        let f = YTDLPService.locate("ffmpeg", override: nil) != nil
        return (y, f)
    }
}
