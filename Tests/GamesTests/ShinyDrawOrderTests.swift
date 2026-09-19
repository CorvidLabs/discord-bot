import Foundation
import Testing
@testable import Games

/// The forage draw order, which is the game.
///
/// These are the tests that would fail if somebody "tidied up" ``Shiny/forage``.
/// Every case counts the draws an action spent as well as checking what it found,
/// because the draw count is the replay contract: a forage that spends a different
/// number of draws leaves the stream in a different place, and every table dealt
/// after it diverges. A find that happens to be right while the count is wrong is
/// not a passing test, it is a delayed failure.
///
/// The expected values here are the ones the engine this was ported from produces
/// for the same seeds. Reproducing them through configuration rather than through
/// hardcoded collections is the whole claim this port is making.
@Suite("Shiny draw order")
struct ShinyDrawOrderTests {

    private func forage(
        seed: UInt32,
        holding ids: [String] = [],
        perks: GamePerks
    ) -> (result: ReduceResult<ShinyState>, draws: UInt32, expected: (Int) -> UInt32) {
        var context = Fixture.context(
            seed: seed,
            holdings: ids.isEmpty ? .empty : GameHoldings(collectionIds: Set(ids), address: "ACCOUNT"),
            perks: perks
        )
        let result = Shiny.forage(Shiny.empty(cooldown: 0), context: &context)
        return (result, context.rng.state, { Fixture.stateAfterDraws(seed: seed, times: $0) })
    }

    // MARK: - Nothing configured

    @Test("With no perks configured a forage spends exactly one draw (ADOPT-3)")
    func noPerksSpendOneDraw() {
        let run = forage(seed: 4, perks: .empty)
        #expect(run.result.state.lastFind == .glass)
        #expect(run.result.chipDelta == 4)
        #expect(run.result.state.lastBonus == nil)
        #expect(run.draws == run.expected(1))
    }

    @Test("Configuring perks changes nothing for somebody who holds none of them")
    func configuringPerksDoesNotMoveTheStream() throws {
        // The trap this whole suite exists for. Making perks configurable makes the
        // draw sequence a function of the configuration, so a host who adds a
        // collection could silently change what every other member finds. It must
        // not: the extra draws belong only to the players who hold the thing.
        let configured = try Fixture.perks()
        var withPerks = Fixture.context(seed: 11, perks: configured)
        var without = Fixture.context(seed: 11, perks: .empty)
        var left = Shiny.empty(cooldown: 0)
        var right = Shiny.empty(cooldown: 0)
        var leftDeltas: [Int] = []
        var rightDeltas: [Int] = []
        for _ in 0..<50 {
            let a = Shiny.forage(left, context: &withPerks)
            let b = Shiny.forage(right, context: &without)
            left = a.state
            right = b.state
            leftDeltas.append(a.chipDelta)
            rightDeltas.append(b.chipDelta)
        }
        #expect(left == right)
        #expect(leftDeltas == rightDeltas)
        #expect(withPerks.rng.state == without.rng.state)
        #expect(withPerks.rng.state == Fixture.stateAfterDraws(seed: 11, times: 50))
    }

    @Test("Holding a collection nobody wrote a perk for spends no extra draw")
    func unknownCollectionSpendsNothing() throws {
        let run = forage(seed: 4, holding: ["not-configured"], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .glass)
        #expect(run.draws == run.expected(1))
    }

    // MARK: - Rerolls

    @Test("A reroll that lands costs the coin and the second roll")
    func rerollThatLands() throws {
        let run = forage(seed: 7, holding: [Fixture.founders], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .gold)
        #expect(run.result.chipDelta == 25)
        #expect(run.result.state.lastBonus == "Founders reroll.")
        #expect(Fixture.pouch(run.result.state) == [.gold: 1])
        // The find, the coin that decides the reroll, then the reroll itself.
        #expect(run.draws == run.expected(3))
    }

