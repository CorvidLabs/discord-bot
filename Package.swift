// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "discord-bot",
    platforms: [
        .macOS(.v11),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        // The payout engine is a product in its own right. The bot target that
        // will grow up beside it depends on this library like any other client
        // would, so the engine can never quietly acquire a Discord import.
        .library(name: "Reserve", targets: ["Reserve"])
    ],
    targets: [
        .target(
            name: "Reserve",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ReserveTests",
            dependencies: ["Reserve"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
