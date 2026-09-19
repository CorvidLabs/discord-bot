@preconcurrency import Foundation

/// What one pass of the sweep did, handed straight back to whoever asked
/// for it.
///
/// The same figures the journal keeps, plus the problems, so a hand-started
/// sweep can answer on the spot without reading back what it just wrote.
public struct SweepReport: Sendable, Equatable {

    // MARK: - Properties

    /// Whether this pass actually ran. False only when another was already
    /// running, which is the one case that does nothing at all.
    public let ran: Bool

    /// Identifies this sweep in every line it produced. Empty for a pass
    /// that never started.
    public let runId: String

    /// Members visited.
    public let memberCount: Int

    /// Accounts read.
    public let accountCount: Int

    /// Members this bot took managed roles back from.
    public let orphansCleared: Int

    /// Per-member outcomes.
    public let tally: SweepTally

    /// How long the pass took.
    public let elapsed: TimeInterval

    /// What went wrong and is worth reading later.
    public let problems: [SweepProblem]

    /// The error that ended the whole pass, when one did.
    public let failure: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - ran: Whether this pass actually ran.
    ///   - runId: Identifies this sweep.
    ///   - memberCount: Members visited.
    ///   - accountCount: Accounts read.
    ///   - orphansCleared: Members roles were taken back from.
    ///   - tally: Per-member outcomes.
    ///   - elapsed: How long it took.
    ///   - problems: What went wrong.
    ///   - failure: The error that ended it, when one did.
    public init(
        ran: Bool,
        runId: String,
        memberCount: Int = 0,
        accountCount: Int = 0,
        orphansCleared: Int = 0,
        tally: SweepTally = .empty,
        elapsed: TimeInterval = 0,
        problems: [SweepProblem] = [],
        failure: String? = nil
    ) {
        self.ran = ran
        self.runId = runId
        self.memberCount = memberCount
        self.accountCount = accountCount
        self.orphansCleared = orphansCleared
        self.tally = tally
        self.elapsed = elapsed
        self.problems = problems
        self.failure = failure
    }

    // MARK: - Public Methods

    /// A pass that did nothing because another was already running.
    public static let skipped = SweepReport(ran: false, runId: "")

    /// One line an operator can read, naming the split SEE-2.a asks for.
    public var summary: String {
        guard ran else { return "A sweep was already running, so this one did nothing." }
        var line = "\(memberCount) member(s), \(accountCount) account(s): "
            + "\(tally.changed) changed, \(tally.unchanged) already correct, "
            + "\(tally.held) held on purpose, \(tally.missed) missed"
        if orphansCleared > 0 {
            line += ", \(orphansCleared) orphan(s) cleared"
        }
        if let failure {
            line += ". The sweep stopped early: \(failure)"
        }
        return line
    }
}
