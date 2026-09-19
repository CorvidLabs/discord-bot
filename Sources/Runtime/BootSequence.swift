import Chain
import Foundation
import Gating
import Store

/// What a start came to.
public enum BootOutcome: Sendable {

    /// It walked the gates and is up.
    case running(RunningInstance)

    /// It stopped, and this is what the operator is told and what the
    /// supervisor reads.
    case refused(BootFailure, report: StartupReport, gatesPassed: [BootGate])

    // MARK: - Public Methods

    /// The report this start wrote, whichever way it went.
    public var report: StartupReport {
        switch self {
        case .running(let instance): return instance.report
        case .refused(_, let report, _): return report
        }
    }

    /// The gates that ran, in the order they ran.
    public var gatesPassed: [BootGate] {
        switch self {
        case .running(let instance): return instance.gatesPassed
        case .refused(_, _, let passed): return passed
        }
    }

    /// The refusal, or nil when it is up.
    public var failure: BootFailure? {
        switch self {
        case .running: return nil
        case .refused(let failure, _, _): return failure
        }
    }
}

/// The eight gates, in order, with nothing between them that a setting could
/// reorder.
///
/// The sequence is handed its seams and can therefore be driven entirely from
/// a test: the store is `SQLiteStore.inMemory()` or a file the test made, the
/// chain is a stub data source, the chat is a spy, and the only socket is a
/// loopback bind on port zero, which reaches no real chain, server or account
/// (RT-030).
public struct BootSequence: Sendable {

    // MARK: - Properties

    private let seams: RuntimeSeams

    // MARK: - Initializers

    /// - Parameter seams: Everything live, handed in.
    public init(seams: RuntimeSeams) {
        self.seams = seams
    }

    // MARK: - Public Methods

