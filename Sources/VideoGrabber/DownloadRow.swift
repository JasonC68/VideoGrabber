import SwiftUI

struct DownloadRow: View {
    @EnvironmentObject var manager: DownloadManager
    @ObservedObject var task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline).lineLimit(1).truncationMode(.middle)
                    subtitle
                }
                Spacer()
                actions
            }
            if case let .downloading(progress, _, _) = task.state {
                ProgressView(value: progress).progressViewStyle(.linear)
            } else if case .probing = task.state {
                ProgressView().progressViewStyle(.linear)
            } else if case .merging = task.state {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var statusIcon: some View {
        Group {
            switch task.state {
            case .queued:      Image(systemName: "clock").foregroundColor(.secondary)
            case .probing:     Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            case .downloading: Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
            case .merging:     Image(systemName: "square.stack.3d.down.right").foregroundColor(.accentColor)
            case .finished:    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:      Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch task.state {
        case .queued:
            Text("排队中…").font(.caption2).foregroundColor(.secondary)
        case .probing:
            Text("正在解析…").font(.caption2).foregroundColor(.secondary)
        case let .downloading(progress, speed, eta):
            HStack(spacing: 6) {
                Text("\(Int(progress * 100))%")
                if !speed.isEmpty { Text(speed) }
                if !eta.isEmpty { Text("剩余 \(eta)") }
            }
            .font(.caption2).foregroundColor(.secondary)
        case .merging:
            Text("合并中…").font(.caption2).foregroundColor(.secondary)
        case .finished:
            Text("已完成").font(.caption2).foregroundColor(.green)
        case let .failed(message):
            Text(message).font(.caption2).foregroundColor(.red)
                .lineLimit(2).truncationMode(.tail)
        }
    }

    @ViewBuilder private var actions: some View {
        switch task.state {
        case .queued, .probing, .downloading, .merging:
            Button {
                manager.cancel(task)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless).help("取消")
        case let .finished(path):
            HStack(spacing: 6) {
                Button {
                    manager.revealInFinder(path: path)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless).help("在访达中显示")
                Button {
                    manager.removeFromList(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).help("从列表移除")
            }
        case .failed:
            HStack(spacing: 6) {
                Button {
                    manager.enqueue(url: task.url)
                    manager.removeFromList(task)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless).help("重试")
                Button {
                    manager.removeFromList(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).help("从列表移除")
            }
        }
    }
}
