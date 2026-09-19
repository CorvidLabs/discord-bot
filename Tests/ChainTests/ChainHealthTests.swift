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
}
