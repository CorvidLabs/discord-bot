import Foundation

/// The single daily ceiling on requests, shared by every caller.
///
/// Reading balances and signing transactions hold their own client. Before this
/// actor each counted separately, and in practice only the read path counted at
/// all, so the configured number was not the number of requests the process
/// could make, and a provider's refusal met while paying somebody did not slow
/// down the loop reading everybody's balances. One counter and one breaker for
/// both paths is the only version of this an operator can reason about.
///
/// It refuses rather than queues. Work that waits for the budget to come back
/// is work that lands hours later, when the thing that asked for it has gone.
public actor RequestGovernor {

    // MARK: - Properties

    /// How many notices are kept for a host that has not drained them. Enough
    /// that an overnight incident is still readable, bounded so a process that
    /// never drains cannot grow without limit.
    public static let maxRetainedNotices = 50

    private var budget: DailyRequestBudget
    private var pauseEndsAt: Date?
    private var pauseCause: RequestBudgetSnapshot.PauseReason?
    private var didAnnouncePause = false
    private var recentNotices: [ChainNotice] = []

    private let store: (any RequestBudgetStore)?
    private let persistEvery: UInt64
    private var persistTask: Task<Void, Never>?

    // MARK: - Initializers

    /// - Parameters:
    ///   - limit: Requests per UTC day. Zero means no budget.
    ///   - persistEvery: How many requests pass between writes of the counter.
    ///   - store: Where the counter is written, so a restart does not hand the
    ///     process a fresh budget. Omitting it means the counter dies with
    ///     the process, which is only right in a test.
    ///   - now: Injected so a test pins the day.
    public init(
        limit: UInt64,
        persistEvery: UInt64 = 25,
        store: (any RequestBudgetStore)? = nil,
        now: Date = Date()
    ) {
        self.budget = DailyRequestBudget(limit: limit, now: now)
        self.persistEvery = max(persistEvery, 1)
        self.store = store
    }

    /// - Parameters:
    ///   - limits: Takes the configured budget and write interval.
    ///   - store: Where the counter is written.
    ///   - now: Injected so a test pins the day.
    public init(limits: ChainLimits, store: (any RequestBudgetStore)? = nil, now: Date = Date()) {
        self.init(
            limit: limits.dailyRequestBudget,
            persistEvery: limits.budgetPersistEvery,
            store: store,
            now: now
        )
    }

    // MARK: - Public Methods

    /// Applies a counter written earlier in the same UTC day.
    ///
    /// Called once at boot, before anything reads the chain. An unreadable row
    /// throws: refusing to start is better than starting with a budget
    /// nobody granted.
    /// - Returns: Whether a counter was found and applied.
    @discardableResult
    public func restoreFromStore(now: Date = Date()) async throws -> Bool {
        guard let store else { return false }
        guard let usage = try await store.loadBudgetUsage() else { return false }
        return budget.restore(used: usage.usedRequests, dayStart: usage.dayStart, now: now)
    }

    /// Spends one request from today's budget.
    ///
    /// Throws **before** the request leaves, so the process throttles itself
    /// rather than finding out about the ceiling by being cut off part way
    /// through a sweep.
    public func reserveRequest(now: Date = Date()) throws {
        try spend(1, now: now)
    }

    /// Spends `count` requests from today's budget, all of them or none.
    ///
    /// For a consumer whose work cannot be half done. The budget is shared, and
    /// its two consumers are not alike: a sweep of everybody's roles reads one
    /// account at a time and can stop anywhere, while a payout run either pays
    /// the whole list or should never have started. The payout's own spending
    /// limits are checked up front for exactly that reason, and then the day's
    /// requests, the one resource nobody reserved, ran out in the middle
    /// instead. The errors that arrive then are not the payout's own refusal,
    /// so every claim is correctly kept, the epoch under-pays and it closes
    /// nothing: the half-finished payout the design exists to prevent, arriving
    /// through the side door.
    ///
    /// Not fitting is **not** a pause. ``ChainError/requestBudgetCannotCover``
    /// leaves the counter untouched and the breaker open, because what is left
    /// of the day is still useful to everything that reads a request at a time.
    /// Only a day with nothing at all left pauses, exactly as one request would.
    ///
    /// There is no way to give a reservation back. A budget that can be handed
    /// back is one two consumers can each believe they hold, and the handing
    /// back is the write a crash skips. Reserve from a figure the work itself
    /// produced, and treat the difference as a day under-used.
    ///
    /// Nothing in `Reserve` calls this, and nothing in it can: that module
    /// depends on Foundation alone, which is what keeps its arithmetic testable
    /// with no network in the package. **The host joins the two.** Before
    /// calling the runner it rehearses the epoch, multiplies the entries by the
    /// requests one payment costs it, adds what reading eligibility cost, and
    /// reserves that here. A refusal is reported and the epoch is not started;
    /// the ledger is untouched, so the same epoch runs later in the day or
    /// tomorrow with nobody paid twice.
    ///
    /// - Parameters:
    ///   - count: Requests to take. Zero takes nothing and reports nothing.
    ///   - now: Injected so a test pins the day.
    public func reserveRequests(_ count: UInt64, now: Date = Date()) throws {
        try spend(count, now: now)
    }

    /// Requests left today, or nil when no budget is set.
    ///
    /// Nil rather than zero, because a caller sizing an all-or-nothing job has
    /// to tell "there is no ceiling" from "there is no room", and the zero on
    /// ``RequestBudgetSnapshot/remainingRequests`` cannot.
    ///
    /// It reports the counter, not the breaker. Work can be paused with the
    /// day's budget barely touched, so a caller that means "may I read?" asks
    /// ``pausedUntil(now:)`` as well, or simply reserves and handles the throw.
    public func remainingRequests(now: Date = Date()) -> UInt64? {
        budget.remaining(at: now)
    }

    /// Trips the breaker when `error` is the provider's own quota refusal.
    ///
    /// - Returns: The error to throw. A caller that has already sent a request
    ///   reports the pause rather than the raw refusal, so every surface says
    ///   the same thing about why nothing is working.
    public func recordRequestFailure(_ error: any Error, now: Date = Date()) -> any Error {
        guard ChainError.isProviderQuotaRefusal(error) else { return error }
        let until = UTCDay.nextMidnight(after: now)
        pause(
            until: until,
            cause: .providerRefusedQuota,
            at: now,
            kind: .providerRefusedQuota(until: until),
            message: "The node's provider refused: its own quota is spent. Asking again before the day "
                + "rolls over achieves nothing."
        )
        return ChainError.providerRefusedQuota(until: until)
    }

    /// Lifts a pause by hand.
    ///
    /// For a refusal that turned out to be a revoked token, an address block or
    /// a misread: without this the only way back was a restart, which also
    /// zeroed the counter and so quietly granted a second day's budget. The budget
    /// itself is untouched, so a day whose budget really is spent pauses again
    /// on the next request.
    /// - Returns: Whether anything was actually paused.
    @discardableResult
    public func unpause(now: Date = Date()) -> Bool {
        guard let until = pauseEndsAt, now < until else {
            pauseEndsAt = nil
            pauseCause = nil
            didAnnouncePause = false
            return false
        }
        pauseEndsAt = nil
        pauseCause = nil
        didAnnouncePause = false
        record(
            ChainNotice(
                kind: .pauseLiftedByHand(wouldHaveEndedAt: until),
                at: now,
                message: "A pause due to end at \(UTCDay.stamp(until)) UTC was lifted by hand. Reads and "
                    + "signing resume. If the provider is still refusing, the next request pauses again."
            )
        )
        return true
    }

    /// When the current pause ends, or nil when requests are allowed.
    public func pausedUntil(now: Date = Date()) -> Date? {
        guard let until = pauseEndsAt, now < until else { return nil }
        return until
    }

    /// Everything a status surface needs, in one value.
    public func snapshot(now: Date = Date()) -> RequestBudgetSnapshot {
        let until = pausedUntil(now: now)
        return RequestBudgetSnapshot(
            usedRequests: budget.used,
            limit: budget.limit,
            remainingRequests: budget.remaining,
            pausedUntil: until,
            pauseReason: until == nil ? nil : pauseCause,
            dayStart: budget.dayStart
        )
    }

    /// The notices kept so far, oldest first, leaving them in place.
    public func notices() -> [ChainNotice] {
        recentNotices
    }

    /// The notices kept so far, oldest first, and forgets them.
    public func drainNotices() -> [ChainNotice] {
        let drained = recentNotices
        recentNotices = []
        return drained
    }

    /// Waits for every write scheduled so far to finish. Tests wait on this,
    /// and so should a host shutting down deliberately.
    public func flushPersistence() async {
        await persistTask?.value
    }

    // MARK: - Private Methods

    /// The one path every reservation takes, whatever size it is.
    ///
    /// One path rather than two, so the pause, the threshold notice and the
    /// write of the counter cannot come to mean different things depending on
    /// how many requests a caller asked for at once.
    private func spend(_ count: UInt64, now: Date) throws {
        try throwIfPaused(now: now)
        switch budget.reserve(count: count, now: now) {
        case .exhausted(let until):
            schedulePersist()
            pause(
                until: until,
                cause: .budgetSpent,
                at: now,
                kind: .budgetSpent(until: until),
                message: "The daily request budget of \(ChainFormatting.grouped(budget.limit)) requests is "
                    + "spent. Raise \(ChainEnvironment.dailyRequestBudget), or read the chain less often."
            )
            throw ChainError.requestBudgetSpent(until: until)
        case .notEnoughBudget(let requested, let remaining):
            // No notice. This refusal is answered to its caller there and then,
            // and it is the one a scheduled run repeats every time it retries;
            // a notice per retry would push the pause announcement out of a
            // buffer an operator reads precisely when things are already bad.
            throw ChainError.requestBudgetCannotCover(requested: requested, remaining: remaining)
        case .allowed(let used, let limit, let crossedThreshold):
            if let threshold = crossedThreshold {
                record(
                    ChainNotice(
                        kind: .budgetThresholdCrossed(percent: threshold, used: used, limit: limit),
                        at: now,
                        message: "\(threshold)% of today's request budget is gone "
                            + "(\(ChainFormatting.grouped(used)) of \(ChainFormatting.grouped(limit)) requests)."
                    )
                )
            }
            // A reservation of many requests can leap clean over the write
            // interval without ever landing on a multiple of it, so it is
            // written down at once instead.
            if count > 1 || (count == 1 && used % persistEvery == 0) {
                schedulePersist()
            }
        }
    }

    private func throwIfPaused(now: Date) throws {
        guard let until = pauseEndsAt else { return }
        if now < until {
            switch pauseCause {
            case .providerRefusedQuota:
                throw ChainError.providerRefusedQuota(until: until)
            case .budgetSpent, .none:
                throw ChainError.requestBudgetSpent(until: until)
            }
        }
        pauseEndsAt = nil
        pauseCause = nil
        didAnnouncePause = false
    }

    /// One notice per pause, not one per refused request.
    ///
    /// A pause refuses everything for the rest of the day, so announcing it on
    /// every refusal would bury the announcement under thousands of copies of
    /// itself at exactly the moment somebody is trying to read it.
    private func pause(
        until: Date,
        cause: RequestBudgetSnapshot.PauseReason,
        at now: Date,
        kind: ChainNotice.Kind,
        message: String
    ) {
        pauseEndsAt = until
        pauseCause = cause
        guard !didAnnouncePause else { return }
        didAnnouncePause = true
        record(
            ChainNotice(
                kind: kind,
                at: now,
                message: message + " Reads and signing are paused until \(UTCDay.stamp(until)) UTC: roles "
                    + "will not change and anything that has to read the chain or sign will refuse. Work "
                    + "already sent is unaffected."
            )
        )
    }

    private func record(_ notice: ChainNotice) {
        recentNotices.append(notice)
        if recentNotices.count > Self.maxRetainedNotices {
            recentNotices.removeFirst(recentNotices.count - Self.maxRetainedNotices)
        }
    }

    /// Writes the counter, serialised behind whatever write is already going.
    ///
    /// Serialised so a later snapshot cannot land before an earlier one and
    /// leave a smaller number on disk than the process has really spent.
    private func schedulePersist() {
        guard let store else { return }
        let usage = RequestBudgetUsage(usedRequests: budget.used, dayStart: budget.dayStart)
        let previous = persistTask
        persistTask = Task { [weak self] in
            await previous?.value
            do {
                try await store.saveBudgetUsage(usage)
            } catch {
                await self?.record(
                    ChainNotice(
                        kind: .budgetNotPersisted(reason: error.localizedDescription),
                        at: Date(),
                        message: "Today's request count could not be written down "
                            + "(\(error.localizedDescription)). A restart would start the day again from "
                            + "the last count that was written."
                    )
                )
            }
        }
    }
}
