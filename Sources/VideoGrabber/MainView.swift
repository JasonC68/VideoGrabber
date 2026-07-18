import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var manager: DownloadManager
    @State private var pasteURL: String = ""
    @State private var env: (ytdlp: Bool, ffmpeg: Bool) = (true, true)
    @FocusState private var pasteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !env.ytdlp { envWarning }
                    if let s = manager.pendingSuggestion { suggestionBanner(s) }
                    pasteBar

                    if manager.tasks.isEmpty {
                        emptyState
                    } else {
                        taskList
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
        .onAppear { env = manager.checkEnvironment() }
        .sheet(isPresented: $manager.showSettings) {
            settingsSheet
        }
    }

    // MARK: - 顶部标题栏

    private var titleBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple, Color.blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("VideoGrabber").font(.headline)
                Text("视频下载器").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $manager.quality) {
                ForEach(QualityPreference.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)   // 给顶部交通灯让出空间（可按喜好在 18~30 之间微调）
        .padding(.bottom, 12)
    }

    // MARK: - 粘贴栏

    private var pasteBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundColor(.secondary)
            TextField("粘贴视频链接后回车…", text: $pasteURL)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($pasteFocused)
                .onSubmit(submitPaste)
            if !pasteURL.isEmpty {
                Button {
                    pasteURL = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button(action: submitPaste) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundColor(pasteURL.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(pasteURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(pasteFocused ? Color.accentColor : Color.gray.opacity(0.25),
                                lineWidth: pasteFocused ? 2 : 1)
                )
        )
    }

    // MARK: - 环境警告

    private var envWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("未检测到 yt-dlp", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.subheadline.bold())
            Text("正常打包的 App 已内置 yt-dlp；若你是从源码运行（swift run），请确保系统中装有 yt-dlp。")
                .font(.caption).foregroundColor(.secondary)
            Button("重新检测") { env = manager.checkEnvironment() }
                .buttonStyle(.link).font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - 检测到视频的提示

    private func suggestionBanner(_ s: DownloadManager.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("在「\(s.source)」检测到视频", systemImage: "sparkle.magnifyingglass")
                .font(.subheadline.bold())
            Text(s.url).font(.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            HStack {
                Button {
                    manager.enqueue(url: s.url)
                } label: {
                    Label("下载", systemImage: "arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("忽略") { manager.pendingSuggestion = nil }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text("暂无下载任务").font(.callout).foregroundColor(.secondary)
            Text("复制视频链接、在浏览器打开视频页面，或直接在上方粘贴链接")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 任务列表

    private var taskList: some View {
        VStack(spacing: 8) {
            ForEach(manager.tasks) { task in
                DownloadRow(task: task).environmentObject(manager)
            }
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack {
            Button {
                manager.clearFinished()
            } label: {
                Label("清除已完成", systemImage: "trash")
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(!manager.tasks.contains { $0.state.isTerminal })

            Spacer()

            if manager.activeCount > 0 {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("\(manager.activeCount) 个下载中").font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                manager.showSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 设置面板（sheet）

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.headline)
                Spacer()
                Button("完成") { manager.showSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            SettingsView().environmentObject(manager)
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - 动作

    private func submitPaste() {
        let url = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        manager.enqueue(url: url)
        pasteURL = ""
    }
}
