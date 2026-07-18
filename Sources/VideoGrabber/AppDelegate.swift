import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObs: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 正常桌面应用：保留 Dock 图标
        NSApp.setActivationPolicy(.regular)
        // 启动后台检测（剪贴板 + 浏览器标签轮询）
        DownloadManager.shared.startMonitors()

        // 按当前明暗模式设置 Dock 图标，并随系统切换实时更新
        updateAppIcon()
        appearanceObs = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateAppIcon() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadManager.shared.stopMonitors()
    }

    /// 关闭主窗口即退出应用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 亮色模式用 AppIconLight，暗色模式用 AppIconDark。
    /// 仅影响运行中应用的 Dock 图标；访达/未运行时仍是打包进去的静态图标。
    private func updateAppIcon() {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = isDark ? "AppIconDark" : "AppIconLight"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = img
        }
        // swift run（无 app bundle）时找不到资源，保持默认图标即可。
    }
}
