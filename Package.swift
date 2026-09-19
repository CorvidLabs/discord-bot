// swift-tools-version: 6.1

// Raised from 6.0, which was not true. The resolved graph reaches
// `swift-asn1` 1.7.3 through `swift-crypto`, and that manifest declares tools
// version 6.1.0, so `swift build` on Swift 6.0 stops before it compiles
// anything. It stopped with an error naming somebody else's package, which is
// the worst kind of wrong floor: the person reading it has no way to tell it
// was this manifest that misled them. The number here is now a toolchain that
// can actually build this, and CI builds on exactly it.

import PackageDescription

let package = Package(
    name: "discord-bot",
    // Raised from macOS 11 / iOS 15 by the Chain target, whose rate limiter
    // measures with `ContinuousClock`. A limiter that reads the wall clock
    // hands out free requests whenever the clock is stepped backwards, which
    // is the one thing a limiter exists to prevent, so the floor moves rather
    // than the clock.
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        // The payout engine is a product in its own right. The bot target that
        // will grow up beside it depends on this library like any other client
        // would, so the engine can never quietly acquire a Discord import.
        .library(name: "Reserve", targets: ["Reserve"]),
        .library(name: "Gating", targets: ["Gating"]),
        .library(name: "Games", targets: ["Games"]),
        .library(name: "Chain", targets: ["Chain"])
    ],
    // Up to the next *minor*, not the next major. Semantic versioning gives a
    // 0.x release no compatibility promise at all across a minor bump, so
    // `from: "0.1.0"` was a range in which a dependency is allowed to break
    // this package without breaking its own rules, and a commit that built
    // last week would stop building with nothing here having changed.
    // `Package.resolved` is committed beside this for the same reason: the
    // range says what may be taken, the lock says what was, and TRUST-4 is
    // that a build made from this repository is made of what the repository
    // says. Raising the floor is a pull request somebody reads, which is also
    // what TRUST-1.b asks of a new thing to reach.
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/swift-algorand.git", .upToNextMinor(from: "0.4.0"))
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
        ),

        // The games, as reducers. Clock and randomness arrive as parameters,
        // so a table replays from a seed and a rule can be pinned by a test.
        // Nothing here can reach a chain or sign anything, and it has no
        // dependency through which it could acquire the ability.
        .target(
            name: "Games",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "GamesTests",
            dependencies: ["Games"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // Reading the chain, and the two brakes that stop it reading too much:
        // a per-second limiter and a per-day budget. An answer this layer
        // could not complete says so rather than returning zero.
        .target(
            name: "Chain",
            dependencies: [
                "Gating",
                .product(name: "Algorand", package: "swift-algorand")
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ChainTests",
            dependencies: ["Chain", "Gating"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