    /// Walks the gates, in the order ``BootGate/allCases`` declares.
    ///
    /// The report is written whatever happens, including on the way out of a
    /// refusal, because a start that refuses is still a start and it is the
    /// one a contributor sees most often (RT-019).
    ///
    /// **Each section goes out as it is produced rather than at the end.** A
    /// buffered report is nothing at all on standard output until the last
    /// gate returns, and the gate before it waits on somebody else's node: a
    /// start killed by a supervisor's timeout while the node is black-holed
    /// would print no banner, no catalogue and, worst of all, no line saying
    /// this start created the store, which is the one thing that tells a
    /// mistyped path from a genuine first boot (SEE-8).
    ///
    /// - Parameter settings: The one snapshot of the machine's variables.
    public func run(settings: Settings) async -> BootOutcome {
        // What a linked chat surface reads, in its own words. This module
        // cannot name a chat variable, so the surface describes itself and
        // the listing, the audit and the reserved-prefix rule all work from
        // the same list (BUILD-4, RT-014).
        let chatEntries = seams.chat?.settingsEntries ?? []
        let catalogue = SettingsCatalogue.entries + chatEntries
        var state = BootProgress(settings: settings, hasChat: seams.chat != nil)

        // 1. The banner, before the settings are even read.
        await state.write(StartupReportWriter.opening(capability: seams.spending), to: seams.output)
        state.passed.append(.banner)
        await state.write(
            StartupReportWriter.catalogue(settings: settings, catalogue: catalogue),
            to: seams.output
        )

        // 2. Configuration. The only gate that touches nothing, so a wrong
        //    variable costs no lock, no socket and no request.
        do {
            state.configuration = try LoadedConfiguration.load(
                settings,
                alsoRead: chatEntries.filter { !$0.isFamily }.map(\.pattern)
            )
        } catch {
            return await refuse(BootFailure.configuration(error), &state)
        }
        guard let configuration = state.configuration else {
            return await refuse(
                BootFailure(summary: "The configuration did not load.", code: .internalError),
                &state
            )
        }
        state.audit = SettingsAudit.of(
            settings: settings,
            keysRead: configuration.keysRead,
            catalogue: catalogue
        )
        if let refusal = state.audit?.refusal {
            return await refuse(refusal, &state)
        }
        state.passed.append(.configuration)
        await state.write(
            StartupReportWriter.understanding(configuration: configuration),
            to: seams.output
        )

        // 3. The store, and the lease that keeps a second instance out, before
        //    any socket is bound.
        do {
            state.opened = try await seams.store.open(path: configuration.runtime.storePath)
        } catch {
            return await refuse(Self.storeRefusal(error), &state)
        }
        guard let opened = state.opened else {
            return await refuse(
                BootFailure(summary: "The store did not open.", code: .unavailable),
                &state
            )
        }
        state.passed.append(.store)
        await state.write(
            StartupReportWriter.store(opened, path: configuration.runtime.storePath),
            to: seams.output
        )

        // 4. Today's request count, back into the one governor everything
        //    shares, before the first request of the process (RUN-8.b).
        let governor = RequestGovernor(
            limits: configuration.chain.limits,
            store: opened.store,
            now: seams.now()
        )
        let restored: Bool
        do {
            restored = try await governor.restoreFromStore(now: seams.now())
        } catch {
            await opened.store.close()
            return await refuse(
                BootFailure(
                    summary: "Today's request count is on record and could not be read: "
                        + Self.describe(error),
                    remedy: "Starting anyway would hand this process a second day's allowance "
                        + "against the provider's own day, so it stopped instead.",
                    code: .internalError
                ),
                &state
            )
        }
        state.passed.append(.budget)
        // Said out loud, because it is the one number a restart can get wrong
        // in a way nothing else in this build would show: several restarts in
        // one UTC day each starting from zero spend past the ceiling while
        // the provider's own day keeps running (RUN-8).
        await state.write(
            StartupReportWriter.budget(
                restored: restored,
                snapshot: await governor.snapshot(now: seams.now())
            ),
            to: seams.output
        )

        // 5. The bind, which produces the value nothing can identify without.
        let health = HealthState(
            componentNames: Self.componentNames(for: configuration, hasChat: seams.chat != nil)
        )
        await health.markReached(HealthComponent.store)
        let socket = HealthListener(state: health)
        let bound: ListenerBound
        do {
            bound = try await socket.bind(
                address: configuration.runtime.healthAddress,
                port: configuration.runtime.healthPort
            )
        } catch {
            await opened.store.close()
            return await refuse(Self.bindRefusal(error), &state)
        }
        state.bound = bound
        state.passed.append(.bind)
        await state.write(StartupReportWriter.listener(bound), to: seams.output)

        // 6. The node. Refuses only on an answer that contradicts the
        //    configuration; anything else leaves the component unreached and
        //    the instance up and `starting`.
        let reader: ChainReader
        do {
            reader = ChainReader(
                configuration: configuration.chain,
                dataSource: try seams.chain.dataSource(for: configuration.chain),
                governor: governor
            )
        } catch {
            await socket.stop()
            await opened.store.close()
            return await refuse(
                BootFailure(
                    variable: ChainEnvironment.nodeURL,
                    summary: Self.describe(error),
                    code: .configuration
                ),
                &state
            )
        }
        let chainOutcome = await ChainGate.probe(reader: reader)
        state.chainOutcome = chainOutcome
        switch chainOutcome {
        case .contradiction(let failure):
            await Self.stopBackground(&state)
            await socket.stop()
            await opened.store.close()
            return await refuse(failure, &state)
        case .confirmed:
            await health.markReached(HealthComponent.chain)
        case .notProbed:
            // Nothing to mark. The check is off, so the node is not a
            // component of this instance's health at all, and the report's
            // Parts section names it and says why (RT-016). Marking a
            // component reached that nothing has reached is how a check comes
            // back fine for an instance that has never spoken to the node.
            break
        case .unreached:
            // Left unreached on purpose. A node that does not answer has said
            // nothing about the configuration, and stopping the boot on it
            // turns a provider's bad five minutes into a bot that stays down
            // until somebody notices (RUN-3).
            state.background.append(retryTask(reader: reader, health: health))
        }
        state.passed.append(.chain)
        await state.write(
            StartupReportWriter.parts(
                configuration: configuration,
                capability: seams.spending,
                chainOutcome: chainOutcome,
                hasChat: seams.chat != nil
            ),
            to: seams.output
        )

        // 7. The chat service, if this build has one. It is handed the value
        //    the bind produced and cannot be reached without it, which is
        //    what makes identifying before binding a program that does not
        //    compile rather than a comment somebody moves (RUN-7.a). A build
        //    with no chat surface refused a chat variable back at the
        //    configuration gate instead, which is where an operator finds
        //    out (RT-014).
        //
        //    Health is **not** raised here. The gate returning says the
        //    identify was asked for, and asking for a websocket is not
        //    having one, so the surface reports its own session through the
        //    closure below and the component stays unreached until the
        //    service's opening event arrives (SEE-1.a).
        if let chat = seams.chat {
            do {
                try await chat.connect(afterBinding: bound) { state in
                    switch state {
                    case .open: await health.markReached(HealthComponent.chat)
                    case .closed: await health.markUnreached(HealthComponent.chat)
                    }
                }
            } catch {
                // The session first, and before the store closes. For the
                // live surface this throws only once the identify has been
                // spent, so a refusal that walked away would leave an
                // identified session and a reconnecting client behind while
                // the process exits and a supervisor starts another one.
                await chat.disconnect()
                // A retry task still in flight holds the governor, which
                // holds this store.
                await Self.stopBackground(&state)
                await socket.stop()
                await opened.store.close()
                return await refuse(
                    BootFailure(
                        summary: "The chat service refused the connection: " + Self.describe(error),
                        code: .configuration
                    ),
                    &state
                )
            }
        }
        state.passed.append(.chat)

        // 8. The loops. There is no sweep and no scheduler yet, and this is
        //    where they will go. The one thing running is the refresh of the
        //    provider proof, which is here because it must never happen on
        //    the health request path.
        if let probe = seams.chain.proofProbe(for: configuration.chain) {
            state.background.append(
                proofRefreshTask(
                    probe: ProviderProofProbe(probe: probe, configuration: configuration.chain),
                    health: health,
                    now: seams.now
                )
            )
        }
        state.passed.append(.loops)

        let instance = RunningInstance(
            listener: bound,
            gatesPassed: state.passed,
            report: await state.finish(capability: seams.spending, to: seams.output),
            health: health,
            listenerSocket: socket,
            chat: seams.chat,
            store: opened.store,
            governor: governor,
            output: seams.output,
            background: state.background
        )
        // A listener that dies takes the whole instance with it. It cannot be
        // rebound in place: the endpoint would answer for an instance nothing
        // else is watching, and this process would go on holding the store's
        // lease, so the replacement a supervisor starts is refused as a
        // duplicate (RUN-7.a).
        await socket.onDeath { [weak instance] death in
            await instance?.listenerDied(death)
        }
        return .running(instance)
    }

