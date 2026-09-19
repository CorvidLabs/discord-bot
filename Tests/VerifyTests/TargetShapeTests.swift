import Foundation
import Testing
import Verify

/// Properties of the source itself, asserted by reading it.
///
/// Several of the things this module sells are **absences**, and an absence
/// has no behaviour to assert. This suite reads the target's own sources and
/// the manifest instead, which is the idiom the store targets already
/// established here, for the reason their own comment gives: a rule held by
/// attention alone is a rule that lasts until a busy afternoon.
///
/// It finds the repository from this file rather than from a working
/// directory, so it means the same thing wherever it is run from. Opening a
/// file is allowed and required; opening a socket is not, and there is
/// nothing here that does.
@Suite("The shape of the verifying target")
struct TargetShapeTests {

    // MARK: - Properties

    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url = url.deletingLastPathComponent() }
        return url
    }

    static var sources: String {
        repositoryRoot.appendingPathComponent("Sources/Verify").path
    }

    static var manifest: String {
        get throws {
            try String(
                contentsOfFile: repositoryRoot.appendingPathComponent("Package.swift").path,
                encoding: .utf8
            )
        }
    }

    static func swiftFiles() throws -> [(path: String, text: String)] {
        let manager = FileManager.default
        let names = try manager.contentsOfDirectory(atPath: sources)
        return try names
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { name in
                let path = sources + "/" + name
                return (path, try String(contentsOfFile: path, encoding: .utf8))
            }
    }

    /// Every public function and initialiser declaration in the target, each
    /// joined back into one line so a signature split over several lines is
    /// still one thing to look at.
    static func publicDeclarations() throws -> [String] {
        var declarations: [String] = []
        for file in try swiftFiles() {
            var current: String?
            for line in file.text.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = String(line).trimmingCharacters(in: .whitespaces)
                if current == nil {
                    guard text.hasPrefix("public func ") || text.hasPrefix("public init") ||
                        text.hasPrefix("public static func ") else { continue }
                    current = text
                } else {
                    current = (current ?? "") + " " + text
                }
                if let signature = current, signature.contains("{") || signature.hasSuffix("}") {
                    declarations.append(signature)
                    current = nil
                }
            }
            if let signature = current { declarations.append(signature) }
        }
        return declarations
    }

    // MARK: - The dependency list

    @Test("The target depends on the address parser and a cryptography library, and on nothing else")
    func theDependencyListIsExact() throws {
        // Goes red against somebody adding the store for convenience, after
        // which the checker can reach a database and the claim that it sits
        // at the bottom of the graph is gone.
        let text = try Self.manifest
        guard let start = text.range(of: "name: \"Verify\",\n            dependencies:"),
            let end = text.range(of: "testTarget(\n            name: \"VerifyTests\"") else {
            Issue.record("the manifest no longer declares the target the way this case reads it")
            return
        }
        let declaration = String(text[start.lowerBound..<end.lowerBound])
        #expect(declaration.contains("\"Algorand\", package: \"swift-algorand\""))
        #expect(declaration.contains("\"Crypto\", package: \"swift-crypto\""))
        for other in ["Store", "Chain", "Gating", "Reserve", "StoreSQLite", "CSQLite"] {
            #expect(!declaration.contains("\"\(other)\""), "the target declares \(other)")
        }
    }

    @Test("No file imports another target in this package")
    func nothingImportsTheRestOfThePackage() throws {
        for file in try Self.swiftFiles() {
            for other in ["Store", "Chain", "Gating", "Reserve", "StoreSQLite", "StoreTestKit"] {
                #expect(!file.text.contains("import \(other)"), "\(file.path)")
            }
        }
    }

    // MARK: - Absences

    @Test("The target names no chat client and no chat identifier type")
    func noChatTypeAnywhere() throws {
        // Goes red against a subject typed as anything but an opaque
        // string, which is how an identifier that came from a person gets
        // below the boundary this package draws.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("DiscordBM"), "\(file.path)")
            #expect(!file.text.contains("Snowflake"), "\(file.path)")
            #expect(!file.text.lowercased().contains("guild"), "\(file.path)")
        }
    }

    @Test("The target declares no private key type, no mnemonic and no signing call")
    func nothingHereCanSign() throws {
        // Goes red against a helper that signs "just for the tests", which
        // is a key living in the one target whose whole claim is that it
        // holds none.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("PrivateKey"), "\(file.path)")
            #expect(!file.text.contains("Mnemonic"), "\(file.path)")
            #expect(!file.text.contains("TransactionSigner"), "\(file.path)")
            #expect(!file.text.contains(".sign("), "\(file.path)")
            #expect(!file.text.contains("bytesToSign"), "\(file.path)")
        }
    }

    @Test("The target constructs no node client and calls nothing that submits")
    func nothingHereCanReachAChain() throws {
        // The one import away from a client is a position the chain reader
        // is also in, and it is only ever answered by checking rather than
        // by promising.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("AlgodClient"), "\(file.path)")
            #expect(!file.text.contains("IndexerClient"), "\(file.path)")
            #expect(!file.text.contains("URLSession"), "\(file.path)")
            #expect(!file.text.contains("URLRequest"), "\(file.path)")
            #expect(!file.text.contains("http"), "\(file.path)")
            #expect(!file.text.contains("submitTransaction"), "\(file.path)")
        }
    }

    @Test("The target reads nothing from outside the process")
    func nothingHereReadsASetting() throws {
        // Goes red against the first flag anybody adds, on the day they add
        // it, rather than in an audit a year later.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("ProcessInfo"), "\(file.path)")
            #expect(!file.text.contains("getenv"), "\(file.path)")
            #expect(!file.text.contains("CommandLine"), "\(file.path)")
            #expect(!file.text.contains("#if DEBUG"), "\(file.path)")
            #expect(!file.text.contains("Bundle"), "\(file.path)")
        }
    }

    @Test("The target reads no clock")
    func nothingHereReadsAClock() throws {
        // Every instant is a parameter, which is what pins every reading in
        // this suite to the test rather than to when it ran.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("Date()"), "\(file.path)")
            #expect(!file.text.contains("ContinuousClock"), "\(file.path)")
            #expect(!file.text.contains("DispatchTime"), "\(file.path)")
            #expect(!file.text.contains("timeIntervalSinceNow"), "\(file.path)")
        }
    }

    @Test("The target logs nothing")
    func nothingHereWritesALine() throws {
        // Goes red against a debug line printing a blob or a challenge,
        // which is a replayable value written to wherever logs go.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("print("), "\(file.path)")
            #expect(!file.text.contains("debugPrint"), "\(file.path)")
            #expect(!file.text.contains("Logger"), "\(file.path)")
            #expect(!file.text.contains("os_log"), "\(file.path)")
            #expect(!file.text.contains("NSLog"), "\(file.path)")
            #expect(!file.text.contains("FileHandle"), "\(file.path)")
        }
    }

    @Test("No path re-encodes parsed fields and checks a signature over the result")
    func nothingRebuildsWhatWasSigned() throws {
        // Goes red against the mistake nobody finds quickly: a re-encoding
        // one byte different from what the wallet signed fails a perfectly
        // good proof and looks like a problem with the cryptography.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("encode("), "\(file.path)")
            #expect(!file.text.contains("Codable"), "\(file.path)")
        }
    }

    @Test("The target performs no account lookup and holds nothing that could")
    func nothingHereCanLookAnAccountUp() throws {
        // Doing the authorising key retry inside the module would make it
        // untestable offline and would spend a chain request on every bad
        // signature, which is RUN-11.
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("DataSource"), "\(file.path)")
            #expect(!file.text.contains("authorizingAddress"), "\(file.path)")
        }
    }

    @Test("A public key is built in exactly one place")
    func thereIsOneSignatureCheck() throws {
        // The keys a signature is ever checked against can therefore be
        // counted: the claimed address, and the key the caller vouched for.
        // Goes red against surfacing a signer read out of the blob and
        // wiring it in "for completeness", which is one convenience away
        // from the blob naming the key that validates it.
        var occurrences = 0
        for file in try Self.swiftFiles() {
            occurrences += file.text.components(separatedBy: "PublicKey(rawRepresentation:").count - 1
        }
        #expect(occurrences == 1)
    }

    @Test("Nothing read out of a blob has anywhere to be surfaced")
    func theReaderHasNoSignerField() throws {
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("public let signer"), "\(file.path)")
            #expect(!file.text.contains("var signer"), "\(file.path)")
        }
    }

    @Test("No file uses a force unwrap, a forced try or a forced cast")
    func nothingIsForced() throws {
        for file in try Self.swiftFiles() {
            #expect(!file.text.contains("try!"), "\(file.path)")
            #expect(!file.text.contains(" as! "), "\(file.path)")
        }
    }

    // MARK: - The public surface

    @Test("No public interface yields a proved account without taking a blob and a session")
    func nothingMintsAnUncheckedProof() throws {
        // This is the case a check on the initialiser alone would miss. A
        // public factory beside a non-public initialiser satisfies "the
        // initialiser is not public" and defeats the property it was
        // standing for, and it compiles perfectly well.
        for declaration in try Self.publicDeclarations() {
            // The **return** type, not a parameter: a call that takes a
            // proved account and hands back something else is not a way to
            // get one.
            guard declaration.contains("-> ProvedAccount")
                || declaration.contains("-> VerificationOutcome") else { continue }
            #expect(declaration.contains("blob"), "\(declaration)")
            #expect(declaration.contains("sessionId"), "\(declaration)")
        }
    }

    @Test("A proved account has no public initialiser and an asserted account does")
    func theTwoProducersAreDistinguishable() throws {
        // Goes red against one type for both, after which a reviewer
        // reading a host cannot see which values were checked here and
        // which were somebody else's word.
        let files = try Self.swiftFiles()
        guard let proved = files.first(where: { $0.path.hasSuffix("ProvedAccount.swift") }),
            let asserted = files.first(where: { $0.path.hasSuffix("AssertedAccount.swift") }) else {
            Issue.record("the two account types are no longer in the files this case reads")
            return
        }
        #expect(!proved.text.contains("public init("), "ProvedAccount.swift")
        #expect(proved.text.contains("internal init("), "ProvedAccount.swift")
        #expect(asserted.text.contains("public init("), "AssertedAccount.swift")
    }

    @Test("Every type the module exports is Sendable")
    func everythingCrossesAConcurrencyBoundary() throws {
        // The coordinator is an actor and a store is a protocol a host
        // conforms to, so every value that reaches either has to be able to
        // cross. Read rather than compiled because a missing conformance on
        // a type nothing has yet passed across is a compile error that has
        // not happened yet.
        for file in try Self.swiftFiles() {
            for line in file.text.split(separator: "\n") {
                let text = String(line)
                guard text.hasPrefix("public struct ") || text.hasPrefix("public enum ")
                    || text.hasPrefix("public protocol ") else { continue }
                #expect(text.contains("Sendable"), "\(file.path): \(text)")
            }
        }
    }
}
