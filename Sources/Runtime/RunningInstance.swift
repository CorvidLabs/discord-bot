import Chain
import Foundation
import Store

/// A process that walked the gates and is up.
///
/// Holds the pieces that have to be let go of in the right order when the
/// process stops: the listener gives the port back, the store's close
/// releases the lease that keeps a second instance out, and only then is the
/// exit clean (RT-028, SEE-8).
public actor RunningInstance {

    // MARK: - Properties

    /// The address and port actually bound.
    public nonisolated let listener: ListenerBound

    /// The gates that ran, in the order they ran.
    ///
    /// Recorded rather than declared, so a test asserts what happened rather
    /// than what a constant says happened.
    public nonisolated let gatesPassed: [BootGate]

    /// The report this start wrote.
    public nonisolated let report: StartupReport

    private let health: HealthState
    private let listenerSocket: HealthListener
    private let store: any BotStore
    private let governor: RequestGovernor
    private let output: any RuntimeOutput
    private var background: [Task<Void, Never>]
    private var stopped = false
    private var stopCode: ExitCode = .ok
    private var waiting: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    /// - Parameters:
    ///   - listener: What the bind produced.
    ///   - gatesPassed: The gates that ran, in order.
    ///   - report: What this start printed.
    ///   - health: What the endpoint answers from.
    ///   - listenerSocket: The socket, so it can be given back.
    ///   - store: What this instance remembers, so its lease can be released.
    ///   - governor: The one request governor, so what it has spent today can
    ///     be read and so its last write lands before the store closes.
    ///   - output: Where a failure that arrives after the boot is written.
    ///   - background: Work started after the gates, cancelled on the way out.
    internal init(
        listener: ListenerBound,
        gatesPassed: [BootGate],
        report: StartupReport,
        health: HealthState,
        listenerSocket: HealthListener,
        store: any BotStore,
        governor: RequestGovernor,
        output: any RuntimeOutput,
        background: [Task<Void, Never>]
    ) {
        self.listener = listener
        self.gatesPassed = gatesPassed
        self.report = report
        self.health = health
        self.listenerSocket = listenerSocket
        self.store = store
        self.governor = governor
        self.output = output
        self.background = background
    }

    // MARK: - Public Methods

    /// What the health endpoint would answer right now.
    ///
    /// Reads state already in memory and makes no request, which is what lets
    /// a check answer with the day's budget spent (SEE-1.b).
    public func currentHealth() async -> HealthAnswer {
        await health.answer()
    }

    /// What this process has spent of today's request budget.
    ///
    /// Read from the one governor every caller shares, so the number is the
    /// whole process rather than one path through it (RUN-8).
    public func requestBudget() async -> RequestBudgetSnapshot {
        await governor.snapshot()
    }

    /// What the process should exit with once this instance has stopped.
    ///
    /// Zero for a signal, which is the ordinary way out. Something else when
    /// the instance stopped because a part of it failed, so a supervisor
    /// starts a replacement rather than recording a clean exit.
    public func exitCode() -> ExitCode {
        stopCode
    }

    /// Returns when the instance has been stopped.
    public func waitUntilStopped() async {
        if stopped { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    /// Stops the listener, closes the store and releases the lease.
    ///
    /// Safe to call more than once, because a second signal arriving while
    /// the first is still unwinding is the ordinary case.
    public func shutDown() async {
        guard !stopped else { return }
        stopped = true
        for task in background {
            task.cancel()
        }
        let running = background
        background = []
        // Awaited, not only cancelled. A retry task still in flight holds the
        // governor, which holds the store that is about to be closed, and a
        // statement prepared against a closed connection is undefined
        // behaviour on a SQLite built without its argument checks.
        for task in running {
            await task.value
        }
        await listenerSocket.stop()
        // The day's counter is written every so many requests, from a task of
        // the governor's own. Waiting for it here is what stops the last
        // write of the day landing after the connection has gone (RUN-8.b).
        await governor.flushPersistence()
        await store.close()
        let resuming = waiting
        waiting = []
        for continuation in resuming {
            continuation.resume()
        }
    }

    // MARK: - Internal Methods

    /// Stops the instance because its health endpoint has died.
    ///
    /// **It stops rather than rebinding.** An endpoint that answers nothing
    /// for the rest of the process's life is not a degraded instance: nothing
    /// watching can tell it from a healthy one, and this process goes on
    /// holding the store's lease, so the replacement somebody starts is
    /// refused as a duplicate. Unwinding properly and exiting non-zero is
    /// what lets a supervisor bring a working one up (RUN-7.a, SEE-8).
    ///
    /// - Parameter death: Why the listener stopped.
    internal func listenerDied(_ death: HealthListenerDeath) async {
        guard !stopped else { return }
        await output.writeError([
            "The health endpoint has died: \(death.sentence).",
            "  Nothing can check this instance any more, so it is stopping and giving the "
                + "store's lease back. Start a replacement."
        ])
        stopCode = .internalError
        await shutDown()
    }
}