    @Test("A reroll that misses still costs the coin")
    func rerollThatMisses() throws {
        // This is the case a well-meaning refactor breaks: the coin is spent and
        // its answer thrown away, which looks like dead code and is not.
        let run = forage(seed: 8, holding: [Fixture.founders], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .twig)
        #expect(run.result.chipDelta == 0)
        #expect(run.result.state.lastBonus == nil)
        #expect(run.draws == run.expected(2))
    }

    @Test("A find the reroll does not cover costs no coin at all")
    func rerollNotTriggered() throws {
        let run = forage(seed: 4, holding: [Fixture.founders], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .silver)
        #expect(run.result.chipDelta == 10)
        #expect(run.result.state.lastBonus == nil)
        #expect(run.draws == run.expected(1))
    }

    @Test("A perk with no reroll spends no coin however poor the find")
    func noRerollNoCoin() throws {
        let perks = try GamePerks([CollectionPerk(id: "quiet", dailyBonusChips: 5)])
        let run = forage(seed: 8, holding: ["quiet"], perks: perks)
        #expect(run.result.state.lastFind == .twig)
        #expect(run.draws == run.expected(1))
    }

    // MARK: - Free finds

    @Test("A free find goes in the pouch, pays nothing, and spends no draw")
    func freeFind() throws {
        let run = forage(seed: 4, holding: [Fixture.wardens], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .glass)
        #expect(run.result.chipDelta == 4)
        #expect(run.result.state.lastBonus == "Wardens tucked in a twig.")
        #expect(Fixture.pouch(run.result.state) == [.twig: 1, .glass: 1])
        #expect(run.draws == run.expected(1))
    }

    // MARK: - Extra finds

    @Test("An extra find fills the pouch and pays nothing for itself")
    func extraFindThatLands() throws {
        let run = forage(seed: 7, holding: [Fixture.companions], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .twig)
        // The twig pays nothing, and the silver the extra find turned up pays
        // nothing either, even though a silver found first-hand is worth ten.
        #expect(run.result.chipDelta == 0)
        #expect(run.result.state.lastBonus == "Companions found Silver.")
        #expect(Fixture.pouch(run.result.state) == [.twig: 1, .silver: 1])
        #expect(Shiny.nestScore(run.result.state) == 16)
        #expect(run.draws == run.expected(3))
    }

    @Test("An extra find that misses still costs its coin")
    func extraFindThatMisses() throws {
        let run = forage(seed: 2, holding: [Fixture.companions], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .pebble)
        #expect(run.result.chipDelta == 0)
        #expect(run.result.state.lastBonus == nil)
        #expect(run.draws == run.expected(2))
    }

    // MARK: - The whole sequence

