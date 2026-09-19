import Foundation
import Testing
@testable import Runtime

/// The graph, asserted from the manifest rather than from a diagram.
///
/// "No target can see a chat client" survives an executable that one day must
/// only if three of the four things holding it up are the compiler's job
/// rather than a reviewer's. This suite reads the manifest and checks the
/// fourth (RT-001, BUILD-4, TRUST-1.b).
@Suite("The package graph")
internal struct RuntimeCompositionTests {

    // MARK: - Properties

    private static var manifest: String {
        get throws {
            var url = URL(fileURLWithPath: #filePath)
            for _ in 0..<3 {
                url = url.deletingLastPathComponent()
            }
            return try String(
                contentsOf: url.appendingPathComponent("Package.swift"),
                encoding: .utf8
            )
        }
    }

    /// One target's declaration, from its name to the end of its
    /// `swiftSettings` line.
    private static func declaration(of target: String) throws -> String {
        let text = try manifest
        guard let start = text.range(of: "name: \"\(target)\"") else {
            Issue.record("\(target) is not in the manifest")
            return ""
        }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: "swiftSettings:") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    // MARK: - Tests

    @Test("Runtime depends on Gating, Chain and Store, and on nothing else (RT-001)")
    internal func runtimeDependencies() throws {
        let declared = try Self.declaration(of: "Runtime")
        #expect(declared.contains("\"Gating\""))
        #expect(declared.contains("\"Chain\""))
        #expect(declared.contains("\"Store\""))
        // Not `Games` and not `Reserve`: neither is reachable without a
        // surface to play on or a payer to pay with. Not `StoreSQLite`,
        // because this target takes `any BotStore` and links no database.
        #expect(!declared.contains("\"Games\""))
        #expect(!declared.contains("\"Reserve\""))
        #expect(!declared.contains("\"StoreSQLite\""))
    }

    @Test("BotMain depends on Runtime and StoreSQLite, and on nothing else")
    internal func executableDependencies() throws {
        let declared = try Self.declaration(of: "BotMain")
        #expect(declared.contains("\"Runtime\""))
        #expect(declared.contains("\"StoreSQLite\""))
        #expect(!declared.contains("\"Gating\""))
        #expect(!declared.contains("\"Chain\""))
        #expect(!declared.contains("\"Games\""))
    }

    @Test("Every package dependency is one somebody named on purpose (TRUST-1.b)")
    internal func packageDependenciesAreNamed() throws {
        let text = try Self.manifest
        // Named rather than counted. A count fails when a dependency is added
        // and says nothing about which one, and the first person to see it red
        // fixes the number. The point of TRUST-1.b is that a new thing to
        // reach is a diff somebody reads, so this list is the diff: adding a
        // package means adding it here and in `docs/WHAT-IT-TALKS-TO.md`, and
        // a reviewer sees both.
        let expected: Set<String> = ["swift-algorand", "swift-crypto", "DiscordBM"]
        let declared = Set(
            text.components(separatedBy: ".package(url:")
                .dropFirst()
                .compactMap { chunk -> String? in
                    guard
                        let open = chunk.firstIndex(of: "\""),
                        let close = chunk[chunk.index(after: open)...].firstIndex(of: "\"")
                    else { return nil }
                    let url = String(chunk[chunk.index(after: open)..<close])
                    return url.split(separator: "/").last.map {
                        String($0).replacingOccurrences(of: ".git", with: "")
                    }
                }
        )
        #expect(declared == expected, "the manifest declares \(declared.sorted())")
    }

    @Test("There is exactly one executable product, so bare `swift run` is unambiguous")
    internal func oneExecutableProduct() throws {
        let text = try Self.manifest
        let executables = text.components(separatedBy: ".executable(name:").count - 1
        #expect(executables == 1)
        #expect(text.contains(".executable(name: \"bot\", targets: [\"BotMain\"])"))
    }

    @Test("Runtime is a target and not a product, because its shape is still moving")
    internal func runtimeIsNotAProduct() throws {
        let text = try Self.manifest
        #expect(!text.contains(".library(name: \"Runtime\""))
    }

    @Test("Both new targets have strict concurrency on, like every other target")
    internal func strictConcurrencyEverywhere() throws {
        let text = try Self.manifest
        let targets = text.components(separatedBy: "name: \"").count - 1
        let strict = text.components(separatedBy: "enableExperimentalFeature(\"StrictConcurrency\")")
            .count - 1
        // One per target and test target, and none missing.
        #expect(strict > 0)
        #expect(targets > strict, "every name should belong to a target or a product")
    }

    @Test("Both new source directories are registered with the contract gate")
    internal func registeredWithTheGate() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url = url.deletingLastPathComponent()
        }
        let configuration = try String(
            contentsOf: url.appendingPathComponent(".specsync/config.toml"),
            encoding: .utf8
        )
        // The gate reads this list. A target that is not in it passes a check
        // that still reports full coverage, which is how an undescribed
        // target ships.
        #expect(configuration.contains("\"Sources/Runtime\""))
        #expect(configuration.contains("\"Sources/BotMain\""))
    }
}
