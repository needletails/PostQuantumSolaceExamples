// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sample-core",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SampleCore",
            targets: ["SampleCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.2.0"),
        .package(url: "https://github.com/needletails/needletail-algorithms.git", from: "2.0.4"),
        .package(url: "https://github.com/needletails/needletail-irc.git", branch: "main"),
        .package(url: "https://github.com/needletails/post-quantum-solace.git", from: "2.0.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SampleCore",
            dependencies: [
                .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
                .product(name: "NeedleTailAlgorithms", package: "needletail-algorithms"),
                .product(name: "NeedleTailIRC", package: "needletail-irc"),
                .product(name: "PostQuantumSolace", package: "post-quantum-solace"),
            ],
        ),
        .testTarget(
            name: "sample-coreTests",
            dependencies: ["SampleCore"]
        ),
    ]
)
