@preconcurrency import Foundation

/// Something that went wrong and is worth an operator's attention
/// afterwards.
///
/// SEE-5: a problem that started overnight is still there to read in the
/// morning. Lines scroll and a container restart takes them with it, so
/// these are written down separately and the morning is not archaeology.
public struct SweepProblem: Sendable, Equatable, Codable {

    /// What kind of problem this is.
    public enum Kind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {

        /// The whole sweep threw.
        case sweepFailed = "sweep-failed"

        /// Members were held or missed during a sweep.
        case membersSkipped = "members-skipped"

        /// The collection catalogue could not be read, so every collection's
        /// roles were left as they were.
        case registryUnread = "registry-unread"

        /// The orphan pass refused to run against the records it was given.
        case orphanSweepRefused = "orphan-sweep-refused"

        /// The orphan pass started and could not finish.
        case orphanSweepFailed = "orphan-sweep-failed"

        /// A sweep started and never finished. Worked out when read rather
        /// than written down, because the process that would have written it
        /// is the one that died.
        case sweepAbandoned = "sweep-abandoned"

        // MARK: - Public Methods

        /// Short heading for a card or a list.
        public var label: String {
            switch self {
            case .sweepFailed: return "Sweep failed"
            case .membersSkipped: return "Members not swept"
            case .registryUnread: return "Collections not read"
            case .orphanSweepRefused: return "Orphan pass refused"
            case .orphanSweepFailed: return "Orphan pass failed"
            case .sweepAbandoned: return "Sweep never finished"
            }
        }
    }

    // MARK: - Properties

    /// When it happened.
    public let at: Date

    /// The sweep it belongs to, when it belongs to one (SEE-6).
    public let runId: String?

    /// What kind of problem it is.
    public let kind: Kind

    /// What happened, in one sentence naming something an operator could
    /// change (SEE-11).
    public let detail: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - at: When it happened.
    ///   - runId: The sweep it belongs to.
    ///   - kind: What kind of problem it is.
    ///   - detail: What happened, in one sentence.
    public init(at: Date, runId: String?, kind: Kind, detail: String) {
        self.at = at
        self.runId = runId
        self.kind = kind
        self.detail = detail
    }

    // MARK: - Public Methods

    /// Most recent problems first, capped.
    ///
    /// Newest first and capped by count rather than by age. A fixed age
    /// window throws away the only record of a problem that started at three
    /// in the morning before anybody was awake to read it, which is the
    /// failure SEE-5 names. The cap exists only so one journal row cannot
    /// grow without bound.
    ///
    /// - Parameters:
    ///   - problems: What to trim.
    ///   - limit: How many to keep. Zero keeps none.
    public static func trimmed(_ problems: [SweepProblem], limit: Int) -> [SweepProblem] {
        guard limit > 0 else { return [] }
        return Array(problems.sorted { $0.at > $1.at }.prefix(limit))
    }
}
