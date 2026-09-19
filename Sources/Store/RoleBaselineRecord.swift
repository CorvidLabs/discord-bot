@preconcurrency import Foundation

/// What the last role sweep that actually ran counted.
///
/// The one guard between a mistyped store path and every managed role in the
/// server being taken off in a single pass. It is written **only** when
/// ``Gating/RoleRules/orphanSweep(verifiedMemberCount:lastRecordedCount:)``
/// answers `.run(recordBaseline:)`, never on a refusal: recording the count
/// observed during a refusal lowers the bar to the wrong store's own tiny
/// count, and the next sweep then passes the halving check against itself and
/// strips the server anyway.
public struct RoleBaselineRecord: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Members with a verified account, as the last sweep that ran counted
    /// them.
    public let verifiedMemberCount: Int

    /// When that sweep ran.
    public let recordedAt: Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - verifiedMemberCount: The count to compare the next sweep against.
    ///   - recordedAt: When the sweep ran, recorded to the second.
    public init(verifiedMemberCount: Int, recordedAt: Date) {
        self.verifiedMemberCount = verifiedMemberCount
        self.recordedAt = StoreDate.whole(recordedAt)
    }
}
