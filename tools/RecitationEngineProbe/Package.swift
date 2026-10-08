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
        .executableTarget(name: "RecitationEngineProbe", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ]),
        .testTarget(name: "RecitationEngineProbeTests", dependencies: ["RecitationEngineProbe"])
    ]
)
