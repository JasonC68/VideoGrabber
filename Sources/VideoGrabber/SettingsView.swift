import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var manager: DownloadManager
    @State private var env: (ytdlp: Bool, ffmpeg: Bool) = (true, true)

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

            Section("依赖工具") {
                LabeledContent("yt-dlp") {
                    Label(env.ytdlp ? "已就绪" : "未找到",
                          systemImage: env.ytdlp ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(env.ytdlp ? .green : .red)
                }
                LabeledContent("ffmpeg") {
                    Label(env.ffmpeg ? "已就绪" : "未找到（合并高清视频需要）",
                          systemImage: env.ffmpeg ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(env.ffmpeg ? .green : .orange)
                }
                HStack {
                    TextField("yt-dlp 路径（留空自动查找）", text: $manager.ytdlpPath)
                    Button("选择…") { chooseFile(binding: $manager.ytdlpPath) }
                }
                HStack {
                    TextField("ffmpeg 所在目录（留空自动查找）", text: $manager.ffmpegDir)
                    Button("选择…") { chooseDir(binding: $manager.ffmpegDir) }
                }
                Button("重新检测依赖") { env = manager.checkEnvironment() }
                Text("推荐用 Homebrew 安装：brew install yt-dlp ffmpeg")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { env = manager.checkEnvironment() }
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

    private func chooseFile(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}
