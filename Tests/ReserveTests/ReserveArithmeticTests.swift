import Foundation
import Testing
@testable import Reserve

/// The arithmetic, pinned in smallest units.
///
/// Every figure here is exact. Nothing is approximated, nothing is compared with
/// a tolerance, and nothing goes near a `Double`, which is the property under
/// test as much as the numbers are.
@Suite("Reserve arithmetic")
struct ReserveArithmeticTests {

    // MARK: - The reserve and its split

    @Test("The reserve splits into streams that add up to all of it, exactly (RESERVE-1.b)")
    func reserveSplit() throws {
        let reserve = try Fixture.reserve()
        #expect(reserve.totalBaseUnits == Fixture.whole(10_000_000_000))
        let members = try reserve.allocationBaseUnits(Fixture.members)
        let passes = try reserve.allocationBaseUnits(Fixture.passes)
        #expect(members == Fixture.whole(7_000_000_000))
        #expect(passes == Fixture.whole(3_000_000_000))
        #expect(members + passes == reserve.totalBaseUnits)
    }

    @Test("Denominators are fixed constants, not the eligible count (RESERVE-3.a)")
    func fixedDenominators() throws {
        let reserve = try Fixture.reserve()
        #expect(try reserve.stream(Fixture.members).denominator == 1_000)
        #expect(try reserve.stream(Fixture.passes).denominator == 4_096)
    }

    @Test("A slot's full-schedule share divides exactly in smallest units (RESERVE-5.a)")
    func sharesDivideExactly() throws {
        let reserve = try Fixture.reserve()
        for stream in reserve.streams {
            let allocation = try reserve.allocationBaseUnits(stream.id)
            #expect(allocation % stream.denominator == 0)
        }
        #expect(try reserve.shareBaseUnits(Fixture.members) == Fixture.whole(7_000_000))
        // 3,000,000,000 / 4,096 = 732,421.875, which is exact at six decimals.
        #expect(try reserve.shareBaseUnits(Fixture.passes) == 732_421_875_000)
    }

    // MARK: - Duration

    @Test("A schedule is a count of epochs and the catalog is configuration (RESERVE-2.a)")
    func epochCounts() throws {
        let reserve = try Fixture.reserve()
        #expect(try reserve.schedule(id: "6m").epochCount == 26)
        #expect(try reserve.schedule(id: "1y").epochCount == 52)
        #expect(try reserve.schedule(id: "6m").cadence == "weekly")
        #expect(try reserve.schedule(id: "6m").summary == "six months · 26 weekly epochs")
    }

