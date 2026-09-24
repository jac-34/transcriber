// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transcriptor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Transcriptor", targets: ["Transcriptor"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TranscriptorCore"),
        .target(name: "TranscriptorEngine", dependencies: ["TranscriptorCore"]),
        .executableTarget(
            name: "Transcriptor",
            dependencies: ["TranscriptorCore", "TranscriptorEngine"]
        ),
        .testTarget(name: "TranscriptorCoreTests", dependencies: ["TranscriptorCore"]),
        .testTarget(name: "TranscriptorEngineTests", dependencies: ["TranscriptorEngine", "TranscriptorCore"]),
    ],
    swiftLanguageModes: [.v6]
)
