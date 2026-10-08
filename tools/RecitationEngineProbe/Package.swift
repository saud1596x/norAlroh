// swift-tools-version: 5.10
import PackageDescription

// Investigation only. This executable is not linked into the shipping app.
let package = Package(
    name: "RecitationEngineProbe",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git",
                 revision: "1e2a163736dfa5a198e637ae44c114e1c6d5cc2d")
    ],
    targets: [
        .target(name: "RecitationAlignment"),
        .target(name: "RecitationCapture"),
        .target(name: "RecitationSessions", dependencies: ["RecitationAlignment"]),
        .target(name: "RecitationEvidence", path: "Sources/RecitationEngineProbe",
                exclude: ["Probe.swift"], sources: ["AudioEvidenceGate.swift"]),
        .executableTarget(name: "RecitationEngineProbe", dependencies: [
            "RecitationEvidence",
            "RecitationAlignment",
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ], exclude: ["AudioEvidenceGate.swift"], sources: ["Probe.swift"]),
        .testTarget(name: "RecitationEngineProbeTests", dependencies: ["RecitationEvidence", "RecitationAlignment", "RecitationCapture", "RecitationSessions", .product(name: "WhisperKit", package: "argmax-oss-swift")])
    ]
)
