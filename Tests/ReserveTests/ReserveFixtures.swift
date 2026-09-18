import Foundation
@testable import Reserve

/// A reserve shaped like a real one, so the pinned figures below are figures
/// somebody actually has to be able to reconcile.
///
/// Ten billion whole units of a six-decimal asset, split seventy-thirty between
/// a once-per-recipient stream with a denominator of 1,000 and a per-unit stream
/// with a denominator of 4,096. The shape matters more than the names: it is the
/// combination that produces awkward residues, and awkward residues are what the
/// arithmetic has to survive.
enum Fixture {

    // MARK: - Ids

    static let members = "members"
    static let passes = "passes"

    // MARK: - Pieces

    static func asset(decimals: UInt8 = 6) throws -> ReserveAsset {
        try ReserveAsset(symbol: "TOKEN", decimals: decimals)
    }

    static func sixMonths() -> ReserveSchedule {
        ReserveSchedule(
            id: "6m",
            label: "six months",
            epochCount: 26,
            cadence: "weekly",
            aliases: ["six months", "6 months"]
        )
    }

    static func oneYear() -> ReserveSchedule {
        ReserveSchedule(
            id: "1y",
            label: "one year",
            epochCount: 52,
            cadence: "weekly",
            aliases: ["year", "12m"]
        )
    }

    static func memberStream() -> ReserveStream {
        ReserveStream(
            id: members,
            name: "Members",
            share: .percent(70),
            denominator: 1_000,
            rule: .oncePerRecipient,
            unitName: "member"
        )
    }

    static func passStream() -> ReserveStream {
        ReserveStream(
            id: passes,
            name: "Passes",
            share: .percent(30),
            denominator: 4_096,
            rule: .oncePerHeldUnit,
            unitName: "pass",
            unitNamePlural: "passes"
        )
    }

    // MARK: - The reserve

    static func reserve() throws -> ReserveConfiguration {
        try ReserveConfiguration(
            asset: try asset(),
            totalWholeUnits: 10_000_000_000,
            streams: [memberStream(), passStream()],
            schedules: [sixMonths(), oneYear()]
        )
    }

    static func planner() throws -> ReservePlanner {
        ReservePlanner(configuration: try reserve())
    }

    // MARK: - Convenience

    /// Whole units as smallest units, for readable expectations.
    static func whole(_ value: UInt64) -> UInt64 { value * 1_000_000 }

    /// An obviously fake account label. Nothing here is a real address.
    static func account(_ index: Int) -> String { String(format: "ACCOUNT-%04d", index) }

    /// One recipient with one holding, all synthetic.
    static func holder(_ index: Int, recipientId: String? = nil) -> ReserveRecipient {
        ReserveRecipient(
            id: recipientId ?? "R\(index)",
            account: account(index),
            holdingIds: ["H-\(index)"]
        )
    }

    static func epoch(_ streamId: String, _ number: UInt64) -> ReserveEpochRecord {
        ReserveEpochRecord(streamId: streamId, epoch: number)
    }
}
