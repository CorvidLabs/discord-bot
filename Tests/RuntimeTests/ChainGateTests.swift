import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// Which answers from the node stop a start, and which do not.
///
/// The line is whether the node contradicted the configuration or merely
/// failed to answer. A contradiction is a mistake an operator fixes in a
/// minute once they are told; silence says nothing about the configuration,
/// and stopping the boot on it turns a provider's bad five minutes into a bot
/// that stays down until somebody notices (ADOPT-12.a, RUN-3).
@Suite("The chain gate")
internal struct ChainGateTests {

    // MARK: - Contradictions

    @Test("An asset the node has never heard of refuses, naming the asset variable")
    internal func assetNotFoundRefuses() async throws {
        let outcome = ChainGate.classify(ChainError.assetNotFound(assetId: 4_242))
        guard case .contradiction(let failure) = outcome else {
            Issue.record("expected a contradiction, got \(outcome)")
            return
        }
        #expect(failure.variable == TokenProfile.assetIdKey)
        #expect(failure.code == .configuration)
    }

    @Test("Decimals that disagree refuse, naming the decimals variable")
    internal func decimalsDisagreeRefuse() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(output: output, chain: StubChainSource(assetDecimals: 2))
        ).run(settings: Fixture.settings())

        let failure = try #require(outcome.failure)
        #expect(failure.variable == TokenProfile.decimalsKey)
        #expect(failure.code == .configuration)
        // Every balance would be wrong by a factor of ten per missing place,
        // and nothing anywhere would look broken.
        #expect(failure.summary.contains("factor of ten"))
    }

    @Test("A 401 is the operator's credential, and waiting does not fix it")
    internal func unauthorisedRefuses() {
        let outcome = ChainGate.classify(ChainError.api(statusCode: 401, message: "no"))
        guard case .contradiction(let failure) = outcome else {
            Issue.record("expected a contradiction, got \(outcome)")
            return
        }
        #expect(failure.variable == ChainEnvironment.apiToken)
    }

    @Test("A 403 that is not a quota refusal is also the credential")
    internal func forbiddenRefuses() {
        let outcome = ChainGate.classify(ChainError.api(statusCode: 403, message: "forbidden"))
        guard case .contradiction = outcome else {
            Issue.record("expected a contradiction, got \(outcome)")
            return
        }
    }

    // MARK: - Not reached

    @Test("A 403 that IS the provider's own quota refusal leaves the instance up")
    internal func quotaRefusalIsAnOutage() {
        // Asked before the status code is looked at. A quota refusal arrives
        // as a 403 and waiting fixes it, so treating it as a wrong credential
        // would send an operator to edit a token that is perfectly good.
        let outcome = ChainGate.classify(
            ChainError.api(statusCode: 403, message: "daily quota exceeded")
        )
        guard case .unreached = outcome else {
            Issue.record("expected unreached, got \(outcome)")
            return
        }
    }

    @Test("A node that never answers leaves the instance up and starting, naming chain (SEE-10.a)")
    internal func unreachableNodeLeavesItStarting() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(
                output: output,
                chain: StubChainSource(failure: ChainError.network("the node did not answer"))
            )
        ).run(settings: Fixture.settings())

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let answer = await instance.currentHealth()
        #expect(answer.statusCode == 503)
        // The waiting list, not a whole body frozen here: the change being
        // defined alongside this one appends a budget section to the same
        // body (RT-015, RT-032).
        #expect(answer.body.contains("\"status\":\"starting\""))
        #expect(answer.body.contains("\"waiting\":[\"chain\"]"))
        await instance.shutDown()
    }

    @Test("Turning the check off says so, and does not hold the instance at starting")
    internal func checkOffIsReported() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(
                output: output,
                chain: StubChainSource(failure: ChainError.network("nobody should ask"))
            )
        ).run(
            settings: Fixture.settings(
                extras: [ChainEnvironment.verifyAssetDecimals: "false"]
            )
        )

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let answer = await instance.currentHealth()
        #expect(answer.statusCode == 200)
        // 200 because the node is not a component of this instance at all,
        // which is not the same as 200 because a component nothing reached
        // was marked reached anyway. The difference is what
        // `componentNames(for:)` below is about.
        #expect(!answer.body.contains("chain"))
        let printed = await output.outText
        #expect(printed.contains("not probed at start"))
        await instance.shutDown()
    }

    @Test("A check that is off contributes no component rather than a component it faked")
    internal func checkOffContributesNoComponent() throws {
        // Requirement 18: a part that is off contributes no component and is
        // named in the startup report instead. Marking `chain` reached when
        // the operator turned the boot check off means `/health` answers 200
        // for an instance that has never exchanged a byte with the node,
        // which is the three hour incident the endpoint exists for.
        let on = try LoadedConfiguration.load(Fixture.settings())
        #expect(
            BootSequence.componentNames(for: on) == [HealthComponent.store, HealthComponent.chain]
        )
        let off = try LoadedConfiguration.load(
            Fixture.settings(extras: [ChainEnvironment.verifyAssetDecimals: "false"])
        )
        #expect(BootSequence.componentNames(for: off) == [HealthComponent.store])
    }

    // MARK: - The retry

    @Test("The retry backs off from five seconds to a fifteen minute ceiling and stays there")
    internal func retryBacksOffToACeiling() {
        // A node down overnight must not spend the day's budget on retries,
        // and a node that comes back must move the health answer without a
        // restart.
        var delay = ChainGate.nextRetryDelay(after: nil)
        #expect(delay == .seconds(5))
        delay = ChainGate.nextRetryDelay(after: delay)
        #expect(delay == .seconds(10))
        var steps = 0
        while delay < ChainGate.maximumRetryDelay, steps < 20 {
            delay = ChainGate.nextRetryDelay(after: delay)
            steps += 1
        }
        #expect(delay == .seconds(900))
        #expect(ChainGate.nextRetryDelay(after: delay) == .seconds(900))
    }
}
