import Foundation
import Store
import Testing
@testable import Sweep

/// When the next sweep is due, and what a badly written interval does.
@Suite("Sweep scheduling")
struct SweepScheduleTests {

    @Test("A whole number of seconds inside the range is taken as written")
    func goodIntervalIsTaken() {
        let parsed = SweepSchedule.interval(from: "900")
        #expect(parsed.seconds == 900)
        #expect(parsed.rejected == nil)
    }

    @Test("Zero, a fraction, a word and a huge number all fall back and say so")
    func badIntervalsAreRejectedLoudly() {
        for raw in ["0", "30", "12.5", "soon", "-60", "99999999999999999999"] {
            let parsed = SweepSchedule.interval(from: raw)
            // Zero used to produce a tight loop that spent the day's chain
            // budget in minutes, and a word used to become the default in
            // silence.
            #expect(parsed.seconds == SweepSchedule.defaultInterval)
            #expect(parsed.rejected == raw)
        }
    }

    @Test("Nothing configured is the default, and is not a rejection")
    func nothingConfiguredIsNotARejection() {
        let parsed = SweepSchedule.interval(from: nil)
        #expect(parsed.seconds == SweepSchedule.defaultInterval)
        #expect(parsed.rejected == nil)
    }

    @Test("A sweep inside the window waits out the remainder")
    func recentSweepWaits() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let due = SweepSchedule.secondsUntilDue(
            lastSweep: now.addingTimeInterval(-600),
            now: now,
            interval: 1800
        )
        #expect(due == 1200)
    }

    @Test("No sweep on record, one long ago, or one in the future all sweep now")
    func anyDoubtSweepsNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SweepSchedule.secondsUntilDue(lastSweep: nil, now: now, interval: 1800) == nil)
        #expect(
            SweepSchedule.secondsUntilDue(
                lastSweep: now.addingTimeInterval(-3600),
                now: now,
                interval: 1800
            ) == nil
        )
        // A container that started with a bad clock is doubt, and doubt
        // sweeps rather than leaving everybody stale for the size of the skew.
        #expect(
            SweepSchedule.secondsUntilDue(
                lastSweep: now.addingTimeInterval(3600),
                now: now,
                interval: 1800
            ) == nil
        )
    }

    @Test("An interval below the floor or above the ceiling is clamped")
    func wholeSecondsClamps() {
        #expect(SweepSchedule.wholeSeconds(0) == SweepSchedule.minimumInterval)
        #expect(SweepSchedule.wholeSeconds(1800) == 1800)
        #expect(SweepSchedule.wholeSeconds(1800.9) == 1800)
        #expect(SweepSchedule.wholeSeconds(Double(UInt64.max)) == SweepSchedule.maximumInterval)
    }

    @Test("An interval that is not a number becomes the default, not either end")
    func nonsenseIntervalBecomesTheDefault() {
        // The floor would sweep every minute and spend the day's chain
        // budget by lunchtime; the ceiling would stop sweeping altogether.
        #expect(SweepSchedule.wholeSeconds(.infinity) == UInt64(SweepSchedule.defaultInterval))
        #expect(SweepSchedule.wholeSeconds(.nan) == UInt64(SweepSchedule.defaultInterval))
    }

    @Test("A sweep asks the journal how long ago the last one was")
    func dueTimeComesFromTheJournal() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let journal = InMemorySweepJournal()
        await journal.begin(SweepRecord(runId: "sweep-1", startedAt: now.addingTimeInterval(-300)))
        let sweep = RoleSweep(
            configuration: try Fixture.configuration(),
            directory: StaticSweepDirectory(members: []),
            store: InMemoryStore(),
            chain: RecordingChainReader([:]),
            gateway: SpyGateway(),
            journal: journal,
            limits: .unthrottled,
            now: { now }
        )

        // A restart used to sweep immediately, so a restart loop multiplied
        // the day's chain spend by the restart count.
        #expect(await sweep.secondsUntilDue(interval: 1800) == 1500)
    }
}
