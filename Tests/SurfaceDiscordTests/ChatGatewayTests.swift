@preconcurrency import Foundation
import Gating
import Runtime
import Surface
import Testing

@testable import SurfaceDiscord

/// The join: the composition root's chat seam, and the one thing that
/// conforms to it.
///
/// Nothing here opens a socket to anybody. The session, the registrar, the
/// member roles and the replies are all doubles, and the one real socket in
/// the file is a loopback bind on port zero, which is the only way to obtain
/// the proof that connecting requires.
@Suite("The chat gateway, joined")
struct ChatGatewayTests {

    // MARK: - Doubles

    /// One ordered record across every double.
    ///
    /// Each double already records what happened to *it*, and the question
    /// the boot order turns on is which of two different objects was reached
    /// first. A per-object record cannot answer that, which is how a suite
    /// named for the order came to pass with the code doing the opposite.
    actor Journal {

        private(set) var entries: [String] = []

        func record(_ what: String) {
            entries.append(what)
        }

        var steps: [String] { entries }
    }

    /// Every session state the gateway reported, in order.
    actor StateLog {

        private(set) var entries: [ChatSessionState] = []

        func add(_ state: ChatSessionState) {
            entries.append(state)
        }

        var states: [ChatSessionState] { entries }
    }

    /// A session that records what happened to it and in what order, and
    /// hands over whatever events the test gave it.
    ///
    /// It holds `deliver` open until it is stopped, as a real session does:
    /// returning from `deliver` means the session ended, and that is what
    /// lowers health.
    actor SpySession: ChatSession {

        private(set) var calls: [String] = []
        private var queued: [ChatEvent]
        private var handler: (@Sendable (ChatEvent) async -> Void)?
        private var ending: AsyncStream<Void>.Continuation?
        private let journal: Journal?

        init(delivering queued: [ChatEvent] = [], journal: Journal? = nil) {
            self.queued = queued
            self.journal = journal
        }

        func identify() async throws {
            calls.append("identify")
            await journal?.record("identify")
        }

        func deliver(
            to handler: @escaping @Sendable (ChatEvent) async -> Void,
            onceReading reading: @escaping @Sendable () -> Void
        ) async {
            calls.append("deliver")
            await journal?.record("deliver")
            self.handler = handler
            let (stream, continuation) = AsyncStream<Void>.makeStream(of: Void.self)
            ending = continuation
            reading()
            for event in queued {
                await handler(event)
            }
            queued = []
            // Open until something ends it, which is the only honest model:
            // a `deliver` that returns straight away is a session that has
            // already closed.
            for await _ in stream {}
        }

        func stop() async {
            calls.append("stop")
            ending?.finish()
            ending = nil
        }

        /// Sends one more event, as the service would after the session is up.
        func send(_ event: ChatEvent) async {
            await handler?(event)
        }

        var record: [String] { calls }
    }

    actor SpyRegistrar: CommandRegistrar {

        private(set) var registered: [String] = []
        private(set) var servers: [String] = []
        private let journal: Journal?
        private let refusal: (any Error)?

        init(journal: Journal? = nil, refusing refusal: (any Error)? = nil) {
            self.journal = journal
            self.refusal = refusal
        }

        func register(_ catalog: ValidatedCatalog, guildId: String) async throws {
            await journal?.record("register")
            if let refusal { throw refusal }
            registered = catalog.names
            servers.append(guildId)
        }

        var names: [String] { registered }
        var seenServers: [String] { servers }
    }

    actor SpyMemberRoles: GuildMemberRoles {

        private(set) var written: [String: Set<String>] = [:]
        private let held: Set<String>

        init(held: Set<String> = ["role-one"]) {
            self.held = held
        }

        func roleIds(ofMember member: String) async throws -> Set<String> {
            held
        }

        func setRoles(ofMember member: String, to roleIds: Set<String>) async throws {
            written[member] = roleIds
        }

        var writes: [String: Set<String>] { written }
    }

    actor SpyReplies: InteractionReplying {

        private(set) var answered: [String] = []

        func perform(_ actions: [RouterAction], for request: InteractionRequest) async {
            answered.append((request.commandName ?? "?") + ":" + String(actions.count))
        }

        var record: [String] { answered }
    }

