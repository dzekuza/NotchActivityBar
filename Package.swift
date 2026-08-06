// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchActivityBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchActivityBar",
            path: "Sources/NotchActivityBar",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                // Embed Info.plist so the bare executable (swift run / Xcode scheme)
                // has a bundle identifier; without it, App Intents registration and
                // window-tab indexing log errors at launch.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ]),
            ]
        )
    ]
)
