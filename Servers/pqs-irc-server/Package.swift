// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pqs-irc-server",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PQSIRCCore", targets: ["PQSIRCCore"]),
        .executable(name: "pqs-irc-server", targets: ["pqs-irc-server"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.28.0"),
        .package(url: "https://github.com/needletails/needletail-irc.git", branch: "main"),
        .package(url: "https://github.com/needletails/connection-manager-kit.git", from: "2.2.0"),
        .package(url: "https://github.com/needletails/swift-crypto.git", from: "1.0.1"),
        .package(url: "https://github.com/needletails/binary-codable.git", from: "1.0.3")
    ],
    targets: [
        .target(
            name: "PQSIRCCore",
            dependencies: [
                .product(name: "ConnectionManagerKit", package: "connection-manager-kit"),
                .product(name: "NeedleTailIRC", package: "needletail-irc"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "BinaryCodable", package: "binary-codable")
            ],
            path: "Sources/PQSIRCCore"
        ),
        .executableTarget(
            name: "pqs-irc-server",
            dependencies: [
                "PQSIRCCore"
            ],
            path: "Sources/pqs-irc-server"
        ),
    ]
)