    // MARK: - Internal Methods

    /// The components this build declares, given what the operator switched
    /// on.
    ///
    /// **A part that is off contributes none**, because an off part reported
    /// as unreached would hold the instance at `starting` for ever, and one
    /// reported as reached is worse still: the answer would say this instance
    /// has spoken to the node when nothing ever has, which is the three hour
    /// incident the endpoint exists for. Off parts are named in the startup
    /// report instead (RT-016).
    ///
    /// **A linked chat surface contributes one**, and it starts unreached.
    /// A process whose websocket never opens is not a degraded bot, it is a
    /// bot that is not in the server, and the whole reason this endpoint
    /// exists is that nothing watching could tell the two apart (SEE-1,
    /// SEE-1.a).
    ///
    /// - Parameters:
    ///   - configuration: What loaded.
    ///   - hasChat: Whether this build was given a chat surface.
    internal static func componentNames(
        for configuration: LoadedConfiguration,
        hasChat: Bool = false
    ) -> [String] {
        var names = [HealthComponent.store]
        if configuration.chain.verifiesAssetDecimals {
            names.append(HealthComponent.chain)
        }
        if hasChat {
            names.append(HealthComponent.chat)
        }
        return names
    }

    // MARK: - Private Methods

    /// Asks the node again, backing off, until it answers or the process
    /// stops.
    ///
    /// Every attempt goes through the same governor everything else does, so
    /// a node down overnight cannot spend the day's budget on retries, and a
    /// node that comes back moves the health answer from `starting` to `ok`
    /// without a restart (RUN-3, SEE-10.a).
    private func retryTask(reader: ChainReader, health: HealthState) -> Task<Void, Never> {
        Task {
            var delay: Duration?
            while !Task.isCancelled {
                let wait = ChainGate.nextRetryDelay(after: delay)
                delay = wait
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    return
                }
                switch await ChainGate.probe(reader: reader) {
                case .confirmed, .notProbed:
                    await health.markReached(HealthComponent.chain)
                    return
                case .contradiction:
                    // A contradiction found after the boot cannot un-boot the
                    // process. The component stays unreached, which is what
                    // the health answer is for.
                    return
                case .unreached:
                    continue
                }
            }
        }
    }

    /// Refreshes the provider proof off the request path, when somebody has
    /// asked for a health answer since the last refresh.
    ///
    /// Never inside the handler: ``Chain/ProviderProofProbe/proof(now:)``
    /// refreshes when its cache is stale, so answering a health request
    /// through it would put a network call on the request path, which is the
    /// one thing a health check must not do (RT-017).
    ///
    /// **And never on a timer either.** One probe at the start, as the bot
    /// this was ported from made, and thereafter one per answer given, which
    /// the probe's own cache then reduces to at most one per cache lifetime.
    /// An instance nobody checks costs the provider one request for its whole
    /// life. A loop ticking every cache lifetime would cost one every thirty
    /// seconds for ever, and none of them go through the request governor, so
    /// ``Chain/ChainEnvironment/dailyRequestBudget`` would neither count nor
    /// stop them.
    private func proofRefreshTask(
        probe: ProviderProofProbe,
        health: HealthState,
        now: @escaping @Sendable () -> Date
    ) -> Task<Void, Never> {
        Task {
            // Once at the start, so the first answer already carries proof.
            // In the background rather than in the gate, because a provider
            // slow to answer must not hold up the report or the bind.
            await health.store(proof: probe.proof(now: now()))
            for await _ in health.proofRefreshWanted {
                if Task.isCancelled { return }
                await health.store(proof: probe.proof(now: now()))
            }
        }
    }

    /// Prints the report and the refusal, and says what the process exits
    /// with.
    ///
    /// **The report is written as it was rendered and the refusal is
    /// redacted**, and the asymmetry is the design rather than an oversight.
    /// The report is rendered from the catalogue, so the renderer has no path
    /// to the value of an entry marked secret and cannot print one however
    /// hard it tries. A refusal is different: the loaders quote the value
    /// they could not use, and a node URL can carry a credential in its path,
    /// so that one line is filtered on its way to standard error.
    private func refuse(_ failure: BootFailure, _ state: inout BootProgress) async -> BootOutcome {
        await Self.stopBackground(&state)
        let report = await state.finish(capability: seams.spending, to: seams.output)
        await seams.output.writeError(
            failure.lines.map { SecretRedaction.applied(to: $0, settings: state.settings) }
        )
        return .refused(failure, report: report, gatesPassed: state.passed)
    }

    /// Stops anything a gate started, and waits for it.
    ///
    /// Waited for rather than only cancelled, because a retry task in flight
    /// holds the governor, which holds the store a refusal is about to close
    /// underneath it. Cancelling wakes a sleeping task at once and a request
    /// in flight not much later, so the wait is short.
    private static func stopBackground(_ state: inout BootProgress) async {
        let running = state.background
        state.background = []
        for task in running {
            task.cancel()
        }
        for task in running {
            await task.value
        }
    }

    private static func storeRefusal(_ error: any Error) -> BootFailure {
        BootFailure(
            variable: RuntimeEnvironment.storePath,
            summary: describe(error),
            code: .unavailable
        )
    }

    private static func bindRefusal(_ error: any Error) -> BootFailure {
        BootFailure(
            variable: RuntimeEnvironment.healthPort,
            summary: describe(error),
            code: (error as? HealthListenerError)?.exitCode ?? .unavailable
        )
    }

    private static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? "\(error)"
    }
}