    @Test("A duration is named, never guessed (RESERVE-2.d)")
    func scheduleMatching() throws {
        let reserve = try Fixture.reserve()
        #expect(try reserve.schedule(matching: "6m").id == "6m")
        #expect(try reserve.schedule(matching: "26").id == "6m")
        #expect(try reserve.schedule(matching: " Six Months ").id == "6m")
        #expect(try reserve.schedule(matching: "six-months").id == "6m")
        #expect(try reserve.schedule(matching: "1y").id == "1y")
        #expect(try reserve.schedule(matching: "52").id == "1y")
        #expect(try reserve.schedule(matching: "one year").id == "1y")
        #expect(try reserve.schedule(matching: "12m").id == "1y")
        // Nothing falls back to a default: an unrecognised duration refuses.
        #expect(throws: ReserveError.unknownSchedule("3m")) {
            try reserve.schedule(matching: "3m")
        }
        #expect(throws: ReserveError.unknownSchedule("")) {
            try reserve.schedule(matching: "")
        }
    }

    @Test("Duration changes the per-epoch figure, never the total per slot (RESERVE-2.b)")
    func durationDoesNotChangeTheTotal() throws {
        let reserve = try Fixture.reserve()
        for stream in reserve.streams {
            let share = try reserve.shareBaseUnits(stream.id)
            for schedule in reserve.schedules {
                let split = try reserve.epochSplit(streamId: stream.id, schedule: schedule)
                // The entitlement is identical on every schedule. What is
                // actually paid differs only by the residue, which is always
                // smaller than one smallest unit per epoch.
                #expect(split.shareBaseUnits == share)
                #expect(split.residueBaseUnits < schedule.epochCount)
            }
        }
        let six = try reserve.epochSplit(streamId: Fixture.members, schedule: Fixture.sixMonths())
        let year = try reserve.epochSplit(streamId: Fixture.members, schedule: Fixture.oneYear())
        #expect(six.perEpochBaseUnits > year.perEpochBaseUnits)
        // The member stream happens to leave the same 20 units either way; the
        // pass stream does not, so its paid total moves by 26 smallest units
        // between the two durations. That gap is the residue, and it is stated.
        #expect(six.totalBaseUnits == year.totalBaseUnits)
        let passSix = try reserve.epochSplit(streamId: Fixture.passes, schedule: Fixture.sixMonths())
        let passYear = try reserve.epochSplit(streamId: Fixture.passes, schedule: Fixture.oneYear())
        #expect(passSix.totalBaseUnits - passYear.totalBaseUnits == 26)
    }

    // MARK: - Per-epoch figures

    @Test("A once-per-recipient slot is paid the same figure every epoch, both durations")
    func memberPayouts() throws {
        let reserve = try Fixture.reserve()
        // 7,000,000 whole units over 26 epochs, floored. The 20 smallest units
        // that will not divide are residue and are never paid.
        let six = try reserve.epochPayoutBaseUnits(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            epoch: 1
        )
        #expect(six == 269_230_769_230)
        #expect(
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 26
            ) == six
        )

        let year = try reserve.epochPayoutBaseUnits(
            streamId: Fixture.members,
            schedule: Fixture.oneYear(),
            epoch: 1
        )
        #expect(year == 134_615_384_615)
        #expect(
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.members,
                schedule: Fixture.oneYear(),
                epoch: 52
            ) == year
        )
    }

    @Test("A per-unit slot is paid the same figure every epoch, both durations")
    func passPayouts() throws {
        let reserve = try Fixture.reserve()
        let six = try reserve.epochPayoutBaseUnits(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths(),
            epoch: 1
        )
        #expect(six == 28_170_072_115)
        #expect(
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.passes,
                schedule: Fixture.sixMonths(),
                epoch: 26
            ) == six
        )

        let year = try reserve.epochPayoutBaseUnits(
            streamId: Fixture.passes,
            schedule: Fixture.oneYear(),
            epoch: 1
        )
        #expect(year == 14_085_036_057)
        #expect(
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.passes,
                schedule: Fixture.oneYear(),
                epoch: 52
            ) == year
        )
    }

    @Test("Every epoch of a schedule pays the identical figure (RESERVE-5.b)")
    func everyEpochPaysTheSame() throws {
        let reserve = try Fixture.reserve()
        for stream in reserve.streams {
            for schedule in reserve.schedules {
                let split = try reserve.epochSplit(streamId: stream.id, schedule: schedule)
                let first = split.payout(epoch: 1)
                for epoch in 1...schedule.epochCount {
                    #expect(split.payout(epoch: epoch) == first)
                }
            }
        }
    }

    @Test("An epoch outside the schedule is refused, not clamped (RESERVE-5.f)")
    func epochRangeIsChecked() throws {
        let reserve = try Fixture.reserve()
        #expect(throws: ReserveError.epochOutOfRange(epoch: 0, count: 26)) {
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 0
            )
        }
        #expect(throws: ReserveError.epochOutOfRange(epoch: 27, count: 26)) {
            try reserve.epochPayoutBaseUnits(
                streamId: Fixture.members,
                schedule: Fixture.sixMonths(),
                epoch: 27
            )
        }
        // A split asked directly pays nothing rather than clamping into range.
        let split = try reserve.epochSplit(streamId: Fixture.members, schedule: Fixture.sixMonths())
        #expect(split.payout(epoch: 99) == 0)
        #expect(split.payout(epoch: 0) == 0)
    }

    // MARK: - Residue reconciliation

    @Test("Paid plus residue equals the share exactly, every stream, every schedule (RESERVE-5.d, RESERVE-9.c)")
    func residueReconciles() throws {
        let reserve = try Fixture.reserve()
        for stream in reserve.streams {
            for schedule in reserve.schedules {
                let split = try reserve.epochSplit(streamId: stream.id, schedule: schedule)
                var paidPerSlot: UInt64 = 0
                for epoch in 1...schedule.epochCount {
                    paidPerSlot += split.payout(epoch: epoch)
                }
                #expect(paidPerSlot == split.totalBaseUnits)
                #expect(
                    paidPerSlot + split.residueBaseUnits == (try reserve.shareBaseUnits(stream.id))
                )
                // And across a fully claimed denominator, every smallest unit of
                // the allocation is accounted for.
                let paid = paidPerSlot * stream.denominator
                let residue = split.residueBaseUnits * stream.denominator
                #expect(paid + residue == (try reserve.allocationBaseUnits(stream.id)))
                #expect(paid < (try reserve.allocationBaseUnits(stream.id)))
            }
        }
    }

    @Test("The residue is stated, not swallowed (RESERVE-5.c)")
    func residueIsVisible() throws {
        let reserve = try Fixture.reserve()
        let members = try reserve.epochSplit(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths()
        )
        #expect(members.residueBaseUnits == 20)
        #expect(members.isEven == false)
        let note = members.residueNote(asset: reserve.asset, unitName: "member")
        #expect(note.contains("20"))
        #expect(note.contains("stay in the reserve"))

        let passes = try reserve.epochSplit(streamId: Fixture.passes, schedule: Fixture.oneYear())
        #expect(passes.residueBaseUnits == 36)
        #expect(passes.residueNote(asset: reserve.asset, unitName: "pass").contains("36"))

        // Six months leaves 10 smallest units per pass, 0.04096 whole across the
        // whole collection of 4,096.
        let passesSix = try reserve.epochSplit(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths()
        )
        #expect(passesSix.residueBaseUnits == 10)
        #expect(passesSix.residueBaseUnits * 4_096 == 40_960)
    }

    @Test("A share that divides evenly says so rather than inventing a residue")
    func evenSplitHasNoResidue() throws {
        let reserve = try ReserveConfiguration(
            asset: try Fixture.asset(decimals: 2),
            totalWholeUnits: 1_000,
            streams: [
                ReserveStream(id: "all", share: .whole, denominator: 10, rule: .oncePerRecipient)
            ],
            schedules: [ReserveSchedule(id: "10", epochCount: 10)]
        )
        let split = try reserve.epochSplit(streamId: "all", schedule: try reserve.schedule(id: "10"))
        #expect(split.isEven)
        #expect(split.residueBaseUnits == 0)
        #expect(split.residueNote(asset: reserve.asset, unitName: "slot").contains("no residue"))
    }

    // MARK: - Projections

    @Test("Eligible counts project the stated spend, and nothing is lost (RESERVE-7.b)")
    func memberProjections() throws {
        let reserve = try Fixture.reserve()
        let cases: [(eligible: UInt64, inUse: UInt64, unspent: UInt64)] = [
            (50, 350_000_000, 6_650_000_000),
            (215, 1_505_000_000, 5_495_000_000),
            (1_000, 7_000_000_000, 0)
        ]
        for schedule in reserve.schedules {
            for row in cases {
                let projection = try reserve.project(
                    streamId: Fixture.members,
                    schedule: schedule,
                    eligibleUnits: row.eligible
                )
                #expect(projection.allocationInUseBaseUnits == Fixture.whole(row.inUse))
                #expect(projection.unusedAllocationBaseUnits == Fixture.whole(row.unspent))
                // In use plus unclaimed is the whole allocation, and spend plus
                // residue is what is in use.
                #expect(
                    projection.allocationInUseBaseUnits + projection.unusedAllocationBaseUnits
                        == (try reserve.allocationBaseUnits(Fixture.members))
                )
                #expect(
                    projection.projectedSpendBaseUnits + projection.projectedResidueBaseUnits
                        == projection.allocationInUseBaseUnits
                )
                #expect(
                    projection.staysInReserveBaseUnits
                        == (try reserve.allocationBaseUnits(Fixture.members))
                            - projection.projectedSpendBaseUnits
                )
            }
        }
        // 20 smallest units per slot stay behind, however long the schedule is.
        let full = try reserve.project(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            eligibleUnits: 1_000
        )
        #expect(full.projectedResidueBaseUnits == 20_000)
        #expect(full.projectedSpendBaseUnits == Fixture.whole(7_000_000_000) - 20_000)
    }

    @Test("A fully claimed per-unit stream puts its whole allocation to use")
    func combinedProjection() throws {
        let reserve = try Fixture.reserve()
        let audit = try reserve.audit(
            schedule: Fixture.oneYear(),
            eligibleUnits: [Fixture.members: 215, Fixture.passes: 4_096]
        )
        #expect(
            audit.projection(Fixture.members)?.allocationInUseBaseUnits
                == Fixture.whole(1_505_000_000)
        )
        #expect(
            audit.projection(Fixture.passes)?.allocationInUseBaseUnits
                == Fixture.whole(3_000_000_000)
        )
        #expect(audit.allocationInUseBaseUnits == Fixture.whole(1_505_000_000 + 3_000_000_000))
        #expect(audit.unusedReserveBaseUnits == Fixture.whole(10_000_000_000 - 4_505_000_000))
        #expect(
            audit.projectedSpendBaseUnits + audit.projectedResidueBaseUnits
                == audit.allocationInUseBaseUnits
        )
    }

    @Test("Unclaimed slots stay unclaimed and change nobody's payment (RESERVE-3.c)")
    func unusedSlotsAreNotRedistributed() throws {
        let reserve = try Fixture.reserve()
        let sparse = try reserve.project(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            eligibleUnits: 50
        )
        let full = try reserve.project(
            streamId: Fixture.members,
            schedule: Fixture.sixMonths(),
            eligibleUnits: 1_000
        )
        #expect(sparse.unusedSlots == 950)
        #expect(full.unusedSlots == 0)
        // The same per-slot figure either way: 950 empty slots buy nobody more.
        #expect(sparse.perUnitShareBaseUnits == full.perUnitShareBaseUnits)
        #expect(sparse.perUnitPayoutBaseUnits(epoch: 4) == full.perUnitPayoutBaseUnits(epoch: 4))
        #expect(sparse.unusedAllocationBaseUnits == Fixture.whole(6_650_000_000))
    }

    @Test("A payment depends on the epoch and nothing else (RESERVE-3.b)")
    func payoutIsFixed() throws {
        let reserve = try Fixture.reserve()
        for eligible in [UInt64(1), 50, 215, 999, 1_000] {
            let projection = try reserve.project(
                streamId: Fixture.members,
                schedule: Fixture.oneYear(),
                eligibleUnits: eligible
            )
            #expect(projection.perUnitPayoutBaseUnits(epoch: 1) == 134_615_384_615)
            #expect(projection.perUnitPayoutBaseUnits(epoch: 40) == 134_615_384_615)
            #expect(projection.perUnitShareBaseUnits == Fixture.whole(7_000_000))
        }
    }

    @Test("Eligible units past the denominator are reported, never paid (RESERVE-3.d)")
    func overflowIsReportedNotPaid() throws {
        let reserve = try Fixture.reserve()
        let projection = try reserve.project(
            streamId: Fixture.passes,
            schedule: Fixture.sixMonths(),
            eligibleUnits: 5_000
        )
        #expect(projection.overflowUnits == 904)
        // Even asked about 5,000, the projection never crosses the allocation.
        #expect(projection.allocationInUseBaseUnits == Fixture.whole(3_000_000_000))
        #expect(projection.projectedSpendBaseUnits < Fixture.whole(3_000_000_000))
    }

    // MARK: - Runway and limit cost

    @Test("The runway says how many more epochs the pot covers (RESERVE-7.c)")
    func runwayCounting() {
        #expect(ReserveConfiguration.runwayEpochs(potBaseUnits: 1_000, epochSpendBaseUnits: 250) == 4)
        #expect(ReserveConfiguration.runwayEpochs(potBaseUnits: 999, epochSpendBaseUnits: 250) == 3)
        #expect(ReserveConfiguration.runwayEpochs(potBaseUnits: 0, epochSpendBaseUnits: 250) == 0)
        // Nothing due has no runway. A sentinel here once flowed into
        // `nextEpoch + runway` on a card and overflowed.
        #expect(ReserveConfiguration.runwayEpochs(potBaseUnits: 5, epochSpendBaseUnits: 0) == nil)
    }

    @Test("A short pot is visible on the preview and blocks nothing (RESERVE-7.c)")
    func runwayOnTheAudit() throws {
        let reserve = try Fixture.reserve()
        let epochCost: UInt64 = 269_230_769_230 * 10
        let audit = try reserve.audit(
            schedule: Fixture.sixMonths(),
            eligibleUnits: [Fixture.members: 10, Fixture.passes: 0],
            nextEpoch: [Fixture.members: 1, Fixture.passes: 1],
            potBaseUnits: epochCost * 3
        )
        #expect(audit.nextEpochSpendBaseUnits == epochCost)
        #expect(audit.runwayEpochs == 3)
        #expect(audit.epochsRemaining == 26)

        // No pot read at all: no runway, and nothing refused.
        let unread = try reserve.audit(
            schedule: Fixture.sixMonths(),
            eligibleUnits: [Fixture.members: 10]
        )
        #expect(unread.runwayEpochs == nil)
    }

    @Test("Limit cost rounds up per payment, never once on the total")
    func limitCostRoundsUp() throws {
        let asset = try Fixture.asset()
        #expect(asset.wholeUnitsRoundingUp(baseUnits: 269_230_769_230) == 269_231)
        #expect(asset.wholeUnitsRoundingUp(baseUnits: 1_000_000) == 1)
        #expect(asset.wholeUnitsRoundingUp(baseUnits: 1) == 1)
        #expect(asset.wholeUnitsRoundingUp(baseUnits: 0) == 0)

        let reserve = try Fixture.reserve()
        let audit = try reserve.audit(
            schedule: Fixture.sixMonths(),
            eligibleUnits: [Fixture.members: 50, Fixture.passes: 0],
            nextEpoch: [Fixture.members: 1, Fixture.passes: 1]
        )
        // 50 × ceil(269,230.76923) = 50 × 269,231 = 13,461,550. One round-up of
        // the total would say 13,461,539: understating the charge on the very
        // figure whose job is to warn about the limit.
        #expect(audit.nextEpochLimitCostWholeUnits == 13_461_550)
    }

    @Test("A caller-supplied epoch of zero does not take the process down (RESERVE-5.f)")
    func epochsRemainingDoesNotTrap() throws {
        let reserve = try Fixture.reserve()
        let audit = try reserve.audit(
            schedule: Fixture.sixMonths(),
            eligibleUnits: [Fixture.members: 1, Fixture.passes: 1],
            nextEpoch: [Fixture.members: 0, Fixture.passes: 0]
        )
        #expect(audit.epochsRemaining == 26)
    }

    @Test("With no duration chosen the preview says so rather than guessing")
    func auditWithoutSchedule() throws {
        let reserve = try Fixture.reserve()
        let audit = try reserve.audit(
            schedule: nil,
            eligibleUnits: [Fixture.members: 3, Fixture.passes: 4]
        )
        #expect(audit.selectedSchedule == nil)
        // It still illustrates, with the first configured duration.
        #expect(audit.effectiveSchedule.id == "6m")
        #expect(audit.epochsRemaining == 0)
    }

    @Test("An incomplete preview is marked as one that would abort (RESERVE-7.e)")
    func auditFlagsIncompleteReads() throws {
        let reserve = try Fixture.reserve()
        let audit = try reserve.audit(
            schedule: Fixture.sixMonths(),
            eligibleUnits: [Fixture.members: 10],
            incompleteRecipients: [Fixture.members: 3, Fixture.passes: 0]
        )
        #expect(audit.totalIncompleteRecipients == 3)
        #expect(audit.wouldAbortLiveRun)
    }

    // MARK: - Formatting

    @Test("Amounts keep every digit and never touch a Double (RESERVE-5.a, RESERVE-5.e)")
    func formatting() throws {
        let asset = try Fixture.asset()
        #expect(asset.format(269_230_769_230) == "269,230.76923")
        #expect(asset.format(269_230_769_231) == "269,230.769231")
        #expect(asset.format(Fixture.whole(3_000_000_000)) == "3,000,000,000")
        #expect(asset.format(0) == "0")
        #expect(asset.formatWithSymbol(1_500_000) == "1.5 TOKEN")
        #expect(ReserveFormatting.grouped(1_000) == "1,000")
        #expect(ReserveFormatting.grouped(4_096) == "4,096")
        #expect(ReserveFormatting.grouped(7) == "7")
        #expect(ReserveFormatting.grouped(0) == "0")
    }

    @Test("A silly decimals argument returns raw units instead of trapping (RESERVE-5.f)")
    func formatterDoesNotTrap() {
        #expect(ReserveFormatting.amount(1_234, decimals: 20) == "1,234")
        #expect(ReserveFormatting.amount(1_234, decimals: 0) == "1,234")
        #expect(ReserveFormatting.amount(1_234, decimals: -1) == "1,234")
        #expect(ReserveFormatting.amount(1_000_000_000_000_000_000, decimals: 19) == "0.1")
    }

    @Test("A zero-decimal asset is a perfectly good asset")
    func zeroDecimalAsset() throws {
        let points = try ReserveAsset(symbol: "POINTS", decimals: 0)
        #expect(points.baseUnitsPerWholeUnit == 1)
        #expect(try points.baseUnits(whole: 25) == 25)
        #expect(points.wholeUnitsRoundingUp(baseUnits: 25) == 25)
        #expect(points.format(1_234) == "1,234")
    }
}
