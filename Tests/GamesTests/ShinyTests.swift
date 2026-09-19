import Foundation
import Testing
@testable import Games

/// Foraging, the pouch, and the nest ladder.
@Suite("Shiny")
struct ShinyTests {

    // MARK: - Shape

    @Test("A new pouch is empty, at nest one, and ready to forage")
    func emptyPouch() {
        let start = Shiny.empty(cooldown: 30)
        #expect(start.nestLevel == 1)
        #expect(start.lastForageAt == nil)
        #expect(start.lastFind == nil)
        #expect(start.lastBonus == nil)
        #expect(start.cooldown == 30)
        #expect(start.inventory.count == ShinyKind.allCases.count)
        for kind in ShinyKind.allCases {
            #expect(start.count(kind) == 0)
        }
        #expect(Shiny.nestScore(start) == 0)
        #expect(Shiny.legalActions(start) == ["forage", "upgrade"])
        #expect(Shiny.remainingCooldown(start, now: Fixture.now) == 0)
    }

    @Test("Common junk pays no chips; only the rarer finds do")
    func junkTable() {
        #expect(Shiny.meta[.twig]?.value == 1)
        #expect(Shiny.meta[.twig]?.chips == 0)
        #expect(Shiny.meta[.feather]?.value == 3)
        #expect(Shiny.meta[.feather]?.chips == 0)
        #expect(Shiny.meta[.pebble]?.value == 2)
        #expect(Shiny.meta[.pebble]?.chips == 0)
        #expect(Shiny.meta[.beetle]?.value == 5)
        #expect(Shiny.meta[.beetle]?.chips == 2)
        #expect(Shiny.meta[.glass]?.value == 8)
        #expect(Shiny.meta[.glass]?.chips == 4)
        #expect(Shiny.meta[.silver]?.value == 15)
        #expect(Shiny.meta[.silver]?.chips == 10)
        #expect(Shiny.meta[.gold]?.value == 40)
        #expect(Shiny.meta[.gold]?.chips == 25)
        #expect(Shiny.meta[.rune]?.value == 24)
        #expect(Shiny.meta[.rune]?.chips == 12)
        for kind in ShinyKind.allCases {
            #expect(Shiny.meta[kind] != nil)
        }
    }

    @Test("Each rung of the nest ladder costs more junk than the last")
    func nestLadder() {
        #expect(Shiny.maxNestLevel == 5)
        #expect(Shiny.nestCosts.map { $0.level } == [2, 3, 4, 5])
        #expect(Shiny.nestCosts[0].cost == [.twig: 8])
        #expect(Shiny.nestCosts[1].cost == [.twig: 12, .feather: 6])
        #expect(Shiny.nestCosts[2].cost == [.twig: 16, .feather: 8, .pebble: 6])
        #expect(Shiny.nestCosts[3].cost == [.twig: 20, .feather: 10, .glass: 3, .silver: 1])
    }

