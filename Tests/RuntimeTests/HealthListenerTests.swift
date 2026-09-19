import Chain
import Foundation
import Testing
@testable import Runtime

/// The one endpoint, and what a check on it means.
///
/// The incident this exists for ran for three hours: the process was up, the
/// port answered, the check said ok, every one of those was true and none of
/// them was useful. A check that comes back fine must never mean only that
/// something is listening (SEE-1, SEE-1.a).
@Suite("The health endpoint")
internal struct HealthListenerTests {

    // MARK: - What the answer means

    @Test("A bound socket with nothing reached reads as starting, and names what it waits for")
    internal func boundIsNotReady() async {
        let state = HealthState(componentNames: [HealthComponent.store, HealthComponent.chain])
        let answer = await state.answer()
        #expect(answer.statusCode == 503)
        // Pinned against what `ChainHealthReport` renders and against the one
        // fact this test is about, rather than against a whole literal frozen
        // here: the change being defined alongside this one appends a budget
        // section to the same body, and a frozen literal breaks the moment it
        // lands (RT-015, RT-032).
        #expect(answer.body == (await state.report()).jsonBody)
        #expect(answer.body.contains("\"status\":\"starting\""))
        #expect(answer.body.contains("\"waiting\":[\"store\",\"chain\"]"))
    }

    @Test("Everything enabled reached is 200, with the same body shape")
    internal func everythingReachedIsOk() async {
        let state = HealthState(componentNames: [HealthComponent.store, HealthComponent.chain])
        await state.markReached(HealthComponent.store)
        await state.markReached(HealthComponent.chain)
        let answer = await state.answer()
        #expect(answer.statusCode == 200)
        #expect(answer.body == (await state.report()).jsonBody)
        #expect(answer.body.contains("\"status\":\"ok\""))
        #expect(!answer.body.contains("waiting"))
    }

    @Test("An instance with nothing to wait for reads as ok (RT-016)")
    internal func nothingToWaitForIsOk() async {
        // A part that is off contributes no component. An off part reported
        // as unreached would hold the instance at `starting` for ever, so off
        // parts are named in the startup report instead.
        let state = HealthState(componentNames: [])
        let answer = await state.answer()
        #expect(answer.statusCode == 200)
        #expect(answer.body == (await state.report()).jsonBody)
        #expect(answer.body.contains("\"status\":\"ok\""))
    }

    @Test("The body is what Chain renders, not a second spelling of the same shape")
    internal func bodyIsChains() async {
        let state = HealthState(componentNames: ["chain"])
        let assembled = await state.report()
        let answer = await state.answer()
        // Pinned against what `ChainHealthReport` renders rather than against
        // a literal frozen here, because the change being defined alongside
        // this one appends a budget section to the same body (RT-032).
        #expect(answer.body == assembled.jsonBody)
        #expect(assembled.status == .starting)
    }

    // MARK: - Over a socket

    @Test("GET /health answers, and everything else is 404")
    internal func oneRouteAndOneOnly() async throws {
        let state = HealthState(componentNames: [])
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let health = try await Self.request("GET /health HTTP/1.1", to: bound)
        #expect(health.contains("HTTP/1.1 200 OK"))
        #expect(health.contains(await state.answer().body))

        let missing = try await Self.request("GET /metrics HTTP/1.1", to: bound)
        #expect(missing.contains("HTTP/1.1 404 Not Found"))

        let wrongMethod = try await Self.request("POST /health HTTP/1.1", to: bound)
        #expect(wrongMethod.contains("HTTP/1.1 404 Not Found"))
    }

    @Test("A query string is the same route, so a monitoring tool's cache buster still works")
    internal func queryStringIsTheSameRoute() async throws {
        let listener = HealthListener(state: HealthState(componentNames: []))
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let answered = try await Self.request("GET /health?t=1 HTTP/1.1", to: bound)
        #expect(answered.contains("HTTP/1.1 200 OK"))
    }

