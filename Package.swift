// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transcriptor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Transcriptor", targets: ["Transcriptor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
    ],
    targets: [
        .target(name: "TranscriptorCore"),
        .target(
            name: "TranscriptorEngine",
            dependencies: [
                "TranscriptorCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .executableTarget(
            name: "Transcriptor",
            dependencies: ["TranscriptorCore", "TranscriptorEngine"]
        ),
        .testTarget(name: "TranscriptorCoreTests", dependencies: ["TranscriptorCore"]),
        .testTarget(name: "TranscriptorEngineTests", dependencies: ["TranscriptorEngine", "TranscriptorCore"]),
    ],
    swiftLanguageModes: [.v6]
)