/// What the boot knows so far, so the report can be finished from wherever it
/// stopped.
///
/// A start that refuses still writes a report, and the report has to describe
/// as much as the boot got to. Sections a gate cannot fill in yet are held
/// here and written by ``finish(capability:to:)``, which is what stops a
/// refusal printing two contradictory `Parts` sections, which is what happened
/// when each gate appended its own.
fileprivate struct BootProgress {

    // MARK: - Properties

    fileprivate let settings: Settings

    /// Whether this build was given a chat surface, so a refusal's own Parts
    /// section says the same thing a clean start's would.
    fileprivate let hasChat: Bool

    fileprivate var passed: [BootGate] = []
    fileprivate var configuration: LoadedConfiguration?
    fileprivate var audit: SettingsAudit?
    fileprivate var opened: OpenedStore?
    fileprivate var bound: ListenerBound?
    fileprivate var chainOutcome: ChainGateOutcome?
    fileprivate var background: [Task<Void, Never>] = []

    private var report = StartupReport()

    /// How many sections have already gone out, so the rest can follow
    /// without any of them going out twice.
    private var written = 0

    // MARK: - Initializers

    fileprivate init(settings: Settings, hasChat: Bool) {
        self.settings = settings
        self.hasChat = hasChat
    }

    // MARK: - Internal Methods

    /// Adds a section and writes it straight out.
    ///
    /// - Parameters:
    ///   - section: The section.
    ///   - output: Where the report goes.
    fileprivate mutating func write(_ section: ReportSection, to output: any RuntimeOutput) async {
        report.append(section)
        await flush(to: output)
    }

    /// Writes everything a gate could not fill in earlier, and returns the
    /// whole report as one value.
    ///
    /// - Parameters:
    ///   - capability: Whether this build can move anything.
    ///   - output: Where the report goes.
    fileprivate mutating func finish(
        capability: SpendCapability,
        to output: any RuntimeOutput
    ) async -> StartupReport {
        if let configuration, !hasSection(titled: StartupReportWriter.partsTitle) {
            report.append(
                StartupReportWriter.parts(
                    configuration: configuration,
                    capability: capability,
                    chainOutcome: chainOutcome,
                    hasChat: hasChat
                )
            )
        }
        if let audit {
            report.appendIfAny(StartupReportWriter.audit(audit))
        }
        await flush(to: output)
        return report
    }

    // MARK: - Private Methods

    /// Whether a gate has already written the section under this heading.
    private func hasSection(titled title: String) -> Bool {
        report.sections.contains { $0.title == title }
    }

    private mutating func flush(to output: any RuntimeOutput) async {
        let pending = report.lines(from: written)
        written = report.sections.count
        guard !pending.isEmpty else { return }
        await output.write(pending)
    }
}
