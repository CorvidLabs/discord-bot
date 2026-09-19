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
        // The program. Exactly one executable product, so bare `swift run` is
        // unambiguous and an operator following the README types one thing.
        //
        // `Runtime` is deliberately **not** a product. A product is a promise
        // about an API, and the composition root is at its least stable
        // moment: it grows a parameter every time a surface lands. Keeping it
        // a plain target means the executable and the tests reach it and
        // nobody downstream can depend on its shape. Promoting a target to a
        // product later breaks nobody; demoting one is a breaking change.
        // `StoreTestKit` is the precedent already in this manifest.
        .executable(name: "bot", targets: ["BotMain"]),

        // The payout engine is a product in its own right. The bot target that
        // will grow up beside it depends on this library like any other client
        // would, so the engine can never quietly acquire a Discord import.
        .library(name: "Reserve", targets: ["Reserve"]),
        .library(name: "Gating", targets: ["Gating"]),
        .library(name: "Games", targets: ["Games"]),
        .library(name: "Chain", targets: ["Chain"]),

        // The records and the two protocols a host writes against, plus a
        // store in memory that passes the same conformance suite the durable
        // one does. A contributor needs nothing installed to use it.
        .library(name: "Store", targets: ["Store"]),

        // The durable store, on the SQLite the operating system already
        // ships. Separate from `Store` so a host that wants the records and
        // the in-memory backend never links a database at all.
        .library(name: "StoreSQLite", targets: ["StoreSQLite"]),
        .library(name: "Verify", targets: ["Verify"])
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
        .package(url: "https://github.com/CorvidLabs/swift-algorand.git", .upToNextMinor(from: "0.4.0")),

        // Declared here rather than reached through `swift-algorand`, which
        // links `Crypto` without re-exporting it. `Verify` checks an Ed25519
        // signature against a public key on its own, and the only verify the
        // Algorand package offers is a method on a type that holds a private
        // key, which is precisely what that target must never hold. A
        // dependency a package uses and has not declared is one it cannot
        // pin, and TRUST-1.b is that something new to reach is a diff
        // somebody reads. Already resolved at 3.15.1 through the line above,
        // so this moves no version.
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.15.1"))
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
        ),

        // What one instance remembers between restarts: the members, the
        // accounts they proved, the ladder's own safety baseline, and the two
        // seams the engine already declared.
        //
        // It declares no chat client, so `import DiscordBM` here is a missing
        // module rather than a review comment, and a member is a `String`. The
        // adapter that will know about snowflakes depends on this target, and
        // SwiftPM refuses a cycle, so this one can never acquire it back.
        .target(
            name: "Store",
            dependencies: ["Reserve", "Gating", "Chain"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // The conformance suite, as a product nobody ships. It is a plain
        // target rather than a library, and no product reaches it, so it is
        // never built into anything that depends on this package: test code
        // does not travel, and a failure still points at a real line.
        .target(
            name: "StoreTestKit",
            dependencies: ["Store"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // The platform's libsqlite3, and nothing else. No amalgamation is
        // vendored, so this adds no pin and the durability engine underneath
        // is the one the machine already trusts and already patches.
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [
                .apt(["libsqlite3-dev"]),
                .yum(["sqlite-devel"])
            ]
        ),

        // The durable backend. Hand-written C interop over a write-ahead log
        // this package did not write, which is the trade: the part that must
        // not lose a payment record is twenty-five years old, and only the
        // thin layer above it is ours.
        .target(
            name: "StoreSQLite",
            dependencies: ["Store", "CSQLite"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // The composition root: the boot gates, the settings catalogue, the
        // startup report, the health state and the listener.
        //
        // It may never depend on a chat SDK and never on a database. Not on a
        // chat SDK, because the chat seam here is a protocol over Foundation
        // types with a role and a member both `String`: the adapter that
        // knows about snowflakes will depend on this target, and SwiftPM
        // refuses a cycle, so this one can never acquire it back and `Store`
        // is two edges further away still, which is what keeps the guarantee
        // the `Store` comment above already claims. Not on a database,
        // because it takes `any BotStore` and the concrete durable store is
        // chosen in the executable.
        //
        // Not `Games` and not `Reserve` either: neither is reachable without
        // a surface to play on or a payer to pay with.
        .target(
            name: "Runtime",
            dependencies: ["Gating", "Chain", "Store"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // The program. Argument handling, the one snapshot of the process
        // environment, the construction of the live seams, signal handling
        // and the exit. Nothing here decides anything, and it is the only
        // place both `Runtime` and a concrete store are visible, which is
        // what makes "what can this build reach" one function rather than a
        // search.
        .executableTarget(
            name: "BotMain",
            dependencies: ["Runtime", "StoreSQLite"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        .testTarget(
            name: "StoreTests",
            dependencies: ["Store", "StoreTestKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StoreSQLiteTests",
            dependencies: ["StoreSQLite", "Store", "StoreTestKit", "CSQLite"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        // Depends on `StoreSQLite` because the boot's own tests compose a
        // real store: `SQLiteStore.inMemory()` and a file under the test's
        // own temporary directory. Everything else they need is a stub, a spy
        // or a loopback bind on port zero, so the whole suite still reaches
        // no chain, no server and no account.
        // Proving a member owns an account. It reads nothing and holds
        // nothing that could: no store, so it cannot write a record; no chain
        // reader, so it cannot spend a request; no chat package, so a member
        // is an opaque string it never interprets.
        .target(
            name: "Verify",
            dependencies: [
                .product(name: "Algorand", package: "swift-algorand"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "VerifyTests",
            dependencies: ["Verify"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),

        .testTarget(
            name: "RuntimeTests",
            dependencies: ["Runtime", "Store", "StoreSQLite", "Gating", "Chain"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
