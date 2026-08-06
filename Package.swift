// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchActivityBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchActivityBar",
            path: "Sources/NotchActivityBar",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
