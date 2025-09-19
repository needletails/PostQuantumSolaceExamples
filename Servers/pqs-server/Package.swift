// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pqs-server",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PQSServerCore", targets: ["PQSServerCore"]),
        .executable(name: "pqs-server", targets: ["pqs-server"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.16.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.6.0"),
        .package(url: "https://github.com/needletails/needletail-irc.git", branch: "main" ),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.0")
    ],
    targets: [
        .target(
            name: "PQSServerCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdHTTP2", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HummingbirdWSCompression", package: "hummingbird-websocket"),
                .product(name: "NeedleTailIRC", package: "needletail-irc"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/PQSServerCore"
        ),
        .executableTarget(
            name: "pqs-server",
            dependencies: [
                "PQSServerCore"
            ],
            path: "Sources/pqs-server"
        ),
    ]
)