    @Test("Every stage firing at once spends five draws in one fixed order")
    func everyStageFires() throws {
        let run = forage(
            seed: 186,
            holding: [Fixture.founders, Fixture.companions, Fixture.wardens],
            perks: try Fixture.perks()
        )
        #expect(run.result.state.lastFind == .glass)
        #expect(run.result.chipDelta == 4)
        #expect(
            run.result.state.lastBonus
                == "Founders reroll. Wardens tucked in a twig. Companions found Feather."
        )
        #expect(Fixture.pouch(run.result.state) == [.twig: 1, .feather: 1, .glass: 1])
        // Find, reroll coin, reroll, extra-find coin, extra find. The bonus line
        // reads in stage order too, which is how a member can tell what happened.
        #expect(run.draws == run.expected(5))
    }

    @Test("A locked kind turns up once a collection unlocks it")
    func unlockedKind() throws {
        let run = forage(seed: 43, holding: [Fixture.relics], perks: try Fixture.perks())
        #expect(run.result.state.lastFind == .rune)
        #expect(run.result.chipDelta == 12)
        #expect(Fixture.pouch(run.result.state) == [.rune: 1])
        #expect(run.draws == run.expected(1))
    }

    @Test("One seed and one configuration produce one sequence, every time")
    func sequenceIsPinned() throws {
        // The replay pin. If this list moves, a stored table no longer deals what
        // it dealt, and the seed printed on a card no longer proves anything.
        let perks = try Fixture.perks()
        let holdings = Fixture.holding(Fixture.founders, Fixture.companions, Fixture.wardens)
        var context = Fixture.context(seed: 1_234, holdings: holdings, perks: perks)
        var state = Shiny.empty(cooldown: 0)
        var finds: [ShinyKind] = []
        var deltas: [Int] = []
        for _ in 0..<12 {
            let result = Shiny.forage(state, context: &context)
            state = result.state
            deltas.append(result.chipDelta)
            if let find = result.state.lastFind {
                finds.append(find)
            }
        }
        let firstRun = (finds: finds, deltas: deltas, pouch: Fixture.pouch(state), rng: context.rng.state)

        var replay = Fixture.context(seed: 1_234, holdings: holdings, perks: perks)
        var replayed = Shiny.empty(cooldown: 0)
        var replayFinds: [ShinyKind] = []
        var replayDeltas: [Int] = []
        for _ in 0..<12 {
            let result = Shiny.forage(replayed, context: &replay)
            replayed = result.state
            replayDeltas.append(result.chipDelta)
            if let find = result.state.lastFind {
                replayFinds.append(find)
            }
        }
        #expect(replayFinds == firstRun.finds)
        #expect(replayDeltas == firstRun.deltas)
        #expect(Fixture.pouch(replayed) == firstRun.pouch)
        #expect(replay.rng.state == firstRun.rng)

        // And the sequence itself, written out, so a change to the order is a
        // failing diff rather than a silent one.
        #expect(
            finds == [
                .twig, .gold, .twig, .twig, .gold, .feather,
                .feather, .glass, .gold, .feather, .twig, .glass
            ]
        )
        #expect(deltas == [0, 25, 0, 0, 25, 0, 0, 4, 25, 0, 0, 4])
    }

    @Test("The host's order decides the sequence, so reordering perks is a real change")
    func configurationOrderIsPartOfTheContract() throws {
        // Two perks that both reroll a twig. Whichever the host wrote first gets
        // its coin first, so its name is the one on the bonus line. This is not a
        // wart: it is the reason the order is configuration rather than a hash.
        let first = CollectionPerk(
            id: "a",
            name: "Alpha",
            reroll: PerkReroll(probability: 1, kinds: [.twig])
        )
        let second = CollectionPerk(
            id: "b",
            name: "Beta",
            reroll: PerkReroll(probability: 1, kinds: [.twig])
        )
        let holdings = Fixture.holding("a", "b")

        var forwards = Fixture.context(seed: 8, holdings: holdings, perks: try GamePerks([first, second]))
        let forwardResult = Shiny.forage(Shiny.empty(cooldown: 0), context: &forwards)
        var backwards = Fixture.context(seed: 8, holdings: holdings, perks: try GamePerks([second, first]))
        let backwardResult = Shiny.forage(Shiny.empty(cooldown: 0), context: &backwards)

        #expect(forwardResult.state.lastBonus?.hasPrefix("Alpha reroll.") == true)
        #expect(backwardResult.state.lastBonus?.hasPrefix("Beta reroll.") == true)
        // Both spent the same draws, because the stages are the same stages.
        #expect(forwards.rng.state == backwards.rng.state)
    }

    @Test("A perk that is only a daily bonus never touches the loot stream")
    func nonLootPerkIsInert() throws {
        let perks = try GamePerks([
            CollectionPerk(id: "generous", dailyBonusChips: 500, forageCooldownFactor: 0.25)
        ])
        var withIt = Fixture.context(seed: 21, holdings: Fixture.holding("generous"), perks: perks)
        var without = Fixture.context(seed: 21)
        var left = Shiny.empty(cooldown: 0)
        var right = Shiny.empty(cooldown: 0)
        for _ in 0..<20 {
            left = Shiny.forage(left, context: &withIt).state
            right = Shiny.forage(right, context: &without).state
        }
        #expect(Fixture.pouch(left) == Fixture.pouch(right))
        #expect(withIt.rng.state == without.rng.state)
    }
}
