@preconcurrency import Foundation
import Runtime
import Surface
import Testing

@testable import SurfaceDiscord

/// The whole assembled program, read as source.
///
/// The type system already makes one ordering impossible: connecting needs a
/// ``Runtime/ListenerBound`` and only a completed bind makes one. That
/// argument holds for the door it guards. What it cannot see is a **second**
/// door: another type in the package that identifies without going through
/// the seam at all, and an executable that reaches for it. Both of those are
/// questions about the shape of the program rather than about any one value,
/// so they are asked of the source (`RUN-7`, `RUN-7.a`).
@Suite("The assembled program cannot identify first")
struct AssembledProgramTests {

    // MARK: - Where the repository is

    /// The package root, found from this file rather than from the working
    /// directory, so the suite passes wherever it is run from.
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Every Swift file under a directory, with its contents.
    private static func sources(under path: String) throws -> [(name: String, text: String)] {
        let directory = root.appendingPathComponent(path)
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return try walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// The file with lines that are only a comment taken out, so a sentence
    /// naming a thing is not mistaken for a use of it.
    private static func code(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - One door

    @Test("Only one type conforms to the chat seam in a way that can reach anybody")
    func oneConformance() throws {
        var conforming: [String] = []
        for file in try Self.sources(under: "Sources") where Self.code(file.text).contains(": ChatGateway") {
            conforming.append(file.name)
        }
        // The second is in the executable, and it cannot reach anybody: it
        // carries the real surface's settings entries so a dry run whose
        // settings were refused still lists them, and every other verb on it
        // throws. What keeps that true is the next test, which refuses the
        // executable any way of identifying at all.
        #expect(
            conforming.sorted() == ["ChatSurface.swift", "DiscordChatGateway.swift"],
            "conformances in \(conforming)"
        )
    }

    @Test("The executable reaches the chat service through that one type and nothing else")
    func theExecutableHasOneDoor() throws {
        // Everything below is a way to make something identify. The
        // executable may name the seam's one conformance and may not name
        // any of the others, because an executable holding a gateway manager
        // of its own is an executable that can connect whenever it likes.
        let otherDoors = ["DiscordSurface", "BotGatewayManager", "DiscordGatewayConnection"]
        var found: [String] = []
        var doors = 0
        for file in try Self.sources(under: "Sources/BotMain") {
            let text = Self.code(file.text)
            for door in otherDoors where text.contains(door) {
                found.append("\(file.name): \(door)")
            }
            if text.contains("DiscordChatGateway") { doors += 1 }
        }
        #expect(found.isEmpty, "the executable can reach: \(found)")
        #expect(doors == 1, "the executable names the one door \(doors) time(s)")
    }

    @Test("Identifying happens in one place in the adapter, and it is behind the proof")
    func identifyingIsBehindTheProof() throws {
        let gateway = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordChatGateway.swift" }
        )
        let text = Self.code(gateway.text)

        // One call, and it is after the signature that demands the bind.
        #expect(text.components(separatedBy: "identify()").count - 1 == 1)
        let connect = try #require(text.range(of: "func connect("))
        #expect(text.contains("afterBinding listener: ListenerBound"))
        let identify = try #require(text.range(of: "identify()"))
        #expect(connect.lowerBound < identify.lowerBound)
    }

