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

    /// The most callers whose shares are tracked at once.
    ///
    /// A constant rather than a setting, because it is a bound on this
    /// process's memory and not a policy anybody should have to think about.
    /// At the bound a caller nobody is tracking yet is refused rather than
    /// admitted untracked, and a caller part way through their allowance is
    /// never evicted to make room: an evicted caller comes back with a full
    /// allowance, which is the exploit. Reaching it at all means something is
    /// very wrong, and the day's budget is the backstop underneath it either
    /// way.
    public static let maxTrackedCallers = 10_000

    /// How often the table is swept of callers whose allowance has come back.
    ///
    /// Sweeping on every arrival would be quadratic in the number of callers,
    /// which is the sort of tidiness that becomes the outage. Once a minute
    /// keeps the table at roughly the callers currently drawing, and the hard
    /// ceiling above is what actually bounds it.
    internal static let allowanceSweepSeconds: TimeInterval = 60

    private var budget: DailyRequestBudget
    private var pauseEndsAt: Date?
    private var pauseCause: RequestBudgetSnapshot.PauseReason?
    private var didAnnouncePause = false
    private var recentNotices: [ChainNotice] = []

    private let store: (any RequestBudgetStore)?
    private let persistEvery: UInt64
    private var persistTask: Task<Void, Never>?

    private let shareRule: CallerShareRule?
    private var allowances: [String: CallerShare] = [:]
    private var shareDayStart: Date
    private var callerRequestsToday: UInt64 = 0
    private var callerRefusalsToday: UInt64 = 0
    private var didAnnounceTrackingFull = false
    private var nextAllowanceSweep = Date.distantPast

    // MARK: - Initializers

    /// - Parameters:
    ///   - limit: Requests per UTC day. Zero means no budget.
    ///   - persistEvery: How many requests pass between writes of the counter.
    ///   - store: Where the counter is written, so a restart does not hand the
    ///     process a fresh budget. Omitting it means the counter dies with
    ///     the process, which is only right in a test.
    ///   - share: What one member's caller may draw, or nil for no share at
    ///     all. Nil rather than a number here because the defaults belong to
    ///     ``ChainLimits``, where an operator can see them: this initialiser
    ///     is the low level one.
    ///   - now: Injected so a test pins the day.
    public init(
        limit: UInt64,
        persistEvery: UInt64 = 25,
        store: (any RequestBudgetStore)? = nil,
        share: CallerShareRule? = nil,
        now: Date = Date()
    ) {
        self.budget = DailyRequestBudget(limit: limit, now: now)
        self.persistEvery = max(persistEvery, 1)
        self.store = store
        self.shareRule = limit > 0 ? share : nil
        self.shareDayStart = UTCDay.start(of: now)
    }

    /// - Parameters:
    ///   - limits: Takes the configured budget, write interval and share.
    ///   - store: Where the counter is written.
    ///   - now: Injected so a test pins the day.
    public init(limits: ChainLimits, store: (any RequestBudgetStore)? = nil, now: Date = Date()) {
        self.init(
            limit: limits.dailyRequestBudget,
            persistEvery: limits.budgetPersistEvery,
            store: store,
            share: limits.callerShare,
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

    /// Spends one request from today's budget, on behalf of somebody named.
    ///
    /// Throws **before** the request leaves, so the process throttles itself
    /// rather than finding out about the ceiling by being cut off part way
    /// through a sweep.
    ///
    /// - Parameters:
    ///   - caller: Who this is for. There is no default: a host that forgot
    ///     would get the unrationed path in silence, which is the share
    ///     bypassed by an omission.
    ///   - now: Injected so a test pins the day.
    public func reserveRequest(for caller: RequestCaller, now: Date = Date()) throws {
        try spend(1, for: caller, now: now)
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
    /// A member's caller is held to the same all-or-nothing rule against their
    /// own share: the whole count out of what they have left, or nothing. A
    /// member cannot order an indivisible job larger than their burst, and
    /// that is ``ChainError/callerShareCannotCover`` rather than a refusal
    /// naming an instant, because no amount of waiting makes it fit.
    ///
    /// - Parameters:
    ///   - count: Requests to take. Zero takes nothing and reports nothing.
    ///   - caller: Who this is for. There is no default.
    ///   - now: Injected so a test pins the day.
    public func reserveRequests(
        _ count: UInt64,
        for caller: RequestCaller,
        now: Date = Date()
    ) throws {
        try spend(count, for: caller, now: now)
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
    ///
    /// **It returns no part of the day, and no part of anybody's share**
    /// (RUN-10.a). Whatever tripped the pause, however many times the pause is
    /// lifted, the day's count, what is left of it, the configured limit, the
    /// start of the day and every caller's allowance are exactly where they
    /// were, and nothing is written to the store: an unpause that lowered the
    /// count on disk would let a repeated unpause walk the persisted figure
    /// downward. Giving a caller their share back here is the plausible and
    /// wrong thing for the next person to write, which is why the suite
    /// asserts against it rather than trusting this sentence.
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
    ///
    /// Costs nothing and works while paused, which is what lets a health
    /// answer be assembled at the moment the day's budget is gone (SEE-1.b).
    /// It reads the share figures as well, so an operator can see that
    /// throttling is happening from the same value every other budget figure
    /// comes from (SEE-9).
    public func snapshot(now: Date = Date()) -> RequestBudgetSnapshot {
        let until = pausedUntil(now: now)
        // Every day-scoped figure answers for the day `now` falls in, the way
        // `remainingRequests(now:)` already does, rather than for the day the
        // counters were last touched. Nothing rolls them until the day's first
        // reservation, and the gap is widest in exactly the case this answer
        // is read in: yesterday's budget was spent, so nothing is reserving,
        // so nothing rolls, and a monitoring check reading a fresh whole
        // budget would be told it was gone (SEE-1.b, SEE-9).
        let isToday = UTCDay.start(of: now) == shareDayStart
        return RequestBudgetSnapshot(
            usedRequests: budget.used(at: now),
            limit: budget.limit,
            remainingRequests: budget.remaining(at: now) ?? 0,
            pausedUntil: until,
            pauseReason: until == nil ? nil : pauseCause,
            dayStart: budget.dayStart(at: now),
            callerShareBurst: shareRule?.burstRequests ?? 0,
            // Counted rather than reported as the table's size, because an
            // entry whose allowance has refilled is a caller nobody is holding
            // and it may not have been swept yet.
            throttledCallers: allowances.values.filter { !$0.isFull(at: now) }.count,
            callerRequestsToday: isToday ? callerRequestsToday : 0,
            callerRefusalsToday: isToday ? callerRefusalsToday : 0
        )
    }

    // MARK: - Internal Methods

    /// How many callers this process is holding an allowance for, swept or
    /// not.
    ///
    /// For the suite that proves the table is bounded in memory rather than
    /// merely reported as small. Not public: the number a host reports is
    /// ``RequestBudgetSnapshot/throttledCallers``, which counts the callers
    /// actually drawing.
    internal func trackedCallerCount() -> Int {
        allowances.count
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
    private func spend(_ count: UInt64, for caller: RequestCaller, now: Date) throws {
        // The pause comes first, so an instance that is refusing everybody
        // tells everybody the same story rather than telling one member their
        // share is spent when the truth is that nothing is working (SEE-11).
        try throwIfPaused(now: now)
        rollCallerDayIfNeeded(now: now)
        if let key = caller.shareKey {
            try takeFromShare(key: key, count: count, now: now)
        }
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
            // Counted here rather than beside the share, so this figure is a
            // part of `usedRequests` and not a separate tally that can
            // disagree with it: a member's caller that the day's budget then
            // refused spent their share and none of the day.
            if caller.isRationed {
                let (sum, overflow) = callerRequestsToday.addingReportingOverflow(count)
                callerRequestsToday = overflow ? UInt64.max : sum
            }
        }
    }

    /// Takes `count` from one caller's share, or refuses having taken nothing.
    ///
    /// A refusal here spends nothing of the day, trips no breaker, pauses
    /// nothing and writes no notice: the rest of the day belongs to everybody
    /// else, and one member refused thousands of times must not push the pause
    /// announcement out of the buffer an operator reads when things are
    /// already bad (RUN-11, SEE-5).
    ///
    /// A member whose reservation is then refused by the day's budget keeps
    /// the charge against their share. There is no way to hand a reservation
    /// back anywhere in this actor, deliberately: an allowance that can be
    /// returned is one two callers can each believe they hold, and the return
    /// is the write a crash skips.
    private func takeFromShare(key: String, count: UInt64, now: Date) throws {
        guard let shareRule, count > 0 else { return }

        // An allowance never holds more than its burst, so this one cannot be
        // served at any instant. Refused here with its own case rather than
        // below with an instant taken from a refilling allowance, which would
        // be the moment the burst comes back and would refuse the same job
        // again on arrival, forever.
        guard count <= shareRule.burstRequests else {
            callerRefusalsToday += 1
            throw ChainError.callerShareCannotCover(requested: count, burst: shareRule.burstRequests)
        }

        var allowance: CallerShare
        if let held = allowances[key] {
            allowance = held
        } else {
            // A new caller is the moment the table is swept of callers whose
            // allowance has come all the way back. A full allowance is
            // indistinguishable from one nobody has heard of, so forgetting
            // them hands them nothing and keeps the table to roughly the
            // callers currently drawing.
            if now >= nextAllowanceSweep {
                forgetFullAllowances(now: now)
                nextAllowanceSweep = now.addingTimeInterval(Self.allowanceSweepSeconds)
            }
            guard allowances.count < Self.maxTrackedCallers else {
                announceTrackingFull(now: now)
                callerRefusalsToday += 1
                // Refused as though their share were spent, which is the
                // honest thing to tell a member: the answer to "when may I
                // read?" is the same, and admitting them untracked is the hole
                // this exists to close.
                //
                // The instant is the next sweep, not the next midnight. A slot
                // comes free as soon as any tracked caller has refilled, which
                // the sweep notices within a minute, and telling a member to
                // come back in fifteen hours is the lockout a refilling
                // allowance exists to avoid.
                throw ChainError.callerShareSpent(
                    requested: count,
                    shareRemaining: 0,
                    nextAllowedAt: now.addingTimeInterval(Self.allowanceSweepSeconds)
                )
            }
            allowance = shareRule.freshAllowance(at: now)
        }

        guard allowance.take(count, at: now) else {
            // Kept rather than dropped, so the refusal does not forget how
            // much has refilled and hand the caller a fresh burst by being
            // asked twice.
            allowances[key] = allowance
            callerRefusalsToday += 1
            throw ChainError.callerShareSpent(
                requested: count,
                shareRemaining: allowance.remaining(at: now),
                nextAllowedAt: allowance.nextAllowed(for: count, at: now)
            )
        }
        allowances[key] = allowance
    }

    /// Drops the callers whose allowance has come all the way back.
    private func forgetFullAllowances(now: Date) {
        allowances = allowances.filter { !$0.value.isFull(at: now) }
    }

    /// Starts the share figures again when the UTC day turns.
    ///
    /// The allowances themselves are **not** cleared wholesale: a caller who
    /// was empty a second before midnight has not earned a fresh burst a
    /// second after it, and refilling is what gives their share back. Only the
    /// ones that are full anyway are forgotten, which changes nothing for
    /// anybody and keeps the table from carrying yesterday.
    private func rollCallerDayIfNeeded(now: Date) {
        let start = UTCDay.start(of: now)
        guard start != shareDayStart else { return }
        shareDayStart = start
        callerRequestsToday = 0
        callerRefusalsToday = 0
        didAnnounceTrackingFull = false
        forgetFullAllowances(now: now)
        nextAllowanceSweep = now.addingTimeInterval(Self.allowanceSweepSeconds)
    }

    /// One notice a day when the tracking table is full, not one per refusal.
    private func announceTrackingFull(now: Date) {
        guard !didAnnounceTrackingFull else { return }
        didAnnounceTrackingFull = true
        record(
            ChainNotice(
                kind: .callerTrackingFull(tracked: allowances.count),
                at: now,
                message: "\(ChainFormatting.grouped(UInt64(allowances.count))) callers are drawing on "
                    + "their share of today's requests at once, which is as many as this process "
                    + "tracks, so a caller it is not already tracking is being refused rather than "
                    + "let through unmeasured. The day's budget is still the backstop."
            )
        )
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
