import Foundation
import Gating

/// Per-member outcomes of one sweep, counted.
///
/// Counts and reason totals rather than a per-member list. The list is
/// unbounded in the size of the server and this is written to one journal
/// row on every sweep, so a thousand-member server would turn the record an
/// operator came to read into something nobody can read. The reasons stay,
/// because a count with no reason answers SEE-2 and not SEE-2.a.
public struct SweepTally: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Members whose roles were written.
    public private(set) var changed: Int

    /// Members compared and already correct.
    public private(set) var unchanged: Int

    /// Members deliberately left alone.
    public private(set) var held: Int

    /// Members the sweep failed on.
    public private(set) var missed: Int

    /// Members for whom at least one fact went unread, whatever was done
    /// with the rest.
    public private(set) var incomplete: Int

    /// Held counts keyed by ``SweepSkipReason`` raw value.
    public private(set) var heldReasons: [String: Int]

    /// Missed counts keyed by ``SweepSkipReason`` raw value.
    public private(set) var missedReasons: [String: Int]

    /// How many members each unread fact affected, keyed by ``key(for:)``.
    public private(set) var unreadFacts: [String: Int]

    // MARK: - Initializers

    /// - Parameters:
    ///   - changed: Members whose roles were written.
    ///   - unchanged: Members compared and already correct.
    ///   - held: Members deliberately left alone.
    ///   - missed: Members the sweep failed on.
    ///   - incomplete: Members with at least one unread fact.
    ///   - heldReasons: Held counts by reason.
    ///   - missedReasons: Missed counts by reason.
    ///   - unreadFacts: Member counts by unread fact.
    public init(
        changed: Int = 0,
        unchanged: Int = 0,
        held: Int = 0,
        missed: Int = 0,
        incomplete: Int = 0,
        heldReasons: [String: Int] = [:],
        missedReasons: [String: Int] = [:],
        unreadFacts: [String: Int] = [:]
    ) {
        self.changed = changed
        self.unchanged = unchanged
        self.held = held
        self.missed = missed
        self.incomplete = incomplete
        self.heldReasons = heldReasons
        self.missedReasons = missedReasons
        self.unreadFacts = unreadFacts
    }

    // MARK: - Public Methods

    /// A tally before any member has been swept.
    public static let empty = SweepTally()

    /// Members accounted for so far.
    public var members: Int {
        changed + unchanged + held + missed
    }

    /// Adds one member's outcome.
    public mutating func record(_ outcome: MemberSweepOutcome) {
        switch outcome.disposition {
        case .changed:
            changed += 1
        case .unchanged:
            unchanged += 1
        case .held:
            held += 1
            if let reason = outcome.reason {
                heldReasons[reason.rawValue, default: 0] += 1
            }
        case .missed:
            missed += 1
            if let reason = outcome.reason {
                missedReasons[reason.rawValue, default: 0] += 1
            }
        }
        if !outcome.unknowns.isEmpty {
            incomplete += 1
        }
        // Counted once per member per fact, so two unread collections on one
        // member are two facts and one incomplete member. A fact counted per
        // wallet would read as an outage twice the size it was.
        for unknown in Set(outcome.unknowns) {
            unreadFacts[Self.key(for: unknown), default: 0] += 1
        }
    }

    /// A stable, short name for one unread fact.
    ///
    /// ``Gating/GatingUnknown`` carries a sentence and not a key, and a
    /// sentence is not something to use as a dictionary key: it is written
    /// for a person and may be reworded, which would silently split one
    /// count into two across a release.
    public static func key(for unknown: GatingUnknown) -> String {
        switch unknown {
        case .balance: return "balance"
        case .liquidityPositions: return "liquidity-positions"
        case .collection(let id): return "collection:\(id)"
        }
    }

    /// Counts rendered largest first, as `"name x3"` parts.
    ///
    /// Sorted by count and then by name so one tally always reads the same
    /// way. An order that shifts between runs makes two screenshots of the
    /// same incident look like two incidents.
    public static func summary(_ counts: [String: Int]) -> String {
        counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: ", ")
    }
}