    /// A reply that does not finish until the test lets it.
    ///
    /// What a member's last command of the day looks like while the process
    /// is being asked to stop.
    actor HeldReplies: InteractionReplying {

        private(set) var started = false
        private var release: AsyncStream<Void>.Continuation?
        private var gate: AsyncStream<Void>?
        private let journal: Journal

        init(journal: Journal) {
            let (stream, continuation) = AsyncStream<Void>.makeStream(of: Void.self)
            self.gate = stream
            self.release = continuation
            self.journal = journal
        }

        func perform(_ actions: [RouterAction], for request: InteractionRequest) async {
            started = true
            if let gate {
                self.gate = nil
                for await _ in gate {}
            }
            await journal.record("answered")
        }

        /// Lets the answer finish.
        func letItFinish() {
            release?.finish()
            release = nil
        }

        var hasStarted: Bool { started }
    }

    /// Something for a double to refuse with.
    enum SpyRefusal: Error {

        /// No reason worth naming; what is being checked is what the gateway
        /// did before it.
        case no
    }

    // MARK: - Fixtures

    /// The one server these tests serve. Short on purpose: a real id pasted
    /// into a repository is somebody's actual server.
    private static let server = "4242"

    private static func catalog() throws -> ValidatedCatalog {
        try CommandValidator.validated(CommandCatalog.build(features: SurfaceFeatures(enabled: [])))
    }

    private static func token() throws -> TokenProfile {
        try TokenProfile(assetId: 4242, symbol: "TOKEN", decimals: 6)
    }

    private static func gateway(
        session: SpySession,
        registrar: SpyRegistrar = SpyRegistrar(),
        members: SpyMemberRoles = SpyMemberRoles(),
        replies: any InteractionReplying = SpyReplies()
    ) throws -> DiscordChatGateway {
        let catalog = try Self.catalog()
        return DiscordChatGateway(
            serverId: Self.server,
            catalog: catalog,
            router: SurfaceRouter(
                servedGuildId: Self.server,
                catalog: catalog.catalog,
                commands: [
                    PingCommand(),
                    HelpCommand(
                        chrome: CardChrome(botName: "", token: try Self.token()),
                        features: SurfaceFeatures(enabled: [])
                    )
                ]
            ),
            session: session,
            registrar: registrar,
            members: members,
            replies: replies
        )
    }

    /// The only way to obtain the proof that connecting requires.
    private static func bound() async throws -> (RootHealthListener, ListenerBound) {
        let listener = RootHealthListener(state: RootHealthState(componentNames: []))
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        return (listener, bound)
    }

    /// One member running `/ping`.
    private static var ping: ChatEvent {
        .interaction(InteractionRequest(
            kind: .command,
            commandName: CommandCatalog.ping,
            guildId: Self.server,
            userExternalId: "member"
        ))
    }

    // MARK: - The order that cannot be changed

    @Test("Nothing identifies and nothing registers until connect is called (RUN-7, RUN-7.a)")
    func nothingHappensBeforeConnect() async throws {
        let session = SpySession()
        let registrar = SpyRegistrar()
        _ = try Self.gateway(session: session, registrar: registrar)

        // Built, wired and holding a token's worth of everything, and it has
        // said nothing to anybody. The only door is `connect(afterBinding:)`
        // and it takes a value only a completed bind produces.
        #expect(await session.record.isEmpty)
        #expect(await registrar.names.isEmpty)
    }

