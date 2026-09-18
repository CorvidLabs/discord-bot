import Foundation

/// How long the reserve takes to pay out, as a count of epochs.
///
/// Chosen once, before the first epoch, and then fixed. The duration decides the
/// per-epoch figure, never what a recipient is entitled to over the whole
/// schedule: half as many epochs pay twice as much each. What is actually *paid*
/// can differ between two durations by a handful of smallest units, because the
/// residue that will not divide differs — and that residue is stated rather than
/// hidden.
///
/// The catalog is configuration. The original hard-coded exactly two durations,
/// which is a reasonable thing for one project to want and an unreasonable thing
/// for a library to insist on.
public struct ReserveSchedule: Sendable, Equatable, Hashable, Codable, Identifiable {

    // MARK: - Properties

    /// Short stable key, stored in state once chosen: `6m`, `1y`, `q4`.
    public let id: String

    /// What a person reads: `six months`.
    public let label: String

    /// Epochs in this schedule. At least one.
    public let epochCount: UInt64

    /// What one epoch is called: `weekly`, `monthly`. Display only — the engine
    /// never reads a clock, so the cadence is the host's to enforce.
    public let cadence: String

    /// Extra spellings ``matches(_:)`` accepts.
    public let aliases: [String]

    // MARK: - Initializers

    public init(
        id: String,
        label: String? = nil,
        epochCount: UInt64,
        cadence: String = "weekly",
        aliases: [String] = []
    ) {
        self.id = id
        self.label = label ?? id
        self.epochCount = epochCount
        self.cadence = cadence
        self.aliases = aliases
    }

    // MARK: - Public Methods

    /// One line for a card: `six months · 26 weekly epochs`.
    public var summary: String { "\(label) · \(epochCount) \(cadence) epochs" }

    /// Whether a typed string names this schedule.
    ///
    /// Matches the id, the label, the epoch count and any alias, ignoring case,
    /// spaces, hyphens and underscores — so `6m`, `26`, `Six Months` and
    /// `six-months` all land on the same schedule. An empty string matches
    /// nothing, because nothing here is allowed to fall back to a default: a
    /// duration that quietly became the other one would halve or double every
    /// payment for the rest of the schedule.
    public func matches(_ raw: String) -> Bool {
        let needle = Self.normalize(raw)
        guard !needle.isEmpty else { return false }
        var candidates = [id, label, String(epochCount)]
        candidates.append(contentsOf: aliases)
        return candidates.contains { Self.normalize($0) == needle }
    }

    // MARK: - Private Methods

    private static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }
}
