import Chain
import Foundation
import Gating
import Store
import StoreSQLite
import Testing
@testable import Runtime

/// The eight gates, in the one order they run in.
///
/// Every test here boots for real: a store in memory, a stub node, and a
/// loopback bind on port zero. Nothing reaches a chain, a server or an
/// account (RT-030).
@Suite("The gates, in order")
internal struct BootSequenceTests {

    // MARK: - The order

    @Test("A clean start runs every gate, in the declared order (RT-008, SEE-11)")
    internal func everyGateInOrder() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        // Compared against what happened, not against a constant that claims
        // what happened.
        #expect(instance.gatesPassed == BootGate.allCases)
        await instance.shutDown()
    }

    @Test("The order is the one the type declares, and nothing configures it")
    internal func theDeclaredOrder() {
        #expect(
            BootGate.allCases == [
                .banner, .configuration, .store, .budget, .bind, .chain, .chat, .loops
            ]
        )
    }

    // MARK: - An empty machine

    @Test("Nothing set names the first variable, says what it is for, and exits 78 (ADOPT-2)")
    internal func emptyEnvironmentNamesTheFirstVariable() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Settings([:]))

        let failure = try #require(outcome.failure)
        // The asset id, because `GatingConfiguration.load` reads the token
        // before anything else: the ladder's thresholds cannot be converted
        // without its decimals and the pools cannot be given an asset id
        // without its asset id.
        #expect(failure.variable == TokenProfile.assetIdKey)
        #expect(failure.code == .configuration)
        #expect(failure.summary.contains("holder ladder is measured in"))
        #expect(outcome.gatesPassed == [.banner])

        let errors = await output.errorText
        #expect(errors.contains(TokenProfile.assetIdKey))
    }

    @Test("Each required variable, taken away on its own, is named in the refusal")
    internal func everyRequiredVariableNamesItself() async throws {
        for name in Fixture.requiredNames {
            let output = RecordingOutput()
            let outcome = await BootSequence(seams: Fixture.seams(output: output))
                .run(settings: Fixture.settings(extras: [name: nil]))
            let failure = try #require(outcome.failure, "\(name) did not refuse")
            #expect(failure.variable == name)
            #expect(failure.code == .configuration, "\(name)")
        }
    }

    @Test("The report is written even by a start that then refuses (RT-019)")
    internal func theReportIsWrittenOnARefusal() async {
        let output = RecordingOutput()
        _ = await BootSequence(seams: Fixture.seams(output: output)).run(settings: Settings([:]))
        let printed = await output.outText
        #expect(printed.contains("This build cannot move anything"))
        #expect(printed.contains("Settings"))
        #expect(printed.contains("UNSET, and required"))
    }

    // MARK: - What reaches the operator, and when

    @Test("The report goes out as it is made, not after the gate that waits on a node (RT-019)")
    internal func theReportIsWrittenAsItGoes() async throws {
        // A buffered report is nothing at all on standard output until the
        // last gate returns, and the gate before it waits on somebody else's
        // node with the request timeout of whoever built the data source. A
        // start killed by a supervisor's start-up timeout in that window
        // printed no banner, no catalogue and no line saying this start made
        // the store, which is the one thing that tells a mistyped path from a
        // genuine first boot (SEE-8).
        let node = SlowNode()
        let output = RecordingOutput()
        let booting = Task {
            await BootSequence(
                seams: Fixture.seams(
                    output: output,
                    store: InMemoryStoreOpener(createdFile: true),
                    chain: BlockingChainSource(node: node)
                )
            ).run(settings: Fixture.settings())
        }

        let arrived = await waitUntil { await output.outText.contains("/health") }
        #expect(arrived, "nothing was printed while the chain gate waited")
        let printedWhileWaiting = await output.outText
        #expect(printedWhileWaiting.contains("discord-bot"))
        #expect(printedWhileWaiting.contains("Token: asset 4242"))
        #expect(printedWhileWaiting.contains("This start CREATED the store"))
        // Not this one: the node has not answered, so nothing yet knows what
        // to say about it.
        #expect(!printedWhileWaiting.contains("Parts"))

        await node.release()
        let outcome = await booting.value
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let printed = await output.outText
        #expect(printed.contains("Parts"))
        // One report, not one and a fragment: what went out in pieces is the
        // same text the value holds.
        #expect(printed == instance.report.rendered)
        await instance.shutDown()
    }

    // MARK: - The day's budget

    @Test("The day's request count is restored before the first request (RUN-8.b)")
    internal func budgetIsRestoredFromTheStore() async throws {
        // Today's real day, because the governor counts a request against
        // the day the clock says it is: a count written for some other day is
        // a count from some other day, and restoring it is the one thing
        // this must not do.
        let today = Date()
        let store = try await SQLiteStore.inMemory()
        try await store.saveBudgetUsage(
            RequestBudgetUsage(usedRequests: 17, dayStart: UTCDay.start(of: today))
        )

        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(
                output: output,
                store: HandedStoreOpener(store: store),
                now: { today }
            )
        ).run(settings: Fixture.settings())

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        // Asserted against the governor the whole process shares, not
        // against the row in the store. The counter is written back every so
        // many requests, so a boot that makes one request writes nothing
        // either way and the row still reads 17 whether the restore ran or
        // not: the assertion that mattered could not fail (RUN-8).
        let budget = await instance.requestBudget()
        #expect(budget.usedRequests == 18, "restored 17 plus the chain gate's one request")
        let printed = await output.outText
        #expect(printed.contains("Restored today's request count: 17"))
        await instance.shutDown()
    }

    @Test("A first start of the day says it begins at zero rather than saying nothing")
    internal func noCountOnRecordIsSaidOutLoud() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let printed = await output.outText
        #expect(printed.contains("No request count on record for today"))
        #expect(await instance.requestBudget().usedRequests == 1)
        await instance.shutDown()
    }

    // MARK: - The loops

    @Test("The provider proof is probed once at the start, and then only when asked (RT-017)")
    internal func theProofIsProbedOnDemandRatherThanOnATimer() async throws {
        // The cache lifetime is a lifetime, not a poll interval. Refreshing
        // on a timer costs the provider one request every lifetime for the
        // life of the process whether or not anybody ever asks, and the probe
        // deliberately does not go through the request governor, so the day's
        // budget neither counts nor stops it. At the documented zero, which
        // means "do not cache", a timer becomes one request a second.
        let probe = CountingHeaderProbe()
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(output: output, chain: StubChainSource(probe: probe))
        ).run(
            settings: Fixture.settings(extras: [
                ChainEnvironment.proofHeaders: "x-served-by",
                ChainEnvironment.healthProbeSeconds: "0"
            ])
        )
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }

        #expect(await waitUntil { await probe.probes == 1 })
        // Long enough that a loop sleeping the cache lifetime, floored at a
        // second, would have gone round again at least once.
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(await probe.probes == 1, "the probe ran without anybody asking for health")

        _ = await instance.currentHealth()
        #expect(await waitUntil { await probe.probes == 2 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await probe.probes == 2, "one answer asked for more than one probe")
        await instance.shutDown()
    }

    @Test("A listener that dies takes the instance down and says so (RUN-7.a)")
    internal func aDeadListenerStopsTheInstance() async throws {
        // Not rebound in place: the endpoint would answer for an instance
        // nothing is watching, and this process would go on holding the
        // store's lease, so the replacement somebody starts is refused as a
        // duplicate and exits 69.
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        await instance.listenerDied(.acceptKeptFailing(times: 50, errorNumber: 24))
        await instance.waitUntilStopped()
        #expect(await instance.exitCode() == .internalError)
        let errors = await output.errorText
        #expect(errors.contains("The health endpoint has died"))
        #expect(errors.contains("50 times in a row"))
    }

    @Test("A count on record that cannot be read stops the boot rather than granting a new day")
    internal func unreadableBudgetRefuses() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(output: output, store: UnreadableBudgetStoreOpener())
        ).run(settings: Fixture.settings())

        let failure = try #require(outcome.failure)
        #expect(failure.code == .internalError)
        #expect(failure.summary.contains("could not be read"))
        #expect(outcome.gatesPassed == [.banner, .configuration, .store])
    }

    @Test("A count that was never written is not a refusal, because a first run has none")
    internal func noCountOnRecordIsFine() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        #expect(outcome.failure == nil)
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    // MARK: - Exit codes

    @Test("The codes are distinct, so a supervisor can tell a wrong token from a full disk")
    internal func codesAreDistinct() {
        let codes = ExitCode.allCases.map(\.rawValue)
        #expect(Set(codes).count == codes.count)
        #expect(ExitCode.ok.rawValue == 0)
        #expect(ExitCode.usage.rawValue == 64)
        #expect(ExitCode.unavailable.rawValue == 69)
        #expect(ExitCode.internalError.rawValue == 70)
        #expect(ExitCode.configuration.rawValue == 78)
    }
}

/// An opener that hands back a store the test already made, so the test can
/// write to it first and read it afterwards.
internal struct HandedStoreOpener: StoreOpening {

    internal let store: SQLiteStore

    internal func open(path: String) async throws -> OpenedStore {
        OpenedStore(store: store, migrationsApplied: [], createdFile: false)
    }
}

/// A store whose day count cannot be read.
///
/// Not a store that answers nothing: a row that cannot be read must throw,
/// because an unreadable count read as "nothing recorded" hands the process a
/// fresh budget, which is the exact failure the persistence exists to
/// prevent.
internal struct UnreadableBudgetStoreOpener: StoreOpening {

    internal func open(path: String) async throws -> OpenedStore {
        let store = try await SQLiteStore.inMemory()
        return OpenedStore(
            store: UnreadableBudgetStore(wrapped: store),
            migrationsApplied: [],
            createdFile: false
        )
    }
}
