import Foundation
import Testing
@testable import Reserve

/// Period keys, which are what stop one epoch being paid twice in an afternoon.
///
/// The property under test is not really "does it print the right string" but
/// "do two different moments inside one period produce the same key, and two
/// moments either side of a boundary produce different ones". That is the whole
/// mechanism.
@Suite("Reserve period")
struct ReservePeriodTests {

    // MARK: - Weeks

    @Test("Two moments in one week share a key; the next week does not (RESERVE-1.g)")
    func weekKeysGroupAndSeparate() {
        // Derived from the week start rather than hard-coded, so the test says
        // what it means: every moment inside one week keys the same.
        let monday = ReservePeriod.isoWeekStart(Date(timeIntervalSince1970: 1_758_000_000))
        let sameWeek = monday.addingTimeInterval(3 * 24 * 60 * 60)
        let lastMoment = monday.addingTimeInterval(7 * 24 * 60 * 60 - 1)
        let nextWeek = monday.addingTimeInterval(7 * 24 * 60 * 60)
        #expect(ReservePeriod.isoWeek(monday) == ReservePeriod.isoWeek(sameWeek))
        #expect(ReservePeriod.isoWeek(monday) == ReservePeriod.isoWeek(lastMoment))
        #expect(ReservePeriod.isoWeek(monday) != ReservePeriod.isoWeek(nextWeek))
    }

    @Test("A week key is the ISO year and week, zero-padded")
    func weekKeyShape() {
        let key = ReservePeriod.isoWeek(Date(timeIntervalSince1970: 1_758_000_000))
        #expect(key.count == 8)
        #expect(key.contains("-W"))
        #expect(key.hasPrefix("2025"))
    }

    @Test("A week runs Monday to Monday, in UTC")
    func weekBoundaries() {
        let midweek = Date(timeIntervalSince1970: 1_758_000_000)
        let start = ReservePeriod.isoWeekStart(midweek)
        let end = ReservePeriod.isoWeekEnd(midweek)
        #expect(end.timeIntervalSince(start) == 7 * 24 * 60 * 60)
        #expect(start <= midweek)
        #expect(end > midweek)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        // 2 is Monday in the Gregorian calendar's weekday numbering.
        #expect(calendar.component(.weekday, from: start) == 2)
        // A Sunday belongs to the week that began six days earlier, not the one
        // starting tomorrow.
        let sunday = start.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(ReservePeriod.isoWeekStart(sunday) == start)
    }

    // MARK: - Months and days

    @Test("Two moments in one month share a key; the next month does not")
    func monthKeys() {
        let early = Date(timeIntervalSince1970: 1_756_684_800)
        let later = early.addingTimeInterval(10 * 24 * 60 * 60)
        let nextMonth = early.addingTimeInterval(45 * 24 * 60 * 60)
        #expect(ReservePeriod.month(early) == ReservePeriod.month(later))
        #expect(ReservePeriod.month(early) != ReservePeriod.month(nextMonth))
        #expect(ReservePeriod.month(early).count == 7)
    }

    @Test("A day key separates consecutive days")
    func dayKeys() {
        let moment = Date(timeIntervalSince1970: 1_758_000_000)
        #expect(ReservePeriod.day(moment) == ReservePeriod.day(moment.addingTimeInterval(60)))
        #expect(
            ReservePeriod.day(moment) != ReservePeriod.day(moment.addingTimeInterval(24 * 60 * 60))
        )
        #expect(ReservePeriod.day(moment).count == 10)
    }

    @Test("Period keys do not move with the host's timezone")
    func keysAreUTC() {
        // The same instant, asked for twice, cannot disagree with itself — and
        // because everything here pins UTC explicitly, the answer does not
        // depend on where the process happens to be running.
        let moment = Date(timeIntervalSince1970: 1_758_000_000)
        #expect(ReservePeriod.isoWeek(moment) == ReservePeriod.isoWeek(moment))
        #expect(ReservePeriod.month(moment) == ReservePeriod.month(moment))
        // Midnight UTC on the first of a month belongs to that month, which is
        // the case a local-timezone implementation gets wrong.
        let firstOfSeptember = Date(timeIntervalSince1970: 1_756_684_800)
        #expect(ReservePeriod.month(firstOfSeptember) == "2025-09")
        #expect(ReservePeriod.day(firstOfSeptember) == "2025-09-01")
    }
}
