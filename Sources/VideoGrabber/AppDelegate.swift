import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 正常桌面应用：保留 Dock 图标
        NSApp.setActivationPolicy(.regular)
        // 启动后台检测（剪贴板 + 浏览器标签轮询）
        DownloadManager.shared.startMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadManager.shared.stopMonitors()
    }

    /// 关闭主窗口即退出应用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