    @Test("The identify is the last thing connect does, after the registration and the reader")
    func theIdentifyFollowsTheRegistrationInSource() throws {
        let gateway = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordChatGateway.swift" }
        )
        let text = Self.code(gateway.text)
        let register = try #require(text.range(of: "registrar.register("))
        let read = try #require(text.range(of: "session.deliver("))
        let identify = try #require(text.range(of: "session.identify()"))
        // `ChatGatewayTests` watches all three happen in this order against
        // doubles. This asks the weaker question the doubles cannot: that
        // there is no second arrangement of the same three statements
        // further down the file.
        #expect(register.lowerBound < read.lowerBound)
        #expect(read.lowerBound < identify.lowerBound)
    }

    @Test("A privileged intent is asked for only when an event is translated out of it")
    func noPrivilegedIntentWithoutAConsumer() throws {
        // `guildMembers` is privileged and off by default on a new
        // application, and Discord answers a request for a disallowed intent
        // by closing the websocket with 4014, which the client will not
        // retry. The REST registration is unaffected, so the boot passes and
        // the process then answers nothing for ever. Asking for it while
        // nothing reads a member event buys that failure and no feature.
        let gateway = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordChatGateway.swift" }
        )
        let boot = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordBoot.swift" }
        )
        let asksFor = Self.code(gateway.text).contains(".guildMembers")
        let translates = Self.code(boot.text).contains("guildMemberRemove")
        #expect(asksFor == translates, "asked for: \(asksFor), translated: \(translates)")
    }

    @Test("The application id the loader worked out is the one the client is given")
    func theApplicationIdIsHandedOver() throws {
        // The client's own extraction from the token tries two segment
        // lengths and answers nil for the rest, and what it answers differs
        // between macOS and Linux. A nil app id makes the registration throw
        // before it makes a request, and setting `DISCORD_APPLICATION_ID`
        // would not help if the value were then dropped.
        let gateway = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordChatGateway.swift" }
        )
        #expect(Self.code(gateway.text).contains("appId: chat.applicationId"))
    }

    @Test("Every role write in this target is read back afterwards (SEE-4)")
    func everyRoleWriteIsReadBack() throws {
        // Discord answers `200` to a member update and silently drops any
        // role id it does not recognise. One wrong digit then costs every
        // member that role for ever, the same list is re-sent on every
        // sweep because the member still lacks it, and nothing anywhere
        // says why. There is no double for the chat client in this suite,
        // so the question is asked of the source: a file that writes roles
        // is a file that checks what landed.
        for file in try Self.sources(under: "Sources/SurfaceDiscord") {
            let text = Self.code(file.text)
            guard text.contains("updateGuildMember(") else { continue }
            #expect(text.contains("RoleWriteCheck."), "\(file.name) writes roles and never reads back")
        }
    }

    @Test("The executable reads its arguments before it builds anything")
    func theVerbIsKnownBeforeTheSurfaceIsBuilt() throws {
        // `bot help` is the one command that has to work on a machine where
        // nothing is configured, and `bot check` exists to say what is wrong
        // with the settings. Building the surface first made a chat
        // misconfiguration refuse every verb the binary has, and the refusal
        // then names `bot check` as the thing to run (RT-026, RUN-9).
        let main = try #require(
            try Self.sources(under: "Sources/BotMain").first { $0.name == "BotMain.swift" }
        )
        let text = Self.code(main.text)
        let parse = try #require(text.range(of: "RuntimeCommand.parse(arguments)"))
        let build = try #require(text.range(of: "ChatSurface.gateway("))
        #expect(parse.lowerBound < build.lowerBound)
        #expect(text.contains("needsChatSurface"))
    }

    @Test("Every event the adapter can hand up is one it actually produces")
    func everyChatEventIsProduced() throws {
        // The translator switches over the chat library's own enum and has
        // to keep a `default`, or this stops building the next time that
        // library learns an event. So the compiler cannot ask this question
        // and the suite does: `ChatEvent` is small and one function makes
        // it, so every case declared must be a case that function returns.
        // One that nothing returns is a case nothing ever sends, which
        // reads to the next person like a feature.
        let seams = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "ChatGatewaySeams.swift" }
        )
        let body = try #require(seams.text.components(separatedBy: "public enum ChatEvent").last)
        let declared = body
            .components(separatedBy: "\n}")
            .first?
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case ") else { return nil }
                return String(trimmed.dropFirst(5).prefix { $0.isLetter })
            } ?? []
        #expect(declared.count >= 3, "cases found: \(declared)")

        let boot = try #require(
            try Self.sources(under: "Sources/SurfaceDiscord")
                .first { $0.name == "DiscordBoot.swift" }
        )
        let translator = Self.code(boot.text)
        for name in declared {
            #expect(translator.contains("return .\(name)"), "nothing produces .\(name)")
        }
    }

    // MARK: - The direction that keeps the guarantee

    @Test("The composition root does not depend back on the surface, so the cycle cannot close")
    func theRootNeverLooksDown() throws {
        // SwiftPM is the real guard: a cycle does not build. This catches
        // the first line of the attempt, which is the one a person writes
        // before finding out.
        for file in try Self.sources(under: "Sources/Runtime") {
            let text = Self.code(file.text)
            #expect(!text.contains("import Surface"), "\(file.name)")
            #expect(!text.contains("import SurfaceDiscord"), "\(file.name)")
            #expect(!text.contains("import DiscordBM"), "\(file.name)")
        }
    }

    @Test("Registration takes the validator's own answer, so it cannot run before one (ADOPT-2)")
    func registrationTakesTheProof() throws {
        for file in try Self.sources(under: "Sources") {
            let text = Self.code(file.text)
            guard text.contains("func register(") else { continue }
            // Every declaration of it, in the protocol and in the live one,
            // takes the proof rather than an array of definitions.
            #expect(
                text.contains("func register(_ catalog: ValidatedCatalog, guildId: String)"),
                "\(file.name)"
            )
        }
        // And the proof has exactly one maker, inside `Surface`.
        var makers: [String] = []
        for file in try Self.sources(under: "Sources") {
            guard Self.code(file.text).contains("ValidatedCatalog(catalog:") else { continue }
            makers.append(file.name)
        }
        #expect(makers == ["CommandValidator.swift"], "made in \(makers)")
    }
}

