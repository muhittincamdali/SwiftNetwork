// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftNetwork",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SwiftNetwork", targets: ["SwiftNetwork"]),
    ],
    targets: [
        .target(
            name: "SwiftNetwork",
            path: "Sources/SwiftNetwork",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftNetworkTests",
            dependencies: ["SwiftNetwork"]
        )
    ]
)
