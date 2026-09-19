import Foundation
import Testing
@testable import Runtime

/// The rule that cannot be softened: nothing identifies before the listener
/// is bound.
///
/// A second instance that identified before discovering it was a duplicate
/// takes the live instance's session away, because the gateway answers a
/// duplicate identify by invalidating the session, and then dies a moment
/// later on the bind. Under a supervisor that restarts it, the healthy
/// instance is knocked offline every time the doomed one boots and neither
/// keeps a session (RUN-7, RUN-7.a, RUN-3).
@Suite("Bind before identify")
internal struct BindBeforeIdentifyTests {

    // MARK: - The order that happened

    @Test("Connect is not called before the bind, and is handed what the bind produced")
    internal func connectComesAfterTheBind() async throws {
        let chat = SpyChatGateway()
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output, chat: chat))
            .run(settings: Fixture.settings())

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let bindIndex = try #require(instance.gatesPassed.firstIndex(of: .bind))
        let chatIndex = try #require(instance.gatesPassed.firstIndex(of: .chat))
        #expect(bindIndex < chatIndex)

        let calls = await chat.calls
        #expect(calls == ["connect"])
        let handed = await chat.boundWhenConnected
        #expect(handed == instance.listener)
        #expect(handed?.port == instance.listener.port)
        await instance.shutDown()
    }

    @Test("The bind reports the port actually obtained, not the one that was asked for")
    internal func portZeroReportsWhatItGot() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings(port: "0"))

        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        #expect(instance.listener.port != 0)
        #expect(instance.listener.address == "127.0.0.1")
        let printed = await output.outText
        #expect(printed.contains("http://127.0.0.1:\(instance.listener.port)/health"))
        await instance.shutDown()
    }

    // MARK: - The order that does not compile

    @Test("Proof of a bind is the only way to connect, and only a bind can make one")
    internal func onlyABindCanMakeTheProof() async throws {
        // What this asserts by existing rather than by running: the only
        // initialiser of `ListenerBound` is internal to `Runtime`, so a chat
        // adapter in another target can hold one and cannot make one, and
        //
        //     try await chat.connect(afterBinding: ListenerBound(...))
        //
        // does not compile outside this module. What the trick proves is that
        // a bound listener exists when connect is called; it does not prove
        // the bind happened first in time, because nothing stops a caller
        // holding a value from an earlier bind. What closes that gap is that
        // this module makes exactly one, at the gate before the chat gate,
        // which the test above asserts by watching the order.
        let state = HealthState(componentNames: [])
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        #expect(bound.port != 0)

        let chat = SpyChatGateway()
        try await chat.connect(afterBinding: bound)
        let handed = await chat.boundWhenConnected
        #expect(handed == bound)
        await listener.stop()
    }

    @Test("A second bind of the same port is refused, using the port the first one got")
    internal func secondBindIsRefused() async throws {
        let first = HealthListener(state: HealthState(componentNames: []))
        let bound = try await first.bind(address: "127.0.0.1", port: 0)
        defer { Task { await first.stop() } }

        let second = HealthListener(state: HealthState(componentNames: []))
        await #expect(throws: HealthListenerError.addressInUse(address: "127.0.0.1", port: bound.port)) {
            _ = try await second.bind(address: "127.0.0.1", port: bound.port)
        }
    }

    @Test("A port already in use stops the boot with the unavailable code, naming the variable")
    internal func portInUseStopsTheBoot() async throws {
        let holder = HealthListener(state: HealthState(componentNames: []))
        let bound = try await holder.bind(address: "127.0.0.1", port: 0)
        defer { Task { await holder.stop() } }

        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings(port: String(bound.port)))

        let failure = try #require(outcome.failure)
        #expect(failure.variable == RuntimeEnvironment.healthPort)
        #expect(failure.code == .unavailable)
        #expect(failure.summary.contains(String(bound.port)))
    }
}
