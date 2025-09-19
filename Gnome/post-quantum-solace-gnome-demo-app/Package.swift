// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pqs-demo-app",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://git.aparoksha.dev/aparoksha/adwaita-swift", branch: "main"),
        .package(url: "https://git.aparoksha.dev/aparoksha/localized", branch: "main"),
        .package(url: "https://github.com/needletails/needletail-algorithms.git", from: "2.0.4"),
        .package(url: "https://github.com/needletails/needletail-irc.git", branch: "main"),
        .package(url: "https://github.com/needletails/post-quantum-solace.git", branch: "os/android"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", branch: "websockets")
    ],
    targets: [
        .executableTarget(
            name: "PQSDemoApp",
            dependencies: [
                .product(name: "Adwaita", package: "adwaita-swift"),
                .product(name: "Localized", package: "localized"),
                .product(name: "NeedleTailAlgorithms", package: "needletail-algorithms"),
                .product(name: "NeedleTailIRC", package: "needletail-irc"),
                .product(name: "PostQuantumSolace", package: "post-quantum-solace"),
                .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
            ],
            path: "Sources",
            resources: [
                .process("Localized.yml")
            ],
            plugins: [
                .plugin(name: "GenerateLocalized", package: "localized")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
