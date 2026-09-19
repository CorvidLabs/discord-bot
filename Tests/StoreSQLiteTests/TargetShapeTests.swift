import Foundation
import Store
import StoreSQLite
import Testing

/// Properties of the source itself, asserted by reading it.
///
/// Three of the rules this layer keeps are not expressible in the type system,
/// so they are asserted here rather than left to a reviewer's attention. A rule
/// held by attention alone is a rule that lasts until a busy afternoon.
@Suite("The shape of the store targets")
struct TargetShapeTests {

    // MARK: - Properties

    /// The repository, found from this file rather than from a working
    /// directory, so the test means the same thing wherever it is run from.
    static var sources: String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url = url.deletingLastPathComponent() }
        return url.appendingPathComponent("Sources").path
    }

    static func swiftFiles(in directory: String) throws -> [(path: String, text: String)] {
        let manager = FileManager.default
        let names = try manager.contentsOfDirectory(atPath: directory)
        return try names
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { name in
                let path = directory + "/" + name
                return (path, try String(contentsOfFile: path, encoding: .utf8))
            }
    }

    // MARK: - Tests

    @Test("Neither store target names a chat client")
    func noChatClientAnywhere() throws {
        // The manifest is the real guard: neither target declares a chat
        // package, so importing one does not compile. This catches the softer
        // version, where a snowflake or a guild id arrives as a comment, a
        // type name or a field, and the layering is lost without a build ever
        // failing.
        for target in ["Store", "StoreTestKit", "StoreSQLite"] {
            for file in try Self.swiftFiles(in: Self.sources + "/" + target) {
                #expect(!file.text.contains("DiscordBM"), "\(file.path)")
                #expect(!file.text.contains("Snowflake"), "\(file.path)")
                #expect(!file.text.lowercased().contains("guild"), "\(file.path)")
            }
        }
    }

    @Test("No statement in the SQLite target is built out of a string")
    func noStatementIsBuiltFromAString() throws {
        // `SQL` takes a `StaticString` and has no initialiser from a `String`,
        // so an interpolated statement does not compile. What a reader cannot
        // see from the type is whether somebody reached around it, so the
        // escape hatches are named here and asserted absent.
        for file in try Self.swiftFiles(in: Self.sources + "/StoreSQLite") {
            #expect(!file.text.contains("sqlite3_exec"), "\(file.path)")
            #expect(!file.text.contains("stringLiteral: String"), "\(file.path)")
            #expect(!file.text.contains("unsafeText"), "\(file.path)")
        }
    }

    @Test("Nothing in the SQLite target can put an amount in a signed integer column")
    func noAmountReachesASignedColumn() throws {
        // An amount is eight bytes in a blob, with a CHECK on the column. The
        // reason is a measured one: the payout engine saturates to the largest
        // unsigned value on purpose, and half of that range does not fit in the
        // signed integer SQLite actually stores.
        for file in try Self.swiftFiles(in: Self.sources + "/StoreSQLite") {
            let mentionsAmountColumn = file.text.contains("base_units")
                || file.text.contains("used_requests")
                || file.text.contains("completed_epochs")
            guard mentionsAmountColumn else { continue }
            #expect(
                !file.text.contains("base_units INTEGER"),
                "an amount column was declared as a signed integer in \(file.path)"
            )
        }
    }

    @Test("No file in either target uses a force unwrap, a forced try or a forced cast")
    func nothingIsForced() throws {
        for target in ["Store", "StoreTestKit", "StoreSQLite"] {
            for file in try Self.swiftFiles(in: Self.sources + "/" + target) {
                #expect(!file.text.contains("try!"), "\(file.path)")
                #expect(!file.text.contains(" as! "), "\(file.path)")
            }
        }
    }
}