    @Test("Connect identifies once, and is handed exactly what the bind produced")
    func connectIdentifiesOnce() async throws {
        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })

        let record = await session.record
        #expect(record.filter { $0 == "identify" }.count == 1)
        #expect(proof.port != 0)
        await gateway.disconnect()
    }

    @Test("The catalogue is registered, and the reader subscribed, before the identify")
    func theIdentifyIsTheLastThing() async throws {
        // The one ordering an outage turns on, asserted across the two
        // objects it spans rather than inside either of them.
        //
        // Registration is an HTTP round trip and is the step here that fails
        // for ordinary reasons an offline validator cannot catch. A failure
        // refuses the boot and the process exits, so under a supervisor it
        // happens again on every restart: after the identify, each of those
        // restarts spends a session, and a bot that identifies too often in
        // a day has its token revoked. The reader then goes between the two,
        // because nothing is delivered before an identify and the opening
        // event arrives a moment after one.
        let journal = Journal()
        let session = SpySession(journal: journal)
        let registrar = SpyRegistrar(journal: journal)
        let gateway = try Self.gateway(session: session, registrar: registrar)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })

        #expect(await journal.steps == ["register", "deliver", "identify"])
        let expected = try Self.catalog().names
        #expect(await registrar.names == expected)
        #expect(await registrar.seenServers == [Self.server])
        await gateway.disconnect()
    }

    @Test("A registration that fails costs no identify at all")
    func aFailedRegistrationNeverIdentifies() async throws {
        let journal = Journal()
        let session = SpySession(journal: journal)
        let registrar = SpyRegistrar(journal: journal, refusing: SpyRefusal.no)
        let gateway = try Self.gateway(session: session, registrar: registrar)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        await #expect(throws: SpyRefusal.self) {
            try await gateway.connect(afterBinding: proof, reporting: { _ in })
        }

        // A 403 for a bot invited without the commands scope, a 404 for a
        // server it is not in, a 429 or a 5xx all land here. The boot refuses
        // and the process exits; nothing was spent that a restart cannot
        // spend again for free.
        #expect(await journal.steps == ["register"])
        #expect(await session.record.isEmpty)
    }

    @Test("What is registered is the catalogue the validator passed, to one server")
    func registersTheValidatedCatalogue() async throws {
        let session = SpySession()
        let registrar = SpyRegistrar()
        let gateway = try Self.gateway(session: session, registrar: registrar)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })

        // Two, not four: `/verify` and `/unlink` need a half this build does
        // not assemble, and a command that cannot finish is never offered
        // (ADOPT-10.b).
        #expect(await registrar.names == ["ping", "help"])
        await gateway.disconnect()
    }

    @Test("The bind cannot be faked from here, so the order is the compiler's to keep")
    func proofCannotBeMadeOutsideTheRoot() async throws {
        // What this asserts by existing rather than by running: the only
        // initialiser of `ListenerBound` is internal to `Runtime`, so
        //
        //     try await gateway.connect(afterBinding: ListenerBound(...))
        //
        // does not compile in this target however convenient it would be.
        // The value below came from a real bind, which is the only source.
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }
        #expect(proof.address == "127.0.0.1")

        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        try await gateway.connect(afterBinding: proof, reporting: { _ in })
        #expect(await session.record.contains("identify"))
        await gateway.disconnect()
    }

    // MARK: - What the session says about health

    @Test("Only the session's own opening event reports it open, never the connect returning")
    func onlyTheOpeningEventReportsOpen() async throws {
        let reported = StateLog()
        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { await reported.add($0) })

        // Registered, reading and identified, and nothing has been reported.
        // Identifying is asking for a websocket rather than having one, so a
        // surface that reported here would put a deploy gate's check at 200
        // for a process that is not in the server (SEE-1.a).
        #expect(await reported.states.isEmpty)

        await session.send(.ready(botExternalId: "bot"))
        #expect(await waitUntil { await reported.states == [.open] })

        // A resume is the session coming back, so it says so again.
        await session.send(.resumed)
        #expect(await waitUntil { await reported.states == [.open, .open] })
    }

    @Test("A session that ends reports closed, which is what takes health back down")
    func aSessionThatEndsReportsClosed() async throws {
        let reported = StateLog()
        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { await reported.add($0) })
        await session.send(.ready(botExternalId: "bot"))
        #expect(await waitUntil { await reported.states == [.open] })

        // The chat library leaves its event stream open on a close it will
        // not retry, so nothing else in the process would ever say this bot
        // has gone deaf.
        await gateway.disconnect()
        #expect(await waitUntil { await reported.states.last == .closed })
    }

    // MARK: - Answering

    @Test("An interaction delivered after the session is up is answered")
    func interactionsAreAnswered() async throws {
        let replies = SpyReplies()
        let session = SpySession(delivering: [.ready(botExternalId: "bot"), Self.ping])
        let gateway = try Self.gateway(session: session, replies: replies)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })
        #expect(await waitUntil { await replies.record.count == 1 })
        #expect(await replies.record == ["ping:1"])
        await gateway.disconnect()
    }

    @Test("The reader is subscribed before the identify, so the opening event is not missed")
    func theReaderIsSubscribedBeforeTheIdentify() async throws {
        let replies = SpyReplies()
        let journal = Journal()
        let session = SpySession(journal: journal)
        let gateway = try Self.gateway(session: session, replies: replies)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })

        // Subscribed, not merely scheduled. Starting a task does not order it
        // against the `await` inside it, and the chat library hands out a
        // fresh continuation when its sequence is read and replays nothing,
        // so an event fanned out before that read is gone for good.
        let steps = await journal.steps
        let reading = try #require(steps.firstIndex(of: "deliver"))
        let identified = try #require(steps.firstIndex(of: "identify"))
        #expect(reading < identified)
        // Once, not once per event: a second reader would answer the same
        // interaction twice.
        #expect(await session.record.filter { $0 == "deliver" }.count == 1)

        // And it is still reading, which is what an event sent now proves.
        await session.send(Self.ping)
        #expect(await waitUntil { await replies.record.count == 1 })
        await gateway.disconnect()
    }

    // MARK: - Roles

    @Test("A member and a role are plain strings on this side of the seam")
    func rolesArePlainStrings() async throws {
        let members = SpyMemberRoles(held: ["role-one", "role-two"])
        let session = SpySession()
        let gateway = try Self.gateway(session: session, members: members)

        #expect(try await gateway.roleIds(ofMember: "member-one") == ["role-one", "role-two"])
        try await gateway.setRoles(ofMember: "member-one", to: ["role-two", "role-three"])
        #expect(await members.writes == ["member-one": ["role-two", "role-three"]])
    }

    // MARK: - Stopping

    @Test("Disconnect closes the session")
    func disconnectStopsTheSession() async throws {
        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })
        await gateway.disconnect()
        #expect(await session.record.last == "stop")
    }

    @Test("Disconnect waits for the answer already in flight before it leaves")
    func disconnectDrainsTheAnswersInFlight() async throws {
        // The composition root puts `disconnect` first on the strength of a
        // handler holding the store, and a handler answering a member is one
        // of these tasks: without the wait that ordering buys nothing and a
        // member's last command of the day becomes a crash rather than an
        // answer (RT-028).
        let journal = Journal()
        let replies = HeldReplies(journal: journal)
        let session = SpySession()
        let gateway = try Self.gateway(session: session, replies: replies)
        let (listener, proof) = try await Self.bound()
        defer { Task { await listener.stop() } }

        try await gateway.connect(afterBinding: proof, reporting: { _ in })
        await session.send(Self.ping)
        #expect(await waitUntil { await replies.hasStarted })

        let stopping = Task {
            await gateway.disconnect()
            await journal.record("disconnected")
        }
        // Let go only once the shutdown is well under way, so a disconnect
        // that did not wait would have recorded itself first.
        try await Task.sleep(for: .milliseconds(100))
        await replies.letItFinish()
        await stopping.value

        #expect(await journal.steps == ["answered", "disconnected"])
    }

    // MARK: - What it says it reads

    @Test("The surface describes its own variables, because the root may not name them")
    func theSurfaceDescribesItself() throws {
        let session = SpySession()
        let gateway = try Self.gateway(session: session)
        let patterns = gateway.settingsEntries.map(\.pattern)
        #expect(patterns.contains(SurfaceConfiguration.tokenKey))
        #expect(patterns.contains(SurfaceConfiguration.guildKey))
        // Every one of them belongs to the group the report prints them
        // under, or the listing would drop them silently.
        #expect(gateway.settingsEntries.allSatisfy { $0.group == .chat })
    }

    @Test("The token is a secret, so no listing can print it")
    func theTokenIsASecret() {
        let entry = ChatSurfaceSettings.settingsEntries
            .first { $0.pattern == SurfaceConfiguration.tokenKey }
        #expect(entry?.secrecy == .secret)
    }
}

/// Waits for something to become true, or gives up.
///
/// A test that hangs says far less than one that fails.
///
/// - Parameters:
///   - deadline: How long to keep asking.
///   - condition: What is being waited for.
/// - Returns: Whether it came true in time.
@discardableResult
func waitUntil(
    within deadline: Duration = .seconds(2),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let started = ContinuousClock.now
    while ContinuousClock.now - started < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
