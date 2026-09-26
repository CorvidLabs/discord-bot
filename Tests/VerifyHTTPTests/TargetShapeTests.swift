import Foundation
import Testing
@testable import VerifyHTTP

/// What this target is allowed to reach, checked by reading its own sources.
///
/// An absence cannot be tested any other way. Every claim here is one a
/// reviewer would otherwise have to re-establish by hand on every change: a
/// page that can reach a database is one edit from recording a member, and a
/// clock read below the listener is an expiry no suite can pin.
@Suite("The shape of the target")
struct TargetShapeTests {

    // MARK: - Properties

    /// The repository, found from this file so it means the same thing
    /// wherever the suite is run from.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Every source file in the target, with its name.
    static func sources() throws -> [(name: String, text: String)] {
        let directory = root.appendingPathComponent("Sources/VerifyHTTP")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        return try names.filter { $0.hasSuffix(".swift") }.map { name in
            (name, try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
        }
    }

    // MARK: - What it may reach

    @Test("Nothing here imports another target in this package")
    func noOtherTargetIsReached() throws {
        // `Verify` is the one, and `Crypto` and Foundation with it. Not
        // `Store`, so a page cannot record a member; not `Chain`, so
        // serving one cannot spend a chain request; not `Surface`, which
        // would reach all three through one import.
        let forbidden = [
            "import Store", "import StoreSQLite", "import Chain", "import Gating",
            "import Reserve", "import Games", "import Surface", "import SurfaceDiscord",
            "import Runtime", "import DiscordBM", "import Algorand"
        ]
        for file in try Self.sources() {
            for name in forbidden {
                #expect(!file.text.contains(name), "\(file.name) reaches \(name)")
            }
        }
    }

    @Test("The manifest says the same thing the imports do")
    func theManifestAgrees() throws {
        // Goes red when somebody adds a dependency to the target and the
        // argument above stops being true, which is the moment it stops
        // being checkable by reading one file.
        let manifest = try String(
            contentsOf: Self.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // The target's own declaration, not the product's, which names the
        // same target and lists no dependencies at all.
        let opening = "name: \"VerifyHTTP\",\n            dependencies: ["
        guard
            let start = manifest.range(of: opening),
            let end = manifest.range(
                of: "\n            ],",
                range: start.upperBound..<manifest.endIndex
            )
        else {
            Issue.record("the manifest does not declare a VerifyHTTP target with dependencies")
            return
        }
        let declared = String(manifest[start.upperBound..<end.lowerBound])
        #expect(declared.contains("\"Verify\""))
        #expect(declared.contains("package: \"swift-crypto\""))
        for other in ["Store", "Chain", "Gating", "Reserve", "Games", "Surface", "Runtime"] {
            #expect(!declared.contains("\"\(other)\""), "the target declares \(other)")
        }
        #expect(!declared.contains("DiscordBM"))
        #expect(!declared.contains("swift-algorand"))
    }

    // MARK: - What reads a clock

    @Test("Only the listener reads a clock, once, at the top")
    func oneClockRead() throws {
        // Every rule below it takes `now` as a parameter, which is what
        // lets a suite pin an expiry and a rate limit window rather than
        // sleeping and hoping.
        for file in try Self.sources() where file.name != "VerifyHTTPListener.swift" {
            #expect(!file.text.contains("Date()"), "\(file.name) reads a clock")
            #expect(!file.text.contains("Date.now"), "\(file.name) reads a clock")
        }
        let listener = try Self.sources().first { $0.name == "VerifyHTTPListener.swift" }
        let reads = listener?.text.components(separatedBy: "Date()").count ?? 0
        #expect(reads == 2, "the listener should read the clock exactly once")
    }

    // MARK: - The page

    @Test("The page is a raw literal, so nothing can be interpolated into it")
    func thePageCannotBeTemplated() throws {
        // The rendered HTML is the wrong place to check this: a page built
        // by interpolation would not contain the two characters, it would
        // contain the value. So the source is what is asserted. A raw
        // literal does not interpolate at all, which is the property, and
        // the member's name being written as a text node in the browser is
        // the reason there is nothing to escape here.
        let page = try Self.sources().first { $0.name == "VerifyPage.swift" }
        #expect(page?.text.contains("public static let html: String = #\"\"\"") == true)
        #expect(page?.text.contains("public static let stylesheet: String = #\"\"\"") == true)
        let script = try Self.sources().first { $0.name == "VerifyPageScript.swift" }
        #expect(script?.text.contains("public static let source: String = #\"\"\"") == true)
    }

    // MARK: - Type safety

    @Test("No force unwrap, no forced try and no forced cast")
    func nothingIsForced() throws {
        for file in try Self.sources() {
            #expect(!file.text.contains("try!"), "\(file.name) forces a try")
            #expect(!file.text.contains("as!"), "\(file.name) forces a cast")
            #expect(!file.text.contains("!)"), "\(file.name) force unwraps")
            #expect(!file.text.contains("!."), "\(file.name) force unwraps")
        }
    }

    @Test("Nothing here holds a lock")
    func nothingLocks() throws {
        // The blocking parts of the listener run on dispatch queues and
        // hand their result to a task, which is what makes the two shared
        // things here actors rather than something with a mutex in it.
        for file in try Self.sources() {
            #expect(!file.text.contains("NSLock"), "\(file.name) holds a lock")
            #expect(!file.text.contains("NSRecursiveLock"), "\(file.name) holds a lock")
            #expect(!file.text.contains("unchecked Sendable"), "\(file.name) opts out of checking")
        }
    }
}
