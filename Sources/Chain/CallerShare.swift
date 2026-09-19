import Foundation

/// How big one caller's share of the day is, and how fast it comes back.
///
/// Derived from two settings rather than being one, and both are needed.
///
/// **A percentage rather than a count**, because a project-neutral bot is
/// pointed at free tiers and paid tiers whose budgets differ by orders of
/// magnitude, and one absolute number is wrong at one end or the other.
///
/// **A burst alongside it**, because "however fast they type" is a rate
/// problem. A pure daily quota lets a member empty their share in ten seconds
/// and then locks them out for the rest of the day, which reads to the member
/// as the bot being broken. A refilling allowance spends the same share over
/// the day and is never more than a burst ahead of itself.
///
/// Pure and with no clock in it, so every boundary below is exercised by a
/// test that finishes instantly.
public struct CallerShareRule: Sendable, Equatable {

    // MARK: - Properties

    /// Requests one caller may take across a whole UTC day.
    public let dailyShareRequests: UInt64

    /// The most one caller may take before their allowance has to refill.
    ///
    /// Clamped to ``dailyShareRequests`` rather than refused, because a burst
    /// larger than the whole day's share is a setting that means "as much as I
    /// am allowed" rather than a mistake worth stopping a boot for. The
    /// effective figure is what a status surface reports, so the clamp is
    /// visible rather than silent.
    public let burstRequests: UInt64

    /// Requests that come back per second, spread over a UTC day.
    public var refillPerSecond: Double {
        Double(dailyShareRequests) / 86_400
    }

    // MARK: - Initializers

    /// The share a percentage of a day's budget works out to, or nil when
    /// there is no share at all.
    ///
    /// Nil when no daily budget is set, because the criterion is about
    /// spending the day's budget for reading the chain and there is no day's
    /// budget to take a part of, and nil when the percentage is zero, which is
    /// how every other zero in this layer means off.
    ///
    /// A percentage of a small budget can work out to nothing, and a share of
    /// nothing would refuse every member every time. The day's share is
    /// therefore held at one request rather than zero: the day's own budget is
    /// still the backstop, and a bot that refuses every member on a small
    /// budget is a bot nobody keeps running.
    ///
    /// - Parameters:
    ///   - dailyRequestBudget: The day's budget. Zero means no share.
    ///   - percent: The share of it one caller may draw. Zero means no share.
    ///     Never above a hundred: ``ChainLimits`` refuses that at boot, where
    ///     an operator can read the refusal, and holds it there for a caller
    ///     building one in Swift. Above a hundred the multiplication below can
    ///     overflow, which is why it is stopped there rather than clamped
    ///     silently here.
    ///   - burstRequests: The most one caller may hold at once.
    public init?(dailyRequestBudget: UInt64, percent: Int, burstRequests: UInt64) {
        guard dailyRequestBudget > 0, percent > 0, burstRequests > 0 else { return nil }
        let share = dailyRequestBudget / 100 * UInt64(percent)
            + dailyRequestBudget % 100 * UInt64(percent) / 100
        self.dailyShareRequests = Swift.max(share, 1)
        self.burstRequests = Swift.max(Swift.min(burstRequests, self.dailyShareRequests), 1)
    }

    // MARK: - Public Methods

    /// A caller nobody is tracking yet, with their whole burst in hand.
    ///
    /// Full rather than empty, because a member who has made no requests today
    /// has spent nothing, and because a caller the table has forgotten has to
    /// be indistinguishable from one it has never heard of or forgetting them
    /// would be a punishment.
    public func freshAllowance(at now: Date) -> CallerShare {
        CallerShare(rule: self, at: now)
    }
}

/// One caller's allowance, refilling as the day passes.
///
/// Held in memory and never written down. The cost of that is stated rather
/// than hidden: a restart hands a caller at most one fresh burst. What it buys
/// is a table and a migration not existing, and a database write not sitting
/// in front of every read of the chain. The day's own count **is** persisted,
/// so no restart trick creates requests out of nothing.
public struct CallerShare: Sendable, Equatable {

    // MARK: - Properties

    /// How big the share is and how fast it comes back.
    public let rule: CallerShareRule

    private var available: Double
    private var updatedAt: Date

    // MARK: - Initializers

    /// A full allowance, as at `now`.
    public init(rule: CallerShareRule, at now: Date) {
        self.rule = rule
        self.available = Double(rule.burstRequests)
        self.updatedAt = now
    }

    // MARK: - Public Methods

    /// Requests this caller could take right now, rounded down.
    public func remaining(at now: Date) -> UInt64 {
        UInt64(refilled(at: now).rounded(.down))
    }

    /// Whether the allowance has come all the way back.
    ///
    /// A full allowance carries no information: a caller holding one is
    /// indistinguishable from a caller nobody has ever heard of, which is what
    /// makes forgetting them safe.
    public func isFull(at now: Date) -> Bool {
        refilled(at: now) >= Double(rule.burstRequests)
    }

    /// Takes `count` requests if they are there, all of them or none.
    ///
    /// All or nothing with no special case for a job larger than the burst: a
    /// member cannot order an indivisible piece of work bigger than their
    /// share, which is the right answer rather than an awkward one.
    ///
    /// - Returns: Whether they were taken. Nothing is taken on a refusal, so a
    ///   refused caller has spent nothing of their own share either.
    public mutating func take(_ count: UInt64, at now: Date) -> Bool {
        available = refilled(at: now)
        // The later of the two, never simply `now`. A clock stepped backwards
        // grants no refill here, but moving the reference point back with it
        // would let the next read refill across the same interval twice and
        // hand a spent caller their whole burst back, which is the one thing a
        // limiter exists to prevent.
        updatedAt = Swift.max(updatedAt, now)
        let wanted = Double(count)
        guard wanted <= available else { return false }
        available -= wanted
        return true
    }

    /// When `count` requests would next be allowed.
    ///
    /// Now, when they already are. Never the next UTC midnight: an allowance
    /// that only came back at midnight would lock a member out for fifteen
    /// hours after a busy morning, which is the failure a refilling allowance
    /// exists to avoid.
    ///
    /// Only ever asked about a count a burst can hold. More than the burst can
    /// never be taken at any instant, so there is no honest date to give and
    /// the amount solved for is clamped to the burst rather than an infinity;
    /// ``ChainError/callerShareCannotCover`` refuses such a count with no date
    /// at all, before this is reached.
    public func nextAllowed(for count: UInt64, at now: Date) -> Date {
        let wanted = Swift.min(Double(count), Double(rule.burstRequests))
        let short = wanted - refilled(at: now)
        guard short > 0 else { return now }
        let rate = rule.refillPerSecond
        // A rate of zero cannot happen while the rule holds at least one
        // request a day, and answering with the day's end rather than with a
        // date built from an infinity is the safe reading if it ever does.
        guard rate > 0 else { return UTCDay.nextMidnight(after: now) }
        return now.addingTimeInterval(short / rate)
    }

    // MARK: - Private Methods

    /// What is available at `now`, capped at the burst.
    ///
    /// Elapsed time is held at zero, so a clock that went backwards grants no
    /// refill, and the cap means an idle member banks a burst rather than the
    /// whole day.
    private func refilled(at now: Date) -> Double {
        let elapsed = Swift.max(now.timeIntervalSince(updatedAt), 0)
        guard elapsed.isFinite else { return available }
        return Swift.min(Double(rule.burstRequests), available + elapsed * rule.refillPerSecond)
    }
}
