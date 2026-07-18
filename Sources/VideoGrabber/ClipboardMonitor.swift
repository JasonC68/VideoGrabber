import AppKit

/// 轮询系统剪贴板，发现新的视频链接时回调。
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastReportedURL: String?

    /// 发现候选视频链接时触发（已切回主线程）。
    var onVideoURLDetected: ((String) -> Void)?

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        guard let url = URLDetector.firstURL(in: text) else { return }
        // 只对“看起来是具体视频页”的链接主动提示，避免复制首页/普通网址也弹窗
        guard URLDetector.looksLikeVideoURL(url) else { return }
        guard url != lastReportedURL else { return }
        lastReportedURL = url

        onVideoURLDetected?(url)
    }
}
