@preconcurrency import Foundation

/// How a recorded sweep ended, as it is read back later.
public enum SweepState: Sendable, Equatable {

    /// Started, not finished, and recent enough that it still could be
    /// running.
    case running

    /// Started, never finished, and too long ago to still be running. The
    /// process died or was killed part way through.
    case abandoned

    /// Reached the end, but the sweep itself threw.
    case failed(String)

    /// Reached the end cleanly.
    case finished
}

/// One sweep of everyone's roles, as it is written down.
///
/// SEE-2 wants "did the last sweep finish, and when". That cannot be
/// answered from memory: what is in memory is lost on restart, and a bot
/// that was restarted because the sweep hung is exactly the bot being asked.
///
/// So the start is written **before** the work and the finish after it, and
/// a record with no ``finishedAt`` is an unfinished sweep rather than the
/// absence of one. Without the first write, the newest thing on disk after a
/// crash mid-sweep is the previous sweep's success, and the check reports a
/// healthy bot for as long as nobody notices.
public struct SweepRecord: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Identifies this sweep in every line it produced (SEE-6).
    public let runId: String

    /// When the sweep started.
    public let startedAt: Date

    /// When it finished, or nil if it never did.
    public let finishedAt: Date?

    /// Members the sweep set out to visit.
    public let memberCount: Int

    /// Accounts the sweep set out to read.
    public let accountCount: Int

    /// Members whose roles this bot granted and then took back, because
    /// nothing on record says they should have them.
    public let orphansCleared: Int

    /// Per-member outcomes.
    public let tally: SweepTally

    /// The error that ended the whole sweep, when one did.
    public let failure: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - runId: Identifies this sweep.
    ///   - startedAt: When it started.
    ///   - finishedAt: When it finished, or nil.
    ///   - memberCount: Members it set out to visit.
    ///   - accountCount: Accounts it set out to read.
    ///   - orphansCleared: Members it took managed roles back from.
    ///   - tally: Per-member outcomes.
    ///   - failure: The error that ended it, when one did.
    public init(
        runId: String,
        startedAt: Date,
        finishedAt: Date? = nil,
        memberCount: Int = 0,
        accountCount: Int = 0,
        orphansCleared: Int = 0,
        tally: SweepTally = .empty,
        failure: String? = nil
    ) {
        self.runId = runId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.memberCount = memberCount
        self.accountCount = accountCount
        self.orphansCleared = orphansCleared
        self.tally = tally
        self.failure = failure
    }

    // MARK: - Public Methods

    /// The same sweep, ended.
    ///
    /// - Parameters:
    ///   - finishedAt: When it finished.
    ///   - memberCount: Members it visited.
    ///   - accountCount: Accounts it read.
    ///   - orphansCleared: Members it took managed roles back from.
    ///   - tally: Per-member outcomes.
    ///   - failure: The error that ended it, when one did.
    public func ended(
        at finishedAt: Date,
        memberCount: Int,
        accountCount: Int,
        orphansCleared: Int = 0,
        tally: SweepTally,
        failure: String? = nil
    ) -> SweepRecord {
        SweepRecord(
            runId: runId,
            startedAt: startedAt,
            finishedAt: finishedAt,
            memberCount: memberCount,
            accountCount: accountCount,
            orphansCleared: orphansCleared,
            tally: tally,
            failure: failure
        )
    }

    /// Wall-clock time the sweep took, or nil while it has not finished.
    public var elapsed: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// How this sweep ended, judged from when it started.
    ///
    /// A record with no ``finishedAt`` is never ``SweepState/finished``.
    ///
    /// - Parameters:
    ///   - now: The instant to judge from.
    ///   - runningHorizon: How long a sweep may go without finishing before
    ///     it is called abandoned. Callers pass the configured interval: by
    ///     the time the next sweep is due, one that has not finished is not
    ///     going to.
    public func state(now: Date, runningHorizon: TimeInterval) -> SweepState {
        guard finishedAt != nil else {
            // A container starting with a bad clock, or an NTP step, must not
            // turn a sweep that began seconds ago into an incident.
            let age = now.timeIntervalSince(startedAt)
            guard age > runningHorizon else { return .running }
            return .abandoned
        }
        if let failure {
            return .failed(failure)
        }
        return .finished
    }

    /// An identifier for a sweep: `sweep-<utc timestamp>-<suffix>`.
    ///
    /// Timestamped rather than a bare random string, so ids sort and so a
    /// line in a log can be placed at a glance without cross-referencing
    /// anything (SEE-6).
    ///
    /// - Parameters:
    ///   - startedAt: When the sweep started.
    ///   - suffix: What tells two sweeps in the same second apart.
    public static func runId(startedAt: Date, suffix: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        // Not the host's timezone. An id that reads 09:00 on one machine and
        // 10:00 on another cannot be matched against anything.
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: startedAt
        )
        let stamp = String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
        return "sweep-\(stamp)-\(suffix)"
    }

    /// A fresh run id, with a random suffix so two sweeps that start in the
    /// same second are still told apart.
    ///
    /// - Parameter startedAt: When the sweep started.
    public static func newRunId(startedAt: Date) -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4).lowercased()
        return runId(startedAt: startedAt, suffix: String(suffix))
    }
}
