// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "post-quantum-solace-skip-demo",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PostQuantumSolaceSkipDemo", type: .dynamic, targets: ["PostQuantumSolaceSkipDemo"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.17"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/needletails/needletail-algorithms.git", from: "2.0.4"),
        .package(url: "https://github.com/needletails/needletail-irc.git", branch: "main"),
        .package(url: "https://github.com/needletails/post-quantum-solace.git", from: "2.0.0"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.2.0")
    ],
    targets: [
        .target(name: "PostQuantumSolaceSkipDemo", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "NeedleTailAlgorithms", package: "needletail-algorithms"),
            .product(name: "NeedleTailIRC", package: "needletail-irc"),
            .product(name: "PostQuantumSolace", package: "post-quantum-solace"),
            .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