/// What the chat surface reads, and how it refuses.
@Suite("The chat surface's own settings")
struct ChatSurfaceSettingsTests {

    @Test("Nothing set at all means no chat surface, and that is a whole answer")
    func nothingSetIsNoSurface() throws {
        #expect(try ChatSurfaceSettings.load([:]) == nil)
        #expect(try ChatSurfaceSettings.load(["STORE_PATH": "/tmp/x"]) == nil)
    }

    @Test("Naming your bot is not asking for a chat surface")
    func theBotNameIsNotASwitch() throws {
        // `BOT_NAME` is worth setting on a build that never talks to
        // anybody, so setting it alone must not refuse a boot for want of a
        // token it was never asking for.
        #expect(try ChatSurfaceSettings.load([SurfaceConfiguration.botNameKey: "Corax"]) == nil)
        #expect(!ChatSurfaceSettings.switchKeys.contains(SurfaceConfiguration.botNameKey))
    }

    @Test("Any one of the other chat variables is asking for one, and says what is missing")
    func anyChatVariableIsASwitch() throws {
        for key in ChatSurfaceSettings.switchKeys where key != SurfaceConfiguration.tokenKey {
            let failure = try #require(
                throws: BootFailure.self,
                performing: { try ChatSurfaceSettings.load([key: "4242"]) }
            )
            #expect(failure.variable == SurfaceConfiguration.tokenKey, "\(key)")
        }
    }

    @Test("A blank value is unset, which is what every loader in the package says")
    func blankIsUnset() throws {
        // A compose file writing `DISCORD_BOT_TOKEN: ${DISCORD_BOT_TOKEN}`
        // with nothing in the variable puts an empty one in the environment.
        #expect(try ChatSurfaceSettings.load([SurfaceConfiguration.tokenKey: "   "]) == nil)
    }

    @Test("Half a chat surface refuses by name rather than starting silently")
    func halfConfiguredRefuses() throws {
        let failure = try #require(
            throws: BootFailure.self,
            performing: { try ChatSurfaceSettings.load([SurfaceConfiguration.guildKey: "4242"]) }
        )
        #expect(failure.variable == SurfaceConfiguration.tokenKey)
        #expect(failure.code == .configuration)
    }

    @Test("A token with no server refuses, naming the server")
    func tokenWithoutServerRefuses() throws {
        let failure = try #require(
            throws: BootFailure.self,
            performing: { try ChatSurfaceSettings.load([SurfaceConfiguration.tokenKey: "a-token"]) }
        )
        #expect(failure.variable == SurfaceConfiguration.guildKey)
    }

    @Test("A server id that is not an id refuses, and says what one looks like")
    func aBadServerIdRefuses() throws {
        let failure = try #require(
            throws: BootFailure.self,
            performing: {
                try ChatSurfaceSettings.load([
                    SurfaceConfiguration.tokenKey: "a-token",
                    SurfaceConfiguration.guildKey: "not-an-id"
                ])
            }
        )
        #expect(failure.variable == SurfaceConfiguration.guildKey)
        #expect(failure.remedy?.contains("one to twenty digits") == true)
    }

    @Test("A value still holding an example placeholder refuses, naming the variable")
    func aPlaceholderRefuses() throws {
        // Somebody copied the example file and started before filling it in.
        // Without this the bot is built, identifies with junk and shows the
        // operator "the chat service refused the connection" rather than the
        // one sentence naming the variable to change (ADOPT-2, RUN-9.a).
        let failure = try #require(
            throws: BootFailure.self,
            performing: {
                try ChatSurfaceSettings.load([
                    SurfaceConfiguration.tokenKey: "<your-bot-token>",
                    SurfaceConfiguration.guildKey: "4242"
                ])
            }
        )
        #expect(failure.variable == SurfaceConfiguration.tokenKey)
        #expect(failure.code == .configuration)
        #expect(failure.summary.contains("<your-bot-token>"))
    }

    @Test("A server id of zero is a placeholder, not an id (the digit check passes it)")
    func aZeroServerIdRefuses() throws {
        // One to twenty digits accepts `0`, so the shape check cannot catch
        // this one and the loader that reads the same table in the other
        // half has always refused it by name.
        let failure = try #require(
            throws: BootFailure.self,
            performing: {
                try ChatSurfaceSettings.load([
                    SurfaceConfiguration.tokenKey: "a-token",
                    SurfaceConfiguration.guildKey: "0"
                ])
            }
        )
        #expect(failure.variable == SurfaceConfiguration.guildKey)
    }

    @Test("The two loaders that read this table agree about what is unfinished")
    func bothLoadersRefuseTheSamePlaceholders() throws {
        // `swift run bot` uses the smaller loader, so a check only the other
        // one made is a check this binary does not have.
        for value in PlaceholderValues.exact.union(["<fill-me-in>"]) {
            let refused = (try? ChatSurfaceSettings.load([
                SurfaceConfiguration.tokenKey: value,
                SurfaceConfiguration.guildKey: "4242"
            ])) == nil
            #expect(refused, "accepted \(value) as a token")
        }
    }

    @Test("A complete set loads, and the bot name falls back to nothing rather than a project")
    func aCompleteSetLoads() throws {
        let loaded = try #require(try ChatSurfaceSettings.load([
            SurfaceConfiguration.tokenKey: " a-token ",
            SurfaceConfiguration.guildKey: "4242",
            SurfaceConfiguration.adminRoleKey: "role-operator"
        ]))
        #expect(loaded.botToken == "a-token")
        #expect(loaded.serverId == "4242")
        #expect(loaded.operatorRoleId == "role-operator")
        #expect(loaded.botName == "")
    }

    @Test("The live factory answers nil rather than building anything, when there is nothing to build")
    func theFactoryBuildsNothingWithoutSettings() async throws {
        // Nothing is constructed on these paths: no gateway manager, no
        // client, no socket. That is why they can be run at all.
        #expect(try await DiscordChatGateway.live(settings: [:]) == nil)
    }

    @Test("A chat surface with no token profile is left to the configuration gate")
    func theFactoryDefersToTheGate() async throws {
        // Configured to talk, with nothing to draw a card with. The
        // composition root reads the same variables a moment later and
        // refuses naming the first one to set, so this answers nil rather
        // than saying it first and worse.
        let built = try await DiscordChatGateway.live(settings: [
            SurfaceConfiguration.tokenKey: "a-token",
            SurfaceConfiguration.guildKey: "4242"
        ])
        #expect(built == nil)
    }

    @Test("Every variable it reads is one it describes, so the listing is complete (TRUST-1)")
    func everythingItReadsIsDescribed() {
        let described = Set(ChatSurfaceSettings.settingsEntries.map(\.pattern))
        #expect(described == [
            SurfaceConfiguration.tokenKey,
            SurfaceConfiguration.guildKey,
            SurfaceConfiguration.applicationKey,
            SurfaceConfiguration.adminRoleKey,
            SurfaceConfiguration.botNameKey
        ])
    }
}
