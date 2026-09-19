@preconcurrency import Foundation
import Testing

@testable import Surface

/// Where the chat client is allowed to be, and what is allowed to be said.
///
/// Both of these are greps, and both are gates rather than review comments.
/// A rule a reviewer has to remember is a rule that holds until the week
/// somebody is in a hurry.
@Suite("Target shape and neutrality")
struct TargetShapeTests {

    // MARK: - Where the repository is

    /// The package root, found from this file rather than from the working
    /// directory, so the suite passes wherever it is run from.
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Every Swift file under a directory.
    private static func swiftFiles(under path: String) -> [URL] {
        let directory = root.appendingPathComponent(path)
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - The chat client stops at one target

    @Test("Only the adapter imports the chat client (BUILD-2, TRUST-4)")
    func chatClientIsConfined() throws {
        // `Store` declares no chat client, so `import DiscordBM` there is a
        // missing module rather than a review comment. The adapter depends
        // on `Store` and SwiftPM refuses a cycle, so the direction cannot be
        // reversed later by somebody in a hurry.
        var offenders: [String] = []
        for file in Self.swiftFiles(under: "Sources") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            // The statement, not the words. A doc comment that explains why
            // the import is absent is the opposite of the leak this catches.
            let imports = contents.components(separatedBy: .newlines).contains {
                $0.trimmingCharacters(in: .whitespaces) == "import DiscordBM"
            }
            guard imports else { continue }
            if !file.path.contains("/Sources/SurfaceDiscord/") {
                offenders.append(file.path)
            }
        }
        #expect(offenders.isEmpty, "the chat client leaked into: \(offenders)")
    }

    @Test("No engine target is given the chat client in the manifest")
    func manifestKeepsTheEnginesClean() throws {
        let manifest = try String(
            contentsOf: Self.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // The product is named once, in the one target that may have it.
        let mentions = manifest.components(separatedBy: "package: \"DiscordBM\"").count - 1
        #expect(mentions == 1)
    }

    @Test("A snowflake type never appears below the adapter")
    func snowflakesStopAtTheBoundary() throws {
        // A member is a `String` everywhere below the chat boundary, which
        // is what lets the router, the handlers and the store be exercised
        // with no gateway at all.
        for file in Self.swiftFiles(under: "Sources/Surface") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for word in ["UserSnowflake", "RoleSnowflake", "GuildSnowflake", "ChannelSnowflake"] {
                #expect(
                    contents.contains(word) == false,
                    "\(word) appears in \(file.lastPathComponent)"
                )
            }
        }
    }

    // MARK: - Nothing from the project this came from

    @Test("Nothing a member can read names the project this was built for (ADOPT-1.c, ADOPT-6.a)")
    func nothingIsInherited() throws {
        // A name, a collection, a ticker, a threshold or a URL from somebody
        // else's community is the one thing an operator can never fix by
        // editing configuration, because they will not know it is there.
        let forbidden = [
            "corvid", "nevermore", "baby ?-?jay", "divroc", "rookery",
            "pera", "defly", "nodely"
        ]
        // Whole words. "operator" contains one of these, and a check that
        // fires on it is a check somebody switches off.
        let pattern = try NSRegularExpression(
            pattern: "\\b(" + forbidden.joined(separator: "|") + ")\\b",
            options: [.caseInsensitive]
        )
        var offenders: [String] = []
        for file in Self.swiftFiles(under: "Sources/Surface") + Self.swiftFiles(under: "Sources/SurfaceDiscord") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            if let match = pattern.firstMatch(in: contents, range: range),
               let found = Range(match.range, in: contents) {
                offenders.append("\(file.lastPathComponent): \(contents[found])")
            }
        }
        #expect(offenders.isEmpty, "inherited names: \(offenders)")
    }

    @Test("No literal account, asset id or chat id is written into the surface (ADOPT-7)")
    func noLiteralIdentifiers() throws {
        // An Algorand address is fifty-eight upper-case base32 characters and
        // a chat snowflake is seventeen to twenty digits. Neither belongs in
        // source: a copied one points somebody's bot at a stranger's asset.
        let address = try NSRegularExpression(pattern: "\"[A-Z2-7]{58}\"")
        let snowflake = try NSRegularExpression(pattern: "\"[0-9]{17,20}\"")
        var offenders: [String] = []
        for file in Self.swiftFiles(under: "Sources/Surface") + Self.swiftFiles(under: "Sources/SurfaceDiscord") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            if address.firstMatch(in: contents, range: range) != nil {
                offenders.append("\(file.lastPathComponent): an account")
            }
            if snowflake.firstMatch(in: contents, range: range) != nil {
                offenders.append("\(file.lastPathComponent): a chat id")
            }
        }
        #expect(offenders.isEmpty, "literals: \(offenders)")
    }

    @Test("The only host written into the surface is Discord's own")
    func noInheritedHosts() throws {
        var offenders: [String] = []
        for file in Self.swiftFiles(under: "Sources/Surface") + Self.swiftFiles(under: "Sources/SurfaceDiscord") {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for line in contents.components(separatedBy: .newlines) {
                guard line.contains("https://") || line.contains("http://") else { continue }
                let allowed = line.contains("discord.com")
                    || line.contains("example.test")
                    || line.contains("attachment://")
                if !allowed {
                    offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "hosts: \(offenders)")
    }

    // MARK: - The suite itself

    @Test("No test reads a secret from the machine it runs on (BUILD-2.a, BUILD-2.b)")
    func testsCannotReachAnythingLive() throws {
        // Configuration on a developer's machine must not be able to point
        // the suite at a real chain, a real server or a real account. The
        // test target does not depend on the adapter, so it cannot construct
        // an HTTP client at all; this checks the rest.
        for file in Self.swiftFiles(under: "Tests/SurfaceTests") {
            // Except the file doing the checking, which has to name the
            // things it is checking for.
            guard file.lastPathComponent != "TargetShapeTests.swift" else { continue }
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(contents.contains("ProcessInfo.processInfo.environment") == false)
            #expect(contents.contains("URLSession") == false)
            #expect(contents.contains("import SurfaceDiscord") == false)
        }
    }
}

/// A chat account id, checked, on its way to becoming a plain string.
@Suite("Identity")
struct DiscordUserIdTests {

    @Test("One to twenty digits, and nothing else")
    func shapeIsChecked() {
        #expect(DiscordUserId(externalId: "1") != nil)
        #expect(DiscordUserId(externalId: "12345678901234567890") != nil)
        #expect(DiscordUserId(externalId: "") == nil)
        #expect(DiscordUserId(externalId: "123456789012345678901") == nil)
        #expect(DiscordUserId(externalId: "12345678901234567a") == nil)
        #expect(DiscordUserId(externalId: " 123") == nil)
        #expect(DiscordUserId(externalId: "-1") == nil)
    }

    @Test("What travels below the boundary is the plain string")
    func externalIdIsAString() throws {
        let id = try #require(DiscordUserId(externalId: "100000000000000001"))
        #expect(id.externalId == "100000000000000001")
        #expect(id.mention == "<@100000000000000001>")
    }
}
