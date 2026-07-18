import Foundation

/// 判断一段文本里是否包含“看起来像视频页面”的链接，并抽取出来。
enum URLDetector {

    /// 每个平台：域名关键字 + 该平台“视频页面”的路径特征（正则）。
    /// 只有域名命中、且路径命中其一，才认为是可下载的视频页——
    /// 这样首页 / 频道页 / 个人主页（如 bilibili.com/index.html）不会被误判。
    private static let videoRules: [(host: String, patterns: [String])] = [
        ("youtube.com",            [#"/watch"#, #"/shorts/"#, #"/live/"#, #"/embed/"#, #"/playlist"#, #"/clip/"#]),
        ("youtu.be",               [#"/.+"#]),
        ("bilibili.com",           [#"/video/"#, #"/bangumi/"#, #"/festival/"#, #"/cheese/"#, #"/medialist/"#, #"/list/"#, #"/opus/"#]),
        ("b23.tv",                 [#"/.+"#]),
        ("twitter.com",            [#"/status/"#]),
        ("x.com",                  [#"/status/"#]),
        ("tiktok.com",             [#"/video/"#, #"/@[^/]+/video"#, #"/t/"#, #"/v/"#]),
        ("vm.tiktok.com",          [#"/.+"#]),
        ("vt.tiktok.com",          [#"/.+"#]),
        ("douyin.com",             [#"/video/"#, #"/note/"#]),
        ("v.douyin.com",           [#"/.+"#]),
        ("iesdouyin.com",          [#"/.+"#]),
        ("mp.weixin.qq.com",       [#"/s"#]),                 // 公众号文章（可能含视频）
        ("channels.weixin.qq.com", [#"/.+"#]),
        ("finder.video.qq.com",    [#"/.+"#]),
        ("vimeo.com",              [#"/\d+"#]),
        ("weibo.com",              [#"/tv/"#, #"/\d+/[A-Za-z0-9]+"#]),
        ("video.weibo.com",        [#"/.+"#]),
        ("xiaohongshu.com",        [#"/explore/"#, #"/discovery/"#]),
        ("xhslink.com",            [#"/.+"#]),
        ("v.redd.it",              [#"/.+"#]),
        ("reddit.com",             [#"/comments/"#]),
        ("facebook.com",           [#"/videos/"#, #"/watch"#, #"/reel/"#]),
        ("fb.watch",               [#"/.+"#]),
        ("instagram.com",          [#"/reel/"#, #"/p/"#, #"/tv/"#]),
        ("twitch.tv",              [#"/videos/"#, #"/clip/"#, #"/clips\."#]),
        ("dailymotion.com",        [#"/video/"#])
    ]

    /// 从任意文本中抽取第一个 http(s) URL。
    static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, range: range)
        for m in matches {
            if let url = m.url, let scheme = url.scheme, scheme.hasPrefix("http") {
                return url.absoluteString
            }
        }
        return nil
    }

    /// 该 URL 是否属于我们认识的视频平台域名（不判断是不是视频页）。
    static func isKnownVideoHost(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return videoRules.contains { host == $0.host || host.hasSuffix("." + $0.host) }
    }

    /// 该 URL 是否“看起来是一个具体的视频页面”（用于自动检测，避免误报首页）。
    static func looksLikeVideoURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        // 用 path + query 一起匹配（YouTube 的 v= 在 query 里，但 /watch 在 path 里即可命中）
        let pathAndQuery = url.path + (url.query.map { "?" + $0 } ?? "")
        let target = pathAndQuery.isEmpty ? "/" : pathAndQuery

        for rule in videoRules where host == rule.host || host.hasSuffix("." + rule.host) {
            for p in rule.patterns {
                if target.range(of: p, options: .regularExpression) != nil {
                    return true
                }
            }
            return false   // 域名认识但路径不像视频（首页/频道页等）→ 不触发
        }
        return false
    }
}
