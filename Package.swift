// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetraTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MetraTracker",
            path: "Sources/MetraTracker"
        )
    ]
)
