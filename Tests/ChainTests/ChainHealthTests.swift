import Foundation
import Testing
@testable import Chain

/// What a health check answers.
///
/// The incident behind this suite ran for three hours while the process was
/// alive, the port answered and the check said ok. All true, none of it
/// useful. A check that comes back fine must mean the thing is doing its job.
@Suite("Saying whether it is really working")
internal struct ChainHealthTests {

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - What the answer means

    @Test("A listener that is up but has not connected yet does not report as working")
    internal func boundButNotConnectedIsStarting() {
        let report = ChainHealthReport(components: [
            ChainHealthComponent(name: "gateway", reached: false),
            ChainHealthComponent(name: "node", reached: true)
        ])
        #expect(report.status == .starting)
        #expect(report.waitingOn == ["gateway"])
        #expect(report.jsonBody == "{\"status\":\"starting\",\"waiting\":[\"gateway\"]}")
    }

    @Test("Everything it has to reach, reached, is what ok means")
    internal func everythingReachedIsOk() {
        let report = ChainHealthReport(components: [
            ChainHealthComponent(name: "gateway", reached: true),
            ChainHealthComponent(name: "node", reached: true)
        ])
        #expect(report.status == .ok)
        #expect(report.jsonBody == "{\"status\":\"ok\"}")
    }

    @Test("A host with nothing to wait for does not have to invent something")
    internal func noComponentsIsOk() {
        #expect(ChainHealthReport(components: []).status == .ok)
    }

    // MARK: - Proof of who served the request

    @Test("The headers copied as proof are the ones an operator configured")
    internal func proofHeadersAreConfigured() {
        let proof = ProviderProof.parse(
            headers: ["X-Served-By": "edge-3", "x-tier": "paid", "x-irrelevant": "no"],
            names: ["x-served-by", "x-tier"]
        )
        #expect(proof?.fields.map(\.name) == ["x-served-by", "x-tier"])
        #expect(proof?.fields.map(\.value) == ["edge-3", "paid"])
        #expect(proof?.httpHeaders["x-tier"] == "paid")
    }

    @Test("A provider that stamps nothing produces no proof, rather than empty proof")
    internal func noHeadersMeansNoProof() {
        #expect(ProviderProof.parse(headers: [:], names: ["x-tier"]) == nil)
        #expect(ProviderProof.parse(headers: ["x-tier": "   "], names: ["x-tier"]) == nil)
    }

    @Test("Proof appears in the answer, and is escaped rather than trusted")
    internal func proofIsEscapedIntoTheBody() {
        let report = ChainHealthReport(
            components: [ChainHealthComponent(name: "node", reached: true)],
            proof: ProviderProof(fields: [ProofField(name: "x-tier", value: "pa\"id\n")])
        )
        #expect(report.jsonBody == "{\"status\":\"ok\",\"provider\":{\"x-tier\":\"pa\\\"id\\n\"}}")
    }

    // MARK: - Probing for it

    @Test("A probe that failed never invents a success")
    internal func failedProbeInventsNothing() async {
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(failure: ChainError.network("connection reset")),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        #expect(await probe.proof(now: Self.noon) == nil)
        #expect(await probe.lastFailure != nil)
    }

    @Test("Proof that has gone stale is dropped rather than served as though it were current")
    internal func staleProofIsNotServedOn() async {
        // One probe asked twice, not two probes asked once. A second, fresh
        // instance has no cached proof to serve on, so it answers nil whatever
        // the code does, and the rule this type exists for goes untested.
        let probe = ProviderProofProbe(
            probe: FadingHeaderProbe(
                headers: ["x-tier": "paid"],
                failure: ChainError.network("connection reset")
            ),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        #expect(await probe.proof(now: Self.noon)?.fields.first?.value == "paid")

        // A probe that starts failing must stop claiming the paid path is in
        // use. Proof from half an hour ago is not evidence about now.
        #expect(await probe.proof(now: Self.noon.addingTimeInterval(31)) == nil)
        #expect(await probe.lastFailure != nil)
    }

    @Test("Monitoring on a timer does not become traffic to the node")
    internal func probeIsCachedForItsLifetime() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        _ = await probe.proof(now: Self.noon)
        _ = await probe.proof(now: Self.noon.addingTimeInterval(29))
        #expect(await log.count == 1)
        _ = await probe.proof(now: Self.noon.addingTimeInterval(31))
        #expect(await log.count == 2)
    }

