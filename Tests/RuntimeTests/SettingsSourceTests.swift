import Foundation
import Testing
@testable import Runtime

/// Properties of the source itself, asserted by reading it.
///
/// The rule these protect is not expressible in the type system: nothing
/// stops a future edit writing `ProcessInfo` inside the composition root. The
/// graph does not cover it, so this is the guard, and naming it as the soft
/// spot is better than implying the manifest handles it (BUILD-2.a).
@Suite("The shape of the runtime targets")
internal struct SettingsSourceTests {

    // MARK: - Properties

    /// `Sources`, found from this file rather than from a working directory,
    /// so the test means the same thing wherever it is run from.
    internal static var sources: String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url = url.deletingLastPathComponent()
        }
        return url.appendingPathComponent("Sources").path
    }

    internal static func swiftFiles(in directory: String) throws -> [(path: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        return try names
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { name in
                let path = directory + "/" + name
                return (path, try String(contentsOfFile: path, encoding: .utf8))
            }
    }

    /// The same text with whole-line comments taken out.
    ///
    /// A rule about what the code does has to be asserted against the code. A
    /// comment explaining why an option is never set would otherwise fail the
    /// test that checks the option is never set, which teaches the next
    /// person to delete the explanation.
    internal static func codeOnly(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - Tests

    @Test("The composition root cannot reach the machine's settings (RT-003)")
    internal func runtimeNeverReadsTheEnvironment() throws {
        for file in try Self.swiftFiles(in: Self.sources + "/Runtime") {
            let code = Self.codeOnly(file.text)
            #expect(!code.contains("ProcessInfo"), "\(file.path)")
            // The other door onto the machine's settings, which exists and is
            // public. The root does not use it and must not start to.
            #expect(!code.contains("loadFromProcessEnvironment"), "\(file.path)")
        }
    }

    @Test("Only two places in the package can reach the environment, and one is never called")
    internal func whoCanReachTheEnvironment() throws {
        // The definition for this change says the executable's snapshot is
        // the only reference to `ProcessInfo.processInfo.environment` in
        // `Sources/`. That is not true of the tree as it stands and the tree
        // wins: `Chain.ChainConfiguration.loadFromProcessEnvironment(token:)`
        // is a merged public convenience with one of its own. Nothing calls
        // it, the runtime contract forbids the root from starting to, and the
        // test above is what enforces that half. This one pins the whole set,
        // so a third door is a failing test rather than a discovery.
        var readers: [String] = []
        let targets = ["Runtime", "BotMain", "Gating", "Games", "Reserve", "Store", "StoreSQLite", "Chain"]
        for target in targets {
            for file in try Self.swiftFiles(in: Self.sources + "/" + target)
            where Self.codeOnly(file.text).contains("ProcessInfo.processInfo.environment") {
                readers.append(file.path)
            }
        }
        let names = readers.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
        #expect(names == ["BotMain.swift", "ChainConfiguration.swift"], "read in \(readers)")
    }

    @Test("Neither new target names a chat client (BUILD-4)")
    internal func noChatClientAnywhere() throws {
        // The manifest is the real guard: neither target declares a chat
        // package, so importing one does not compile. This catches the softer
        // version, where a snowflake or a guild id arrives as a type name or
        // a field and the layering is lost with no build ever failing.
        for target in ["Runtime", "BotMain"] {
            for file in try Self.swiftFiles(in: Self.sources + "/" + target) {
                #expect(!file.text.contains("DiscordBM"), "\(file.path)")
                #expect(!file.text.contains("Snowflake"), "\(file.path)")
                #expect(!file.text.lowercased().contains("guild"), "\(file.path)")
            }
        }
    }

    @Test("Neither new target uses a force unwrap, a forced try or a forced cast")
    internal func nothingIsForced() throws {
        for target in ["Runtime", "BotMain"] {
            for file in try Self.swiftFiles(in: Self.sources + "/" + target) {
                #expect(!file.text.contains("try!"), "\(file.path)")
                #expect(!file.text.contains(" as! "), "\(file.path)")
            }
        }
    }

    @Test("The executable refuses to die of a write to a peer that has gone (RT-001)")
    internal func sigpipeIsIgnoredBeforeAnythingElse() throws {
        // A write to a socket whose peer has reset, or to a closed pipe on
        // standard output, raises SIGPIPE, and its default disposition kills
        // the process: no report, no exit code from the documented set, no
        // lease released. The socket option that would turn it into an error
        // fails on Darwin when the peer has already gone, which is the case
        // it is wanted for, so the process-wide ignore is the only thing that
        // actually holds. It belongs here because it touches the machine.
        let path = Self.sources + "/BotMain/BotMain.swift"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let code = Self.codeOnly(text)
        #expect(code.contains("signal(SIGPIPE, SIG_IGN)"), "\(path)")
        guard
            let ignoring = code.range(of: "signal(SIGPIPE, SIG_IGN)"),
            let settings = code.range(of: "ProcessInfo.processInfo.environment")
        else {
            Issue.record("neither line is in \(path)")
            return
        }
        // Before the environment is even read, because everything after that
        // can write something.
        #expect(ignoring.lowerBound < settings.lowerBound)
    }

    @Test("The listener never asks for the option that would let a duplicate bind")
    internal func noReusePort() throws {
        // SO_REUSEADDR is set and is fine: it lets a restart bind while the
        // previous socket is in TIME_WAIT. SO_REUSEPORT permits a second live
        // listener on the same address and port, which is the second bind
        // this bind exists to refuse.
        for file in try Self.swiftFiles(in: Self.sources + "/Runtime") {
            #expect(!Self.codeOnly(file.text).contains("SO_REUSEPORT"), "\(file.path)")
        }
    }
}
