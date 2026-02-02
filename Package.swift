// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftNetwork",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftNetwork",
            targets: ["SwiftNetwork"]
        )
    ],
    targets: [
        .target(
            name: "SwiftNetwork",
            path: "Sources/SwiftNetwork"
        ),
        .testTarget(
            name: "SwiftNetworkTests",
            dependencies: ["SwiftNetwork"],
            path: "Tests/SwiftNetworkTests"
        )
    ]
)