    @Test("An operator who configured no proof headers is never probed at all")
    internal func noConfiguredHeadersMeansNoProbe() async throws {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            configuration: try Fixture.configuration()
        )
        #expect(await probe.proof(now: Self.noon) == nil)
        #expect(await log.count == 0)
    }

    @Test("Forgetting the cached proof makes the next answer a fresh probe")
    internal func invalidationForcesAProbe() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 300
        )
        _ = await probe.proof(now: Self.noon)
        await probe.invalidate()
        _ = await probe.proof(now: Self.noon)
        #expect(await log.count == 2)
    }

    // MARK: - The held read, which never probes

    @Test("The held read answers from what is already there, and probes nothing (SEE-1.b)")
    internal func heldProofMakesNoCall() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        // Nothing held yet, and asking for what is held must not go and get
        // some.
        #expect(await probe.heldProof(now: Self.noon) == nil)
        #expect(await log.count == 0)

        _ = await probe.proof(now: Self.noon)
        #expect(await log.count == 1)
        for _ in 0..<5 {
            #expect(await probe.heldProof(now: Self.noon)?.fields.first?.value == "paid")
        }
        #expect(await log.count == 1)
    }

    @Test("A held proof past its lifetime reads as absent rather than being refreshed (SEE-1.b, SEE-10.a)")
    internal func heldProofDoesNotRefreshAStaleAnswer() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        _ = await probe.proof(now: Self.noon)
        #expect(await log.count == 1)

        // This is the whole reason the read exists. `proof(now:)` would make a
        // request here, which is fine in a test and a surprise in production
        // at the moment the cache expires, on the one path that must never
        // make one.
        #expect(await probe.heldProof(now: Self.noon.addingTimeInterval(31)) == nil)
        #expect(await log.count == 1)

        // And the cache is left exactly as it was, so a health answer does not
        // quietly throw away the proof the next real probe would have reused.
        #expect(await probe.heldProof(now: Self.noon.addingTimeInterval(29))?.fields.first?.value == "paid")
        #expect(await probe.lastFailure == nil)
    }

    // MARK: - The refresh that fills what the held read reads

    @Test("An answer with no proof to give starts one probe, and the next answer carries it (SEE-10.a)")
    internal func anAnswerWithoutProofStartsAProbe() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        let assembler = ChainHealthAssembler(governor: RequestGovernor(limit: 0), probe: probe)

        // Nothing is held on a cold start, and the answer does not wait for
        // any: a synchronous probe here stalled the listener this was ported
        // from for up to four seconds.
        let first = await assembler.report(components: [], now: Self.noon)
        #expect(first.proof == nil)

        // But something has to go and get it. A read that never probes and
        // nothing else probing is an answer that can never carry proof at
        // all, which is what an operator configured the headers for: checking
        // from outside that the paid path is the one being served.
        await probe.flushRefresh()
        #expect(await log.count == 1)

        let second = await assembler.report(components: [], now: Self.noon)
        #expect(second.proof?.fields.first?.value == "paid")
        #expect(second.jsonBody.contains("\"provider\":{\"x-tier\":\"paid\"}"))

        // And a check on a timer does not become a queue of probes while what
        // is held is still current.
        await probe.flushRefresh()
        #expect(await log.count == 1)
    }

    @Test("A stale answer is refreshed beside the next check rather than in front of it (SEE-1.b)")
    internal func aStaleProofIsRefreshedBesideTheAnswer() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        let assembler = ChainHealthAssembler(governor: RequestGovernor(limit: 0), probe: probe)
        _ = await assembler.report(components: [], now: Self.noon)
        await probe.flushRefresh()
        #expect(await log.count == 1)

        // Within the lifetime the answer is served from what is held and
        // nothing is probed.
        #expect(await assembler.report(components: [], now: Self.noon.addingTimeInterval(29)).proof != nil)
        #expect(await log.count == 1)

        // Past it, proof reads as absent rather than being served on, and the
        // refresh that makes the next answer honest starts here.
        let stale = Self.noon.addingTimeInterval(31)
        #expect(await assembler.report(components: [], now: stale).proof == nil)
        await probe.flushRefresh()
        #expect(await log.count == 2)
        #expect(await assembler.report(components: [], now: stale).proof?.fields.first?.value == "paid")
    }

    @Test("A provider that is down is not probed again by every check while it is down (SEE-1.b)")
    internal func aFailingProbeIsNotRetriedOnEveryCheck() async {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(failure: ChainError.network("connection reset"), log: log),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        let assembler = ChainHealthAssembler(governor: RequestGovernor(limit: 0), probe: probe)
        for second in 0..<10 {
            let report = await assembler.report(
                components: [],
                now: Self.noon.addingTimeInterval(Double(second) * 2)
            )
            await probe.flushRefresh()
            // Never a fabricated success, whatever the check does.
            #expect(report.proof == nil)
        }
        // The failure is kept for the same lifetime a success gets, or a
        // monitoring check every two seconds becomes the load on the node at
        // the moment it can least take it.
        #expect(await log.count == 1)
        #expect(await probe.lastFailure != nil)
    }

    // MARK: - An answer that costs nothing

    @Test("Assembling an answer spends no request and asks the chain nothing (SEE-1.b)")
    internal func assemblingSpendsNothing() async throws {
        let log = CallLog()
        let governor = RequestGovernor(limit: 100)
        // A reader over the same governor, so that anything reaching for the
        // chain would both show in the log and move the counter.
        _ = ChainReader(
            configuration: try Fixture.configuration(),
            dataSource: StubAccountDataSource(log: log),
            governor: governor
        )
        try await governor.reserveRequests(7, for: Fixture.sweep, now: Self.noon)
        let before = await governor.snapshot(now: Self.noon)

        let assembler = ChainHealthAssembler(governor: governor)
        let report = await assembler.report(
            components: [ChainHealthComponent(name: "node", reached: true)],
            now: Self.noon
        )

        #expect(await log.calls.isEmpty)
        #expect(await governor.snapshot(now: Self.noon) == before)
        #expect(report.status == .ok)
        #expect(report.budget?.usedRequests == 7)
        #expect(report.budget?.remainingRequests == 93)
    }

    @Test("An instance with no proof configured opens no socket at all (SEE-1.b, SEE-10.a)")
    internal func noProofConfiguredMeansNoSocket() async throws {
        let log = CallLog()
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(headers: ["x-tier": "paid"], log: log),
            configuration: try Fixture.configuration()
        )
        let assembler = ChainHealthAssembler(governor: RequestGovernor(limit: 0), probe: probe)
        let report = await assembler.report(components: [], now: Self.noon)
        // This is what makes the promise honest rather than a statement about
        // a cache: with no headers named there is nothing to probe, and the
        // answer still comes back.
        #expect(await log.count == 0)
        #expect(report.proof == nil)
        #expect(report.status == .ok)
    }

    @Test("A proof that could not be taken leaves the answer without one, inventing nothing (SEE-10.a)")
    internal func aFailedProofDoesNotFailTheAnswer() async {
        let probe = ProviderProofProbe(
            probe: StubHeaderProbe(failure: ChainError.network("connection reset")),
            headerNames: ["x-tier"],
            lifetime: 30
        )
        _ = await probe.proof(now: Self.noon)
        let assembler = ChainHealthAssembler(governor: RequestGovernor(limit: 0), probe: probe)
        let report = await assembler.report(
            components: [ChainHealthComponent(name: "node", reached: true)],
            now: Self.noon
        )
        #expect(report.proof == nil)
        #expect(!report.jsonBody.contains("provider"))
        #expect(report.status == .ok)
    }

    @Test("The answer still comes back once the day's budget is spent (SEE-1.b, SEE-1.a)")
    internal func answersWithTheBudgetSpent() async throws {
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        await #expect(throws: ChainError.self) {
            try await governor.reserveRequest(for: Fixture.sweep, now: Self.noon)
        }

        let report = await ChainHealthAssembler(governor: governor).report(
            components: [ChainHealthComponent(name: "node", reached: true)],
            now: Self.noon
        )
        // Reachability is what the status is about. An instance that has
        // reached everything and is refusing chain work is `ok` and says the
        // rest in the body, or a deploy gate would roll back a working version
        // because a provider quota ran out at four in the afternoon (RUN-3).
        #expect(report.status == .ok)
        #expect(report.budget?.isPaused == true)
        #expect(report.budget?.pauseReason == .budgetSpent)
        #expect(report.jsonBody.contains("\"paused_reason\":\"budget_spent\""))
        let midnight = UTCDay.stamp(UTCDay.nextMidnight(after: Self.noon))
        #expect(report.jsonBody.contains("\"paused_until\":\"\(midnight)\""))
    }

    @Test("The answer says when it is the provider refusing rather than the budget (SEE-1.b)")
    internal func answersWithTheProviderRefusing() async {
        let governor = RequestGovernor(limit: 100)
        _ = await governor.recordRequestFailure(
            ChainError.api(statusCode: 403, message: "quota exceeded"),
            now: Self.noon
        )
        let report = await ChainHealthAssembler(governor: governor).report(
            components: [],
            now: Self.noon
        )
        #expect(report.status == .ok)
        #expect(report.budget?.pauseReason == .providerRefusedQuota)
        #expect(report.jsonBody.contains("\"paused_reason\":\"provider_refused_quota\""))
    }

    @Test("An instance with no budget set reads as having none rather than as having none left (SEE-9)")
    internal func noBudgetIsNotAnEmptyBudget() async {
        let report = await ChainHealthAssembler(governor: RequestGovernor(limit: 0)).report(
            components: [],
            now: Self.noon
        )
        // Both answer zero for what is left, which is why the body says which
        // of the two it is rather than leaving a reader to guess.
        #expect(report.budget?.hasBudget == false)
        #expect(report.jsonBody.contains("\"configured\":false"))
        let expected = "{\"status\":\"ok\","
            + "\"budget\":{\"configured\":false,\"used\":0,\"limit\":0,\"remaining\":0}}"
        #expect(report.jsonBody == expected)
    }

    @Test("The budget on the answer is the one every other surface reports (SEE-9)")
    internal func theBudgetIsTheSameSnapshot() async throws {
        let governor = RequestGovernor(limit: 50)
        try await governor.reserveRequests(20, for: Fixture.sweep, now: Self.noon)
        let report = await ChainHealthAssembler(governor: governor).report(
            components: [],
            now: Self.noon
        )
        // The same value, not two readings of it: a health page and a status
        // reply that can disagree about what is left are worse than one of
        // them not existing.
        #expect(report.budget == (await governor.snapshot(now: Self.noon)))
    }

    @Test("A report a host built itself carries the same body as an assembled one")
    internal func aPureReportSaysTheSameThing() async throws {
        let governor = RequestGovernor(limit: 10)
        try await governor.reserveRequests(3, for: Fixture.sweep, now: Self.noon)
        let snapshot = await governor.snapshot(now: Self.noon)
        let assembled = await ChainHealthAssembler(governor: governor).report(
            components: [ChainHealthComponent(name: "store", reached: false)],
            now: Self.noon
        )
        let byHand = ChainHealthReport(
            components: [ChainHealthComponent(name: "store", reached: false)],
            budget: snapshot
        )
        #expect(assembled == byHand)
        #expect(byHand.status == .starting)
        #expect(byHand.jsonBody.contains("\"waiting\":[\"store\"]"))
        #expect(byHand.jsonBody.contains("\"budget\":{\"configured\":true,\"used\":3,\"limit\":10,\"remaining\":7}"))
    }
}
