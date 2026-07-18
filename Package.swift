// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VideoGrabber",
    platforms: [
        .macOS(.v13)   // MenuBarExtra 需要 macOS 13 Ventura 及以上
    ],
    targets: [
        .executableTarget(
            name: "VideoGrabber",
            path: "Sources/VideoGrabber"
        )
    ]
)
