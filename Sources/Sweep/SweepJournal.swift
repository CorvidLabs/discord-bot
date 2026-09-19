@preconcurrency import Foundation

/// Where the run record and the problems are kept.
///
/// Two writes per sweep, deliberately: ``begin(_:)`` before any work and
/// ``end(_:)`` after it. A journal that only heard about finished sweeps
/// could not tell an operator that the last one never came back, which is
/// half of SEE-2.
///
/// Nothing here throws. A journal that cannot write must not be the reason a
/// sweep fails, because the sweep is the thing keeping members' roles true
/// and the journal is the thing describing it. An implementation swallows
/// its own failures, or reports them through its own log.
public protocol SweepJournal: Sendable {

    /// Records that a sweep has started.
    ///
    /// - Parameter record: The sweep, with no finish on it yet.
    func begin(_ record: SweepRecord) async

    /// Records that a sweep has ended, cleanly or not.
    ///
    /// - Parameter record: The same sweep, ended.
    func end(_ record: SweepRecord) async

    /// Keeps problems worth reading later.
    ///
    /// - Parameter problems: What went wrong during one sweep. An empty list
    ///   is an ordinary call and clears nothing.
    func record(_ problems: [SweepProblem]) async

    /// The last sweep written down, finished or not, or nil before any has
    /// been.
    func lastSweep() async -> SweepRecord?

    /// Problems kept, most recent first.
    func recentProblems() async -> [SweepProblem]
}

/// A journal in memory, for a test or a host with nothing durable yet.
///
/// **It does not survive a restart**, which is the one thing a real journal
/// is for, so a host that ships this gets the reasons and loses the memory.
/// Said plainly here rather than discovered later.
public actor InMemorySweepJournal: SweepJournal {

    // MARK: - Properties

    /// How many problems are kept before the oldest are dropped.
    public let problemLimit: Int

    private var record: SweepRecord?
    private var problems: [SweepProblem] = []

    // MARK: - Initializers

    /// - Parameter problemLimit: How many problems to keep.
    public init(problemLimit: Int = 50) {
        self.problemLimit = problemLimit
    }

    // MARK: - Public Methods

    public func begin(_ record: SweepRecord) async {
        self.record = record
    }

    public func end(_ record: SweepRecord) async {
        self.record = record
    }

    public func record(_ problems: [SweepProblem]) async {
        self.problems = SweepProblem.trimmed(self.problems + problems, limit: problemLimit)
    }

    public func lastSweep() async -> SweepRecord? {
        record
    }

    public func recentProblems() async -> [SweepProblem] {
        problems
    }
}
