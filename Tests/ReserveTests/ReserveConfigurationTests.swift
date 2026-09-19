import Foundation
import Testing
@testable import Reserve

/// What a reserve refuses to be.
///
/// Every case here is caught by an initializer, before anything exists that
/// could pay anybody. A split that does not add up is a mistake to find while
/// typing, not on the morning of the first payout.
@Suite("Reserve configuration")
struct ReserveConfigurationTests {

    // MARK: - The split must add up

    @Test("Shares that do not sum to the whole reserve are refused (RESERVE-1.b)")
    func sharesMustSumToTheReserve() throws {
        // Seventy and twenty leaves a tenth of the reserve that nobody owns.
        #expect(throws: (any Error).self) {
            try ReserveConfiguration(
                asset: try Fixture.asset(),
                totalWholeUnits: 10_000_000_000,
                streams: [
                    ReserveStream(id: "a", share: .percent(70), denominator: 10, rule: .oncePerRecipient),
                    ReserveStream(id: "b", share: .percent(20), denominator: 10, rule: .oncePerRecipient)
                ],
                schedules: [Fixture.sixMonths()]
            )
        }
        // And over-allocating is refused just as hard: it cannot be paid.
        #expect(throws: (any Error).self) {
            try ReserveConfiguration(
                asset: try Fixture.asset(),
                totalWholeUnits: 10_000_000_000,
                streams: [
                    ReserveStream(id: "a", share: .percent(70), denominator: 10, rule: .oncePerRecipient),
                    ReserveStream(id: "b", share: .percent(50), denominator: 10, rule: .oncePerRecipient)
                ],
                schedules: [Fixture.sixMonths()]
            )
        }
    }

    @Test("A split that does not divide into whole smallest units is refused (RESERVE-1.c)")
    func indivisibleShareRefused() throws {
        // Ten smallest units split three ways cannot be exact.
        #expect(
            throws: ReserveConfigurationError.indivisibleShare(streamId: "a", share: "1/3")
        ) {
            try ReserveConfiguration(
                asset: try Fixture.asset(decimals: 0),
                totalWholeUnits: 10,
                streams: [
                    ReserveStream(id: "a", share: ReserveShare(1, of: 3), denominator: 1, rule: .oncePerRecipient),
                    ReserveStream(id: "b", share: ReserveShare(2, of: 3), denominator: 1, rule: .oncePerRecipient)
                ],
                schedules: [Fixture.sixMonths()]
            )
        }
    }

    @Test("Three streams are as ordinary as two (RESERVE-1.a)")
    func threeStreamsAreFine() throws {
        let reserve = try ReserveConfiguration(
            asset: try Fixture.asset(decimals: 2),
            totalWholeUnits: 1_000_000,
            streams: [
                ReserveStream(id: "a", share: .percent(50), denominator: 100, rule: .oncePerRecipient),
                ReserveStream(id: "b", share: .percent(30), denominator: 200, rule: .oncePerHeldUnit),
                ReserveStream(id: "c", share: .percent(20), denominator: 400, rule: .oncePerHeldUnit)
            ],
            schedules: [ReserveSchedule(id: "12", epochCount: 12, cadence: "monthly")]
        )
        #expect(reserve.streams.count == 3)
        #expect(try reserve.allocationBaseUnits("a") == 50_000_000)
        #expect(try reserve.allocationBaseUnits("b") == 30_000_000)
        #expect(try reserve.allocationBaseUnits("c") == 20_000_000)
        let sum = try reserve.streams.reduce(UInt64(0)) { $0 + (try reserve.allocationBaseUnits($1.id)) }
        #expect(sum == reserve.totalBaseUnits)
    }

    @Test("One stream taking the whole reserve is a legitimate reserve")
    func singleStream() throws {
        let reserve = try ReserveConfiguration(
            asset: try Fixture.asset(),
            totalWholeUnits: 1_000_000,
            streams: [
                ReserveStream(id: "only", share: .whole, denominator: 500, rule: .oncePerRecipient)
            ],
            schedules: [Fixture.oneYear()]
        )
        #expect(try reserve.allocationBaseUnits("only") == reserve.totalBaseUnits)
        #expect(try reserve.shareBaseUnits("only") == Fixture.whole(2_000))
    }

    // MARK: - Structural refusals

    @Test("A reserve needs streams, schedules, and unique ids for both")
    func structuralRefusals() throws {
        let asset = try Fixture.asset()
        #expect(throws: ReserveConfigurationError.noStreams) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [],
                schedules: [Fixture.sixMonths()]
            )
        }
        #expect(throws: ReserveConfigurationError.noSchedules) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [ReserveStream(id: "a", share: .whole, denominator: 1, rule: .oncePerRecipient)],
                schedules: []
            )
        }
        #expect(throws: ReserveConfigurationError.duplicateStreamId("a")) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [
                    ReserveStream(id: "a", share: .percent(50), denominator: 1, rule: .oncePerRecipient),
                    ReserveStream(id: "a", share: .percent(50), denominator: 1, rule: .oncePerRecipient)
                ],
                schedules: [Fixture.sixMonths()]
            )
        }
        #expect(throws: ReserveConfigurationError.duplicateScheduleId("6m")) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [ReserveStream(id: "a", share: .whole, denominator: 1, rule: .oncePerRecipient)],
                schedules: [Fixture.sixMonths(), Fixture.sixMonths()]
            )
        }
    }

    @Test("A zero denominator or a zero-epoch schedule is refused, never divided by")
    func zeroesRefused() throws {
        let asset = try Fixture.asset()
        #expect(throws: ReserveConfigurationError.invalidDenominator(streamId: "a")) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [ReserveStream(id: "a", share: .whole, denominator: 0, rule: .oncePerRecipient)],
                schedules: [Fixture.sixMonths()]
            )
        }
        #expect(throws: ReserveConfigurationError.invalidEpochCount(scheduleId: "none")) {
            try ReserveConfiguration(
                asset: asset,
                totalWholeUnits: 100,
                streams: [ReserveStream(id: "a", share: .whole, denominator: 1, rule: .oncePerRecipient)],
                schedules: [ReserveSchedule(id: "none", epochCount: 0)]
            )
        }
    }

    @Test("An asset cannot have more decimals than 64 bits can hold")
    func decimalCeiling() {
        #expect(throws: ReserveConfigurationError.unsupportedDecimals(20)) {
            try ReserveAsset(symbol: "X", decimals: 20)
        }
        #expect(throws: Never.self) {
            try ReserveAsset(symbol: "X", decimals: 19)
        }
    }

    @Test("A reserve too large for 64 bits is refused rather than wrapped")
    func reserveOverflowRefused() throws {
        #expect(throws: (any Error).self) {
            try ReserveConfiguration(
                asset: try Fixture.asset(decimals: 18),
                totalWholeUnits: UInt64.max / 2,
                streams: [ReserveStream(id: "a", share: .whole, denominator: 1, rule: .oncePerRecipient)],
                schedules: [Fixture.sixMonths()]
            )
        }
    }

    @Test("An unknown stream or schedule is named in the refusal")
    func unknownIds() throws {
        let reserve = try Fixture.reserve()
        #expect(throws: ReserveError.unknownStream("nope")) {
            try reserve.stream("nope")
        }
        #expect(throws: ReserveError.unknownStream("nope")) {
            try reserve.allocationBaseUnits("nope")
        }
        #expect(throws: ReserveError.unknownSchedule("nope")) {
            try reserve.schedule(id: "nope")
        }
    }

    // MARK: - Shares on their own

    @Test("A share divides exactly or answers nil")
    func shareArithmetic() {
        #expect(ReserveShare.percent(70).amount(of: 1_000) == 700)
        #expect(ReserveShare.whole.amount(of: 12_345) == 12_345)
        #expect(ReserveShare(1, of: 3).amount(of: 10) == nil)
        #expect(ReserveShare(1, of: 0).amount(of: 10) == nil)
        #expect(ReserveShare(1, of: 3).amount(of: 9) == 3)
        // Big numerators over a denominator that does not divide the total are
        // still exact when the product happens to divide.
        #expect(ReserveShare(3, of: 4).amount(of: 8) == 6)
        #expect(ReserveShare.percent(70).description == "70/100")
    }
}
