import Foundation
import Testing
@testable import Games

/// The chip economy, which is a score and nothing else.
@Suite("Chips")
struct ChipsTests {

    @Test("The table constants are the ones the games actually play by")
    func constants() {
        #expect(Chips.starting == 200)
        #expect(Chips.minimumBet == 10)
        #expect(Chips.streakWinBase == 8)
        #expect(Chips.streakSteps == 8)
        #expect(Chips.baseDailyStipend == 40)
        #expect(Chips.defaultForageCooldown == 30)
        #expect(Chips.minimumForageCooldown == 8)
    }

    @Test("A run of wins pays a quarter more each time and then stops climbing")
    func streakPayoutSteps() {
        let steps: [Int] = (1...10).map { Chips.streakPayout(streakAfterWin: $0) }
        #expect(steps == [8, 10, 12, 14, 16, 18, 20, 22, 24, 24])
        #expect(Chips.streakPayout(streakAfterWin: 40) == 24)
    }

    // MARK: - The daily claim

    @Test("Somebody who holds nothing can still claim tomorrow")
    func stipendWithoutHoldings() throws {
        #expect(Chips.dailyClaim(.empty) == .payable(chips: 40))
        // Configured perks change nothing for somebody who holds none of them,
        // which is the ordinary case for most members of most servers.
        #expect(Chips.dailyClaim(.empty, perks: try Fixture.perks()) == .payable(chips: 40))
        // Positive whatever happens: the base is positive and no bonus can be
        // negative, so the claim is never a way to end the day poorer.
        #expect(Chips.baseDailyStipend > 0)
    }