    @Test("A waiting instance answers 503 over the socket with the same body")
    internal func waitingAnswers503() async throws {
        let state = HealthState(componentNames: [HealthComponent.chain])
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let answered = try await Self.request("GET /health HTTP/1.1", to: bound)
        #expect(answered.contains("HTTP/1.1 503 Service Unavailable"))
        #expect(answered.contains("\"waiting\":[\"chain\"]"))
    }

    // MARK: - It costs nothing

    @Test("The endpoint answers with the day's request budget spent (SEE-1.b)")
    internal func answersWithTheBudgetSpent() async throws {
        // The moment somebody is actually looking at a health check is the
        // moment the budget has gone, so a check that needs a request is a
        // check that is not there when it is wanted.
        let governor = RequestGovernor(limit: 1)
        try await governor.reserveRequest(for: .system(job: "test"))
        await #expect(throws: (any Error).self) {
            try await governor.reserveRequest(for: .system(job: "test"))
        }
        let snapshot = await governor.snapshot()
        #expect(snapshot.isPaused)

        let state = HealthState(componentNames: [HealthComponent.store])
        await state.markReached(HealthComponent.store)
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let answered = try await Self.request("GET /health HTTP/1.1", to: bound)
        // 200, not 503. A spent budget is a fact for monitoring to alert on,
        // not a reason to take a serving instance out of rotation: the other
        // way round, a deploy gate rolls a working version back over a
        // provider quota (RUN-3).
        #expect(answered.contains("HTTP/1.1 200 OK"))
    }

    @Test("With proof headers configured and the cache stale, answering probes nothing")
    internal func answeringNeverProbes() async throws {
        // Not "an unset CHAIN_PROOF_HEADERS makes no request": that passes
        // already, because `proof(now:)` returns early when no header names
        // are configured, so a handler calling it on every request keeps such
        // a test green and reaches the network the first time an operator
        // configures headers and the cache expires. A test that cannot fail
        // the thing it is named for is worse than no test.
        let probe = CountingHeaderProbe()
        let cached = ProviderProofProbe(probe: probe, headerNames: ["x-served-by"], lifetime: 0)
        let found = await cached.proof(now: Date())
        #expect(found?.fields.first?.value == "edge-1")
        let afterRefresh = await probe.probes
        #expect(afterRefresh == 1)

        let state = HealthState(componentNames: [])
        await state.store(proof: found)
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        // The lifetime is zero, so the probe's cache is stale on every read.
        // Answering ten requests still costs nothing, because the handler
        // reads what the runtime already stored rather than going through
        // `proof(now:)`.
        for _ in 0..<10 {
            let answered = try await Self.request("GET /health HTTP/1.1", to: bound)
            #expect(answered.contains("x-served-by: edge-1"))
        }
        let afterTenRequests = await probe.probes
        #expect(afterTenRequests == 1)
    }

    // MARK: - Binding

    @Test("Port zero is accepted, so a test binds without choosing a number (HOST-6)")
    internal func portZeroIsAccepted() async throws {
        let listener = HealthListener(state: HealthState(componentNames: []))
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        #expect(bound.port > 0)
        await listener.stop()
    }

    @Test("Loopback is the default address, because the answer carries a waiting list")
    internal func loopbackIsTheDefault() throws {
        let settings = Fixture.settings(extras: [RuntimeEnvironment.healthAddress: nil])
        let runtime = try settings.read { try RuntimeSettings.load($0.lookup) }.value
        #expect(runtime.healthAddress == "127.0.0.1")
        #expect(runtime.healthAddress == RuntimeEnvironment.defaultHealthAddress)
    }

    @Test("An address this machine cannot bind is a configuration refusal, not an outage")
    internal func unusableAddressIsAConfigurationRefusal() async {
        let listener = HealthListener(state: HealthState(componentNames: []))
        await #expect(throws: HealthListenerError.addressUnusable(address: "not-an-address")) {
            _ = try await listener.bind(address: "not-an-address", port: 0)
        }
        #expect(HealthListenerError.addressUnusable(address: "x").exitCode == .configuration)
    }

    // MARK: - One slow client is not everybody's problem

    @Test("A client that connects and sends nothing does not hold up the endpoint")
    internal func aSilentClientDoesNotHoldUpTheEndpoint() async throws {
        // The read is bounded in seconds, and on the accept loop that bound
        // is what each silent connection costs everybody else: three of them
        // held the endpoint for six seconds, ten for twenty, which is past
        // any orchestrator's probe timeout, so a healthy container is
        // restarted for being busy reading nothing.
        let listener = HealthListener(state: HealthState(componentNames: []))
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        var silent: [Int32] = []
        for _ in 0..<3 {
            silent.append(try LoopbackClient.connectSilently(to: bound))
        }
        defer {
            for handle in silent {
                close(handle)
            }
            Task { await listener.stop() }
        }

        let started = ContinuousClock.now
        let answered = try await Self.request("GET /health HTTP/1.1", to: bound)
        let took = ContinuousClock.now - started
        #expect(answered.contains("HTTP/1.1 200 OK"))
        #expect(
            took < .seconds(1),
            "three silent connections delayed one health check by \(took)"
        )
    }

    @Test("A client that aborts before the answer is written leaves the endpoint answering")
    internal func anAbortedConnectionIsNotFatal() async throws {
        // Writing to a peer that has gone raises SIGPIPE, whose default
        // disposition kills the whole process: no report, no exit code from
        // the documented set, and off loopback an unauthenticated remote kill
        // from one TCP exchange. Any client that gives up rather than closing
        // politely does this: a probe that timed out, a scanner, a cancelled
        // request.
        //
        // The ignore is the host's job and the executable does it at its
        // first line, which `SettingsSourceTests` asserts; this process is
        // not that executable, so it does it here for itself and puts back
        // what it found. What is left to assert is this listener's half: the
        // write gives up on that one connection and the endpoint carries on.
        let previous = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previous) }

        let state = HealthState(componentNames: [])
        let listener = HealthListener(state: state)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        for _ in 0..<10 {
            try LoopbackClient.sendAndAbort("GET /health HTTP/1.1", to: bound)
            try await Task.sleep(for: .milliseconds(20))
        }
        let answered = try await Self.request("GET /health HTTP/1.1", to: bound)
        #expect(answered.contains("HTTP/1.1 200 OK"))
    }

    // MARK: - A listener that dies

    @Test("A loop that stops on its own hands over the reason")
    internal func deathIsHandedOver() async throws {
        // Not bound: the point is the wiring between a loop that has given up
        // and whoever has to act on it, and a real bind would leave a live
        // accept loop behind this test.
        let listener = HealthListener(state: HealthState(componentNames: []))
        let told = Recorded<HealthListenerDeath>()
        await listener.onDeath { death in await told.record(death) }
        await listener.noteLoopFinished(
            death: .acceptKeptFailing(times: 50, errorNumber: 24)
        )
        let arrived = await waitUntil { await told.value != nil }
        #expect(arrived)
        #expect(await told.value == .acceptKeptFailing(times: 50, errorNumber: 24))
        #expect(
            await told.value?.sentence.contains("50 times in a row") == true
        )
    }

    @Test("A reason that arrived before anybody was listening is still handed over")
    internal func deathBeforeTheHandlerIsNotLost() async throws {
        let listener = HealthListener(state: HealthState(componentNames: []))
        await listener.noteLoopFinished(death: .pollFailed(errorNumber: 9))
        let told = Recorded<HealthListenerDeath>()
        await listener.onDeath { death in await told.record(death) }
        #expect(await waitUntil { await told.value != nil })
        #expect(await told.value == .pollFailed(errorNumber: 9))
    }

    // MARK: - Private Methods

    /// One request over loopback, and the whole answer.
    private static func request(_ line: String, to bound: ListenerBound) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "health.test.client")
            queue.async {
                do {
                    continuation.resume(returning: try LoopbackClient.send(line, to: bound))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
