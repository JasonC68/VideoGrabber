import SwiftUI

@main
struct VideoGrabberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = DownloadManager.shared

    var body: some Scene {
        // 正常桌面窗口应用（有 Dock 图标、可最小化/缩放）
        Window("VideoGrabber", id: "main") {
            MainView()
                .environmentObject(manager)
                .frame(minWidth: 460, minHeight: 640)
        }
        .defaultSize(width: 540, height: 720)
        .windowStyle(.hiddenTitleBar)   // 隐藏标题栏，内容延伸到顶部、交通灯浮在玻璃上
        .commands {
            // 用“设置…”替换默认的 App 菜单设置项，Cmd+, 打开
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    DownloadManager.shared.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
