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
        .library(name: "Reserve", targets: ["Reserve"]),
        .library(name: "Gating", targets: ["Gating"])
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
        ),

        // What holding something on chain earns somebody in a server. Pure
        // arithmetic over operator configuration: no network, no database, no
        // Discord types. A role is a plain string here and becomes a snowflake
        // at the Discord boundary, which is what lets the whole rule set be
        // tested without a guild.
        .target(
            name: "Gating",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "GatingTests",
            dependencies: ["Gating"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
