import Foundation

/// How hard one sweep is allowed to push the chat service.
///
/// The chain side is already bounded elsewhere, by a per-second limiter and
/// a per-day budget that belong to the whole process. What is bounded here
/// is the other end: a sweep of two thousand members is two thousand role
/// reads, and a chat service that tolerates a burst from one bot does not
/// tolerate it for long.
public struct SweepLimits: Sendable, Equatable {

    // MARK: - Properties

    /// How many members are handled at once.
    ///
    /// At least one. A batch of one is a plain sequential sweep, which is
    /// what a host that has been rate limited should fall back to.
    public let memberBatchSize: Int

    /// How long to wait between batches.
    ///
    /// Zero is allowed and is what a test uses. It is not the default,
    /// because a sweep with no pause at all is a burst the chat service
    /// answers with a rate limit that then delays everything a member typed.
    public let pauseBetweenBatches: Duration

    /// How many orphans have their roles taken back at once.
    ///
    /// Larger than the member batch because each one is a single write with
    /// no read in front of it: the roster already said what they hold.
    public let orphanBatchSize: Int

    /// How many problems one sweep may add to the journal.
    public let problemLimit: Int

    // MARK: - Initializers

    /// - Parameters:
    ///   - memberBatchSize: How many members at once. Raised to one if lower.
    ///   - pauseBetweenBatches: How long to wait between batches.
    ///   - orphanBatchSize: How many orphans at once. Raised to one if lower.
    ///   - problemLimit: How many problems one sweep may add.
    public init(
        memberBatchSize: Int = 8,
        pauseBetweenBatches: Duration = .milliseconds(100),
        orphanBatchSize: Int = 10,
        problemLimit: Int = 20
    ) {
        self.memberBatchSize = max(1, memberBatchSize)
        self.pauseBetweenBatches = pauseBetweenBatches
        self.orphanBatchSize = max(1, orphanBatchSize)
        self.problemLimit = max(0, problemLimit)
    }

    // MARK: - Public Methods

    /// What a host gets by not choosing.
    public static let standard = SweepLimits()

    /// No pause at all, for a test that would otherwise spend its time
    /// asleep.
    public static let unthrottled = SweepLimits(pauseBetweenBatches: .zero)
}
