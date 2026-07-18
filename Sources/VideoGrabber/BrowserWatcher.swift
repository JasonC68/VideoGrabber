import AppKit

/// 通过 AppleScript 读取前台浏览器当前标签页的 URL，实现“检测正在看的视频”。
/// 需要“自动化(Apple Events)”权限——首次读取时系统会弹窗请求授权。
final class BrowserWatcher {

    private var timer: Timer?
    private var lastReportedURL: String?

    /// 前台浏览器出现新的视频页面时触发（已切回主线程）。
    var onVideoURLDetected: ((_ url: String, _ browserName: String) -> Void)?

    /// 支持的浏览器：bundleID -> (显示名, 读取当前标签 URL 的 AppleScript, 应用名)
    private struct BrowserDef {
        let displayName: String
        let appName: String
        let isChromiumLike: Bool
    }

    private let browsers: [String: BrowserDef] = [
        "com.apple.Safari":            .init(displayName: "Safari",  appName: "Safari",             isChromiumLike: false),
        "com.google.Chrome":          .init(displayName: "Chrome",  appName: "Google Chrome",      isChromiumLike: true),
        "com.google.Chrome.canary":   .init(displayName: "Chrome",  appName: "Google Chrome Canary", isChromiumLike: true),
        "com.microsoft.edgemac":      .init(displayName: "Edge",    appName: "Microsoft Edge",     isChromiumLike: true),
        "com.brave.Browser":          .init(displayName: "Brave",   appName: "Brave Browser",      isChromiumLike: true),
        "company.thebrowser.Browser": .init(displayName: "Arc",     appName: "Arc",                isChromiumLike: true),
        "com.vivaldi.Vivaldi":        .init(displayName: "Vivaldi", appName: "Vivaldi",            isChromiumLike: true)
    ]

    func start() {
        stop()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
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
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              let def = browsers[bundleID] else {
            return
        }

        guard let url = currentTabURL(for: def) else { return }
        guard URLDetector.looksLikeVideoURL(url) else { return }
        guard url != lastReportedURL else { return }
        lastReportedURL = url

        onVideoURLDetected?(url, def.displayName)
    }

    private func currentTabURL(for def: BrowserWatcher.BrowserDef) -> String? {
        let script: String
        if def.isChromiumLike {
            script = """
            tell application "\(def.appName)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """
        } else {
            // Safari
            script = """
            tell application "\(def.appName)"
                if (count of documents) is 0 then return ""
                return URL of front document
            end tell
            """
        }

        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return nil }
        let result = apple.executeAndReturnError(&error)
        if error != nil { return nil }   // 未授权或读取失败时静默返回
        let str = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let str, !str.isEmpty, str.hasPrefix("http") else { return nil }
        return str
    }
}