    @Test("A pouch survives the round trip a stored player goes through")
    func codableRoundTrip() throws {
        var context = Fixture.context(seed: 4)
        let found = Shiny.forage(Shiny.empty(cooldown: 30), context: &context).state
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShinyState.self, from: try encoder.encode(found))
        #expect(decoded == found)
        #expect(decoded.count(.glass) == 1)
        #expect(decoded.lastFind == .glass)
    }

    // MARK: - Foraging with nothing held

    @Test("A forage pays the chips of what it found and stamps the clock")
    func plainForage() {
        var context = Fixture.context(seed: 4)
        let result = Shiny.forage(Shiny.empty(cooldown: 30), context: &context)
        #expect(result.chipDelta == 4)
        #expect(result.note == nil)
        #expect(result.state.lastFind == .glass)
        #expect(result.state.lastBonus == nil)
        #expect(result.state.lastForageAt == Fixture.now)
        #expect(Fixture.pouch(result.state) == [.glass: 1])
        #expect(Shiny.nestScore(result.state) == 8)
        #expect(context.rng.state == Fixture.stateAfterDraws(seed: 4, times: 1))
    }

    @Test("A run of forages pays only for the rare finds")
    func aRunOfForages() {
        var context = Fixture.context(seed: 1)
        var state = Shiny.empty(cooldown: 0)
        var deltas: [Int] = []
        var finds: [ShinyKind] = []
        for _ in 0..<5 {
            let result = Shiny.forage(state, context: &context)
            state = result.state
            deltas.append(result.chipDelta)
            if let find = result.state.lastFind {
                finds.append(find)
            }
        }
        #expect(finds == [.pebble, .twig, .feather, .silver, .silver])
        #expect(deltas == [0, 0, 0, 10, 10])
        #expect(Fixture.pouch(state) == [.twig: 1, .feather: 1, .pebble: 1, .silver: 2])
        #expect(Shiny.nestScore(state) == 36)
    }

    @Test("The locked kind never turns up for somebody with no collections")
    func lockedKindStaysLocked() {
        var context = Fixture.context(seed: 2)
        var state = Shiny.empty(cooldown: 0)
        for _ in 0..<200 {
            state = Shiny.forage(state, context: &context).state
        }
        #expect(state.count(.rune) == 0)
    }

    @Test("A configuration that zeroes the whole table still does not unlock the rare one")
    func mutedTableStaysLocked() throws {
        // Zero is a legal weight, so a host can write a perk that zeroes every
        // kind, by hand or by multiplying a table down. The pick then has nothing
        // positive to land on, and it used to fall through to the last index, which
        // is the one kind documented as unreachable and the second-best payer in
        // the table.
        let muted = try GamePerks([
            CollectionPerk(
                id: "muted",
                weightAdjustments: ShinyKind.allCases.map {
                    LootWeightAdjustment(kind: $0, operation: .set(0))
                }
            )
        ])
        let holdings = Fixture.holding("muted")
        #expect(Shiny.weights(perks: muted.active(for: holdings)) == Array(repeating: 0, count: 8))

        var context = Fixture.context(seed: 3, holdings: holdings, perks: muted)
        var state = Shiny.empty(cooldown: 0)
        var paid = 0
        for _ in 0..<50 {
            let found = Shiny.forage(state, context: &context)
            state = found.state
            paid += found.chipDelta
        }
        #expect(state.count(.rune) == 0)
        #expect(state.count(.twig) == 50)
        #expect(paid == 0)
    }

    // MARK: - The cooldown

    @Test("A forage too soon is refused, and only the line under it changes")
    func cooldownRefusal() {
        var context = Fixture.context(seed: 4)
        let found = Shiny.forage(Shiny.empty(cooldown: 30), context: &context).state
        let spent = context.rng.state

        var later = GameContext(
            now: Fixture.now.addingTimeInterval(10),
            player: context.player,
            rng: context.rng
        )
        let refused = Shiny.forage(found, context: &later)

        var expected = found
        expected.lastBonus = "Ready again in 20s."
        #expect(refused.chipDelta == 0)
        #expect(refused.state == expected)
        #expect(Fixture.pouch(refused.state) == [.glass: 1])
        // No draw is spent on a refusal, so a member tapping a cooling button
        // cannot walk the stream on under their own next find.
        #expect(later.rng.state == spent)
    }

    @Test("Part of a second still reads as a second to wait")
    func cooldownRoundsUp() {
        var context = Fixture.context(seed: 4)
        let found = Shiny.forage(Shiny.empty(cooldown: 30), context: &context).state
        var later = GameContext(
            now: Fixture.now.addingTimeInterval(29.25),
            player: context.player,
            rng: context.rng
        )
        #expect(Shiny.forage(found, context: &later).state.lastBonus == "Ready again in 1s.")
        #expect(Shiny.remainingCooldown(found, now: Fixture.now.addingTimeInterval(29.25)) == 0.75)
    }

    @Test("On the boundary the forage goes ahead")
    func cooldownBoundary() {
        var context = Fixture.context(seed: 4)
        let found = Shiny.forage(Shiny.empty(cooldown: 30), context: &context)
        var later = GameContext(
            now: Fixture.now.addingTimeInterval(30),
            player: context.player,
            rng: context.rng
        )
        let again = Shiny.forage(found.state, context: &later)
        #expect(again.chipDelta == 0)
        #expect(again.state.lastFind == .twig)
        #expect(again.state.lastForageAt == Fixture.now.addingTimeInterval(30))
        #expect(Fixture.pouch(again.state) == [.twig: 1, .glass: 1])
        #expect(later.rng.state == Fixture.stateAfterDraws(seed: 4, times: 2))
    }

    @Test("Somebody who has never foraged is ready, and a zero wait never blocks")
    func cooldownEdges() {
        let never = Shiny.empty(cooldown: 30)
        #expect(Shiny.remainingCooldown(never, now: Fixture.now) == 0)
        var flown = never
        flown.lastForageAt = Fixture.now
        #expect(Shiny.remainingCooldown(flown, now: Fixture.now) == 30)
        #expect(Shiny.remainingCooldown(flown, now: Fixture.now.addingTimeInterval(45)) == 0)
        var instant = flown
        instant.cooldown = 0
        #expect(Shiny.remainingCooldown(instant, now: Fixture.now) == 0)
    }

    // MARK: - The nest ladder

    @Test("An upgrade with too little junk changes nothing and says what is missing")
    func upgradeShortPouch() {
        var state = Shiny.empty(cooldown: 30)
        state.inventory["twig"] = 7
        let result = Shiny.upgrade(state)
        #expect(result.chipDelta == 0)
        #expect(result.note == "Need 8 twigs.")
        #expect(result.state == state)
        #expect(result.state.nestLevel == 1)
    }

    @Test("A shortage is named with a plural somebody would actually write")
    func shortageNamesAPlural() {
        var state = Shiny.empty(cooldown: 30)
        state.nestLevel = 4
        state.inventory["twig"] = 20
        state.inventory["feather"] = 10
        state.inventory["silver"] = 1
        // Glass is short before silver is, and the kinds are checked in table order
        // so the note is stable rather than whichever a dictionary offered first.
        #expect(Shiny.upgrade(state).note == "Need 3 glass.")
    }

    @Test("An upgrade burns its ingredients and raises the nest")
    func upgradeSpendsJunk() {
        var state = Shiny.empty(cooldown: 30)
        state.inventory["twig"] = 10
        state.inventory["feather"] = 2
        let result = Shiny.upgrade(state)
        #expect(result.chipDelta == 0)
        #expect(result.note == nil)
        #expect(result.state.nestLevel == 2)
        #expect(result.state.lastBonus == "Nest rose to 2.")
        #expect(Fixture.pouch(result.state) == [.twig: 2, .feather: 2])
        #expect(Shiny.nestScore(result.state) == 16)
    }

    @Test("The ladder runs to the top and then refuses to rise")
    func ladderToTheTop() {
        var state = Shiny.empty(cooldown: 30)
        state.inventory["twig"] = 100
        state.inventory["feather"] = 50
        state.inventory["pebble"] = 20
        state.inventory["glass"] = 10
        state.inventory["silver"] = 5
        for level in 2...5 {
            let result = Shiny.upgrade(state)
            #expect(result.chipDelta == 0)
            #expect(result.note == nil)
            #expect(result.state.nestLevel == level)
            state = result.state
        }
        #expect(Fixture.pouch(state) == [.twig: 44, .feather: 26, .pebble: 14, .glass: 7, .silver: 4])
        #expect(Shiny.nestScore(state) == 1330)
        #expect(Shiny.legalActions(state) == ["forage"])

        let maxed = Shiny.upgrade(state)
        #expect(maxed.note == "The nest is as high as it goes.")
        #expect(maxed.state == state)
        #expect(maxed.chipDelta == 0)
    }

    @Test("Raising the nest never moves a chip in either direction")
    func upgradesAreFreeOfChips() {
        var state = Shiny.empty(cooldown: 30)
        state.inventory["twig"] = 100
        for _ in 0..<5 {
            #expect(Shiny.upgrade(state).chipDelta == 0)
            state = Shiny.upgrade(state).state
        }
    }

    @Test("Foraging still works at the top of the ladder")
    func forageAtMaxNest() {
        var state = Shiny.empty(cooldown: 0)
        state.nestLevel = 5
        var context = Fixture.context(seed: 4)
        let result = Shiny.forage(state, context: &context)
        #expect(result.chipDelta == 4)
        #expect(result.state.nestLevel == 5)
        #expect(Shiny.nestScore(result.state) == 40)
        #expect(Shiny.legalActions(result.state) == ["forage"])
    }

    // MARK: - The card

    @Test("An empty pouch draws a card with the forage button live")
    func cardForEmptyPouch() {
        let context = Fixture.context(seed: 1)
        let card = Shiny.card(Shiny.empty(cooldown: 30), context: context)
        #expect(card.title == "Shiny")
        #expect(card.description == "Last find: **nothing yet**. Nest level 1. Score 0.")
        #expect(card.fields.count == 1)
        #expect(card.fields[0].name == "Pouch")
        #expect(card.fields[0].value == "Empty.")
        #expect(card.footer == "What you find stays in the pouch. Nothing cashes out.")
        #expect(card.buttons.count == 2)
        #expect(card.buttons[0].id == "ng_shiny_forage")
        #expect(card.buttons[0].label == "Forage")
        #expect(!card.buttons[0].disabled)
        #expect(card.buttons[1].id == "ng_shiny_upgrade")
        #expect(card.buttons[1].label == "Upgrade nest, spends junk")
    }

    @Test("A cooling pouch greys the button and shows the wait")
    func cardWhileCooling() {
        var context = Fixture.context(seed: 4)
        let found = Shiny.forage(Shiny.empty(cooldown: 30), context: &context)
        let card = Shiny.card(found.state, context: context)
        #expect(card.description == "Last find: **Glass**. Nest level 1. Score 8.")
        #expect(card.fields[0].value == "Glass 1")
        #expect(card.buttons[0].label == "Cooling down")
        #expect(card.buttons[0].disabled)

        var later = GameContext(
            now: Fixture.now.addingTimeInterval(10),
            player: context.player,
            rng: context.rng
        )
        let refused = Shiny.forage(found.state, context: &later)
        let waiting = Shiny.card(refused.state, context: later)
        #expect(
            waiting.description
                == "Last find: **Glass**. Nest level 1. Score 8.\nReady again in 20s."
        )
        #expect(waiting.buttons[0].disabled)
    }

    @Test("The pouch line lists the kinds in table order")
    func cardPouchOrder() {
        var state = Shiny.empty(cooldown: 0)
        state.inventory["twig"] = 2
        state.inventory["silver"] = 1
        state.inventory["rune"] = 1
        state.nestLevel = 3
        state.lastFind = .rune
        let card = Shiny.card(state, context: Fixture.context(seed: 1))
        #expect(card.fields[0].value == "Twig 2 \u{00b7} Silver 1 \u{00b7} Rune shard 1")
        #expect(card.description == "Last find: **Rune shard**. Nest level 3. Score 123.")
        #expect(card.buttons[0].label == "Forage")
        #expect(!card.buttons[0].disabled)
    }

    @Test("A card carries the player's own picture and nobody else's")
    func cardPicture() {
        let holdings = GameHoldings(collectionIds: [], address: "ACCOUNT", pictureUrl: "https://example.test/a.png")
        let context = Fixture.context(seed: 1, holdings: holdings)
        #expect(Shiny.card(Shiny.empty(cooldown: 0), context: context).thumbnailUrl == "https://example.test/a.png")
        #expect(Shiny.card(Shiny.empty(cooldown: 0), context: Fixture.context(seed: 1)).thumbnailUrl == nil)
    }
}
