import Foundation
import Combine

// MARK: - 视频信息（yt-dlp -J 探测结果的精简映射）

struct VideoInfo: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let title: String
    let uploader: String?
    let durationSeconds: Double?
    let thumbnailURL: String?
    let isPlaylist: Bool
    let entryCount: Int?   // 播放列表/多分P 的条目数

    var durationText: String? {
        guard let d = durationSeconds, d > 0 else { return nil }
        let total = Int(d)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 清晰度 / 输出偏好

enum QualityPreference: String, CaseIterable, Identifiable, Codable {
    case best = "最佳画质"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case audioMP3 = "仅音频 (MP3)"

    var id: String { rawValue }

    /// 映射为 yt-dlp 的 -f 选择表达式（音频单独处理）
    var formatSelector: String {
        switch self {
        case .best:
            return "bv*+ba/b"
        case .p1080:
            return "bv*[height<=1080]+ba/b[height<=1080]/b"
        case .p720:
            return "bv*[height<=720]+ba/b[height<=720]/b"
        case .p480:
            return "bv*[height<=480]+ba/b[height<=480]/b"
        case .audioMP3:
            return "ba/b"
        }
    }

    var isAudioOnly: Bool { self == .audioMP3 }
}

// MARK: - 下载任务

enum DownloadState: Equatable {
    case queued
    case probing          // 正在探测信息
    case downloading(progress: Double, speed: String, eta: String)
    case merging          // 音视频合并 / 后处理
    case finished(path: String)
    case failed(message: String)

    var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .probing, .downloading, .merging: return true
        default: return false
        }
    }
}

final class DownloadTask: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    @Published var title: String
    @Published var state: DownloadState
    let quality: QualityPreference
    let createdAt = Date()

    // 关联的运行中进程，便于取消
    var process: Process?

    init(url: String, title: String, quality: QualityPreference, state: DownloadState = .queued) {
        self.url = url
        self.title = title
        self.quality = quality
        self.state = state
    }
}
