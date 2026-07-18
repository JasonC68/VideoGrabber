import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var manager: DownloadManager

    var body: some View {
        Form {
            Section("下载") {
                HStack {
                    TextField("下载目录", text: $manager.downloadDir)
                    Button("选择…") { chooseDownloadDir() }
                }
                Picker("默认清晰度", selection: $manager.quality) {
                    ForEach(QualityPreference.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
            }

            Section("检测方式") {
                Toggle("监听剪贴板中的视频链接", isOn: $manager.clipboardEnabled)
                Toggle("检测浏览器当前标签页（需自动化权限）", isOn: $manager.browserEnabled)
                Toggle("检测到即自动下载（否则先提示）", isOn: $manager.autoDownload)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 文件选择

    private func chooseDownloadDir() {
        chooseDir(binding: $manager.downloadDir)
    }

    private func chooseDir(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}
