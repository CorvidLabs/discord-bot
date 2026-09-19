import Foundation

/// The chip economy: the starting pile, the daily claim, the streak payout and the
/// forage cooldown.
///
/// **Chips are a score.** They are not a token, not an asset id, not a coin and not
/// a balance of anything that can be sent. Nothing in this package can sign, send
/// or convert, and there is no dependency here that could: the module imports
/// Foundation and nothing else, so the property is enforced by the package graph
/// rather than by a reviewer noticing (`PLAY-1.a`).
///
/// The type is called `Chips` and every member-visible string says "chips". The
/// name it replaces meant the currency, a collectible ladder, a profile card and a
/// button all at the same time, and nobody could tell which one a sentence was
/// about. "Nest" now names the collectible ladder in ``Shiny`` and nothing else.
public enum Chips: Sendable {

    // MARK: - Properties

    /// A new player's pile.
    public static let starting: Int = 200

    /// Smallest stake ``Blackjack`` will deal for.
    public static let minimumBet: Int = 10

    /// Chips a won call pays before the streak multiplier.
    public static let streakWinBase: Int = 8

    /// Quarter-steps the streak multiplier climbs before it flattens.
    ///
    /// A named constant because the number is quoted to members on a rules page,
    /// and a rules page that quotes a different number from the one the game plays
    /// by is worse than no rules page (`LEARN-6`).
    public static let streakSteps: Int = 8

    /// Chips the daily claim pays before any collection bonus.
    public static let baseDailyStipend: Int = 40

    /// Seconds between forages with no collections held.
    public static let defaultForageCooldown: TimeInterval = 30

    /// Collection perks stack, but a forage never comes round faster than this.
    ///
    /// An absolute floor rather than a suggestion. Without it a host who configures
    /// six generous collections has built a button to hold down.
    public static let minimumForageCooldown: TimeInterval = 8

    // MARK: - Public Methods

    /// UTC `yyyy-MM-dd` key for the daily claim.
    ///
    /// Fixed to a Gregorian UTC calendar rather than the process locale or time
    /// zone: the claim rolls over at the same instant for every player, and a
    /// container restarted in another zone must not hand out a second daily.
    public static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = pad(parts.year ?? 1970, width: 4)
        let month = pad(parts.month ?? 1, width: 2)
        let day = pad(parts.day ?? 1, width: 2)
        return "\(year)-\(month)-\(day)"
    }

    /// Chips the daily claim pays: the base, plus each held collection's bonus.
    ///
    /// Always positive, because the base is positive and a bonus cannot be
    /// negative. A player who holds nothing and has linked nothing can still play
    /// tomorrow, which is the point of the claim (`ADOPT-3`, `PLAY-8`).
    ///
    /// - Parameters:
    ///   - holdings: What the player holds.
    ///   - perks: The host's configuration. Empty pays the base alone.
    /// - Returns: Chips to pay, at least one.
    public static func dailyStipend(_ holdings: GameHoldings, perks: GamePerks = .empty) -> Int {
        var total = baseDailyStipend
        for perk in perks.active(for: holdings) {
            // Saturating rather than trapping: a host who types too many zeroes
            // into a bonus should get an absurd stipend, not a dead process.
            let (sum, overflow) = total.addingReportingOverflow(perk.dailyBonusChips)
            total = overflow ? Int.max : sum
        }
        return total
    }

    /// Chips a won call pays at the streak the win produced.
    ///
    /// `round(base * (1 + min(streak - 1, steps) * 0.25))`: streak 1 pays the base
    /// and each further win adds a quarter, flattening from the ninth win on.
    ///
    /// - Parameter streakAfterWin: The streak the win has just produced, counting
    ///   from 1.
    /// - Returns: Chips to pay.
    public static func streakPayout(streakAfterWin: Int) -> Int {
        let steps = min(streakAfterWin - 1, streakSteps)
        let multiplier = 1.0 + Double(steps) * 0.25
        return Int((Double(streakWinBase) * multiplier).rounded())
    }

    /// Seconds a player waits between forages, after their collections shorten it.
    ///
    /// Each held perk's factor is applied in configuration order and floored to
    /// whole milliseconds at every step, because that is what the JavaScript
    /// original did and because flooring once at the end gives a different answer.
    /// Never returns less than ``minimumForageCooldown``.
    ///
    /// - Parameters:
    ///   - holdings: What the player holds.
    ///   - perks: The host's configuration. Empty returns `base`, floored.
    ///   - base: The wait before any perk, in seconds.
    /// - Returns: Seconds to wait.
    public static func forageCooldown(
        _ holdings: GameHoldings,
        perks: GamePerks = .empty,
        base: TimeInterval = Chips.defaultForageCooldown
    ) -> TimeInterval {
        var milliseconds = floorToMilliseconds(base)
        for perk in perks.active(for: holdings) {
            // Floored at every step, not once at the end. The two give different
            // answers, and the stepwise one is what the original played by.
            milliseconds = floorToInt(Double(milliseconds) * perk.forageCooldownFactor)
        }
        let floorMilliseconds = floorToMilliseconds(minimumForageCooldown)
        return TimeInterval(max(floorMilliseconds, milliseconds)) / 1000
    }

    /// A chip total after a delta, floored at zero.
    ///
    /// The floor lives here, in the engine, rather than in whatever stores a
    /// player: a member can lose a hand but can never owe, and the rule is worth
    /// proving in a test that needs no database. Saturating at both ends, because
    /// a total that traps is a table nobody can play.
    ///
    /// - Parameters:
    ///   - delta: What a ``ReduceResult`` asked for.
    ///   - balance: What the player had.
    /// - Returns: The new total, never below zero.
    public static func applying(_ delta: Int, to balance: Int) -> Int {
        let (sum, overflow) = balance.addingReportingOverflow(delta)
        if overflow {
            return delta > 0 ? Int.max : 0
        }
        return max(0, sum)
    }

    // MARK: - Private Methods

    /// Whole milliseconds in `seconds`, never negative.
    private static func floorToMilliseconds(_ seconds: TimeInterval) -> Int {
        floorToInt(seconds * 1000)
    }

    /// `value` floored into an `Int`, clamped rather than trapped at both ends.
    ///
    /// The order of the two guards is the whole point. A product that overflowed a
    /// `Double` is an enormous wait, not a missing one, so infinity clamps to the
    /// top with every other huge number. Sending it to zero instead handed the host
    /// who asked for the longest wait the shortest one: the floor, eight seconds.
    /// Only a value that is not a number at all, or one at or below zero, floors at
    /// zero.
    private static func floorToInt(_ value: Double) -> Int {
        let scaled = value.rounded(.down)
        if scaled.isNaN || scaled <= 0 { return 0 }
        if scaled >= Double(Int.max) { return Int.max }
        return Int(scaled)
    }

    /// Zero-padded decimal, so the day key does not depend on a number formatter.
    private static func pad(_ value: Int, width: Int) -> String {
        let digits = String(value)
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}