    @Test("Every collection held adds its own bonus to the claim")
    func stipendSumsEveryBonus() throws {
        let perks = try Fixture.perks()
        let ids = [Fixture.founders, Fixture.companions, Fixture.wardens, Fixture.relics]
        let bonuses = [80, 25, 15, 10]
        for mask in 0..<16 {
            var held: Set<String> = []
            var expected = 40
            for (index, id) in ids.enumerated() where mask & (1 << index) != 0 {
                held.insert(id)
                expected += bonuses[index]
            }
            let holdings = GameHoldings(collectionIds: held, address: "ACCOUNT")
            #expect(Chips.dailyClaim(holdings, perks: perks) == .payable(chips: expected))
        }
        #expect(Chips.dailyClaim(Fixture.holding(Fixture.founders), perks: perks) == .payable(chips: 120))
        #expect(
            Chips.dailyClaim(
                Fixture.holding(Fixture.founders, Fixture.companions, Fixture.wardens, Fixture.relics),
                perks: perks
            ) == .payable(chips: 170)
        )
    }

    @Test("Holding a collection nobody configured a perk for changes nothing")
    func unknownCollectionIsIgnored() throws {
        let perks = try Fixture.perks()
        #expect(Chips.dailyClaim(Fixture.holding("something-else"), perks: perks) == .payable(chips: 40))
    }

    @Test("An absurd bonus gives an absurd claim rather than a dead process")
    func stipendSaturates() throws {
        let perks = try GamePerks([
            CollectionPerk(id: "one", dailyBonusChips: .max),
            CollectionPerk(id: "two", dailyBonusChips: .max)
        ])
        #expect(Chips.dailyClaim(Fixture.holding("one", "two"), perks: perks) == .payable(chips: .max))
    }

    // MARK: - The forage cooldown

    @Test("Collections shorten the wait between forages, and they stack")
    func cooldownStacks() throws {
        let perks = try Fixture.perks()
        #expect(Chips.forageCooldown(.empty, perks: perks) == 30)
        #expect(Chips.forageCooldown(Fixture.holding(Fixture.founders), perks: perks) == 15)
        #expect(Chips.forageCooldown(Fixture.holding(Fixture.companions), perks: perks) == 25.5)
        #expect(
            Chips.forageCooldown(
                Fixture.holding(Fixture.founders, Fixture.companions),
                perks: perks
            ) == 12.75
        )
    }

    @Test("The wait is floored at each step, not rounded once at the end")
    func cooldownFloorsPerStep() throws {
        let perks = try Fixture.perks()
        // 9.999s is 9999ms; times 0.85 is 8499.15ms, floored to 8499ms, never
        // rounded up. Flooring once at the end gives a different number.
        #expect(Chips.forageCooldown(Fixture.holding(Fixture.companions), perks: perks, base: 9.999) == 8.499)
    }

    @Test("No arrangement of collections gets a forage under the floor")
    func cooldownFloor() throws {
        let perks = try Fixture.perks()
        let both = Fixture.holding(Fixture.founders, Fixture.companions)
        #expect(Chips.forageCooldown(Fixture.holding(Fixture.companions), perks: perks, base: 9) == 8)
        #expect(Chips.forageCooldown(both, perks: perks, base: 10) == 8)
        #expect(Chips.forageCooldown(.empty, perks: perks, base: 1) == 8)
        #expect(Chips.forageCooldown(.empty, perks: perks, base: 0) == 8)
        #expect(Chips.forageCooldown(.empty, perks: perks, base: -5) == 8)
        #expect(Chips.forageCooldown(both, perks: perks, base: 600) == 255)
    }

    @Test("A wait too big to hold clamps to the longest, never to the shortest")
    func cooldownOverflowsUpwards() throws {
        // A factor this size is a host with too many zeroes, not an attack, and the
        // product overflows a Double. An overflowed wait is an enormous wait: the
        // clamp has to go up. Sending it to zero handed the host who asked for the
        // longest wait the eight-second floor, which is a button to hold down.
        let perks = try GamePerks([CollectionPerk(id: "slow", forageCooldownFactor: 1e308)])
        let waited = Chips.forageCooldown(Fixture.holding("slow"), perks: perks)
        #expect(waited == TimeInterval(Int.max) / 1000)
        #expect(waited > Chips.defaultForageCooldown)

        // Two of them, so the second multiplies a factor already at the ceiling.
        let stacked = try GamePerks([
            CollectionPerk(id: "slow", forageCooldownFactor: 1e308),
            CollectionPerk(id: "slower", forageCooldownFactor: 1e308)
        ])
        #expect(
            Chips.forageCooldown(Fixture.holding("slow", "slower"), perks: stacked)
                == TimeInterval(Int.max) / 1000
        )

        // A factor of zero is still a floor, not a ceiling: it asks for no wait at
        // all and gets the minimum.
        let instant = try GamePerks([CollectionPerk(id: "fast", forageCooldownFactor: 0)])
        #expect(Chips.forageCooldown(Fixture.holding("fast"), perks: instant) == Chips.minimumForageCooldown)
    }

    @Test("A perk that says nothing about the wait leaves it alone")
    func defaultFactorIsNeutral() throws {
        let perks = try GamePerks([CollectionPerk(id: "quiet")])
        #expect(Chips.forageCooldown(Fixture.holding("quiet"), perks: perks) == 30)
    }

    // MARK: - The day key

    @Test("The claim rolls over at midnight UTC wherever the process is running")
    func utcDayBoundary() {
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 0)) == "1970-01-01")
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 1_757_807_999)) == "2025-09-13")
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 1_757_808_000)) == "2025-09-14")
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 1_757_808_001)) == "2025-09-14")
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 1_757_894_399)) == "2025-09-14")
        #expect(Chips.utcDay(Date(timeIntervalSince1970: 1_757_894_400)) == "2025-09-15")
    }

    // MARK: - The zero floor

    @Test("A player can lose a hand but can never owe")
    func chipsFloorAtZero() {
        #expect(Chips.applying(-10, to: 200) == 190)
        #expect(Chips.applying(-500, to: 200) == 0)
        #expect(Chips.applying(-1, to: 0) == 0)
        #expect(Chips.applying(0, to: 0) == 0)
        #expect(Chips.applying(25, to: 0) == 25)
    }

    @Test("An absurd win or loss clamps rather than taking the table down")
    func chipsSaturate() {
        #expect(Chips.applying(.max, to: 10) == Int.max)
        #expect(Chips.applying(.min, to: 10) == 0)
    }
}
