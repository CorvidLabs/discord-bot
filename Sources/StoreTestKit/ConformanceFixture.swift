@preconcurrency import Foundation
import Reserve
import Store

/// Made-up members, accounts and a reserve, so nothing in the suite resembles
/// anything real.
///
/// Every label here is obviously synthetic on sight. A fixture that looked like
/// a real address is a fixture somebody eventually pastes into a live command.
internal enum ConformanceFixture {

    // MARK: - Properties

    /// The stream the reserve behaviours pay.
    internal static let streamId = "members"

    // MARK: - Internal Methods

    /// An account label nobody could mistake for an address.
    internal static func account(_ index: Int) -> String {
        String(format: "ACCOUNT-%04d", index)
    }

    /// A chat account id nobody could mistake for a real one.
    internal static func externalId(_ index: Int) -> String {
        String(format: "EXTERNAL-%04d", index)
    }

    /// A holding id nobody could mistake for a real one.
    internal static func holding(_ index: Int) -> String {
        String(format: "HOLDING-%04d", index)
    }

    /// A fixed instant, so nothing in the suite depends on when it ran.
    internal static func instant(_ offsetSeconds: Int) -> Date {
        Date(timeIntervalSince1970: 1_600_000_000 + TimeInterval(offsetSeconds))
    }

    /// A reserve with one stream, paying once per recipient.
    internal static func reserve() throws -> ReserveConfiguration {
        try ReserveConfiguration(
            asset: try ReserveAsset(symbol: "TOKEN", decimals: 6),
            totalWholeUnits: 1_000_000,
            streams: [
                ReserveStream(
                    id: streamId,
                    name: "Members",
                    share: .percent(100),
                    denominator: 100,
                    rule: .oncePerRecipient,
                    unitName: "member"
                )
            ],
            schedules: [
                ReserveSchedule(
                    id: "short",
                    label: "four weeks",
                    epochCount: 4,
                    cadence: "weekly",
                    aliases: ["four weeks"]
                )
            ]
        )
    }

    /// One recipient per index, each holding one thing.
    internal static func recipients(_ indices: [Int]) -> ReserveRecipientList {
        ReserveRecipientList(
            streamId: streamId,
            recipients: indices.map { index in
                ReserveRecipient(
                    id: "RECIPIENT-\(index)",
                    account: account(index),
                    holdingIds: [holding(index)]
                )
            }
        )
    }
}
