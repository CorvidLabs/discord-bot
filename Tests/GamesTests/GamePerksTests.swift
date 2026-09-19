import Foundation
import Testing
@testable import Games

/// Perk configuration: what a host writes down, and what it refuses.
///
/// A host finds out they have set this up wrongly when the process starts, not
/// when a member notices their forage behaving oddly (`ADOPT-2`).
@Suite("Game perks")
struct GamePerksTests {

    // MARK: - Shape

    @Test("A server that owns no collections has a perfectly valid configuration")
    func emptyIsOrdinary() {
        #expect(GamePerks.empty.isEmpty)
        #expect(GamePerks.empty.ordered.isEmpty)
        #expect(GamePerks.empty.active(for: Fixture.holding("anything")).isEmpty)
        #expect(GamePerks.empty.perk("anything") == nil)
    }

    @Test("A perk that says nothing does nothing")
    func defaultsAreNeutral() throws {
        let perk = CollectionPerk(id: "quiet")
        #expect(perk.name == "quiet")
        #expect(perk.dailyBonusChips == 0)
        #expect(perk.forageCooldownFactor == 1)
        #expect(perk.weightAdjustments.isEmpty)
        #expect(perk.reroll == nil)
        #expect(perk.freeFind == nil)
        #expect(perk.extraFind == nil)

        let perks = try GamePerks([perk])
        let holdings = Fixture.holding("quiet")
        #expect(Chips.dailyStipend(holdings, perks: perks) == Chips.baseDailyStipend)
        #expect(Chips.forageCooldown(holdings, perks: perks) == Chips.defaultForageCooldown)
        #expect(Shiny.weights(perks: perks.active(for: holdings)) == Shiny.weights(perks: []))
    }

    @Test("Only the collections somebody holds earn them anything")
    func activeFiltersByHoldings() throws {
        let perks = try Fixture.perks()
        #expect(perks.active(for: .empty).isEmpty)
        #expect(perks.active(for: Fixture.holding(Fixture.wardens)).map(\.id) == [Fixture.wardens])
        #expect(perks.perk(Fixture.relics)?.name == "Relics")
        #expect(perks.perk("missing") == nil)
    }

    @Test("Perks apply in the order they were written down, not in holdings order")
    func configurationOrderWins() throws {
        // The same two perks, configured the other way round. A player holding both
        // gets them in the host's order either way, because a holdings set has no
        // order a replay could depend on.
        let forwards = try GamePerks([Fixture.foundersPerk(), Fixture.companionsPerk()])
        let backwards = try GamePerks([Fixture.companionsPerk(), Fixture.foundersPerk()])
        let holdings = Fixture.holding(Fixture.companions, Fixture.founders)
        #expect(forwards.active(for: holdings).map(\.id) == [Fixture.founders, Fixture.companions])
        #expect(backwards.active(for: holdings).map(\.id) == [Fixture.companions, Fixture.founders])

        // And a set built in a different order is the same set.
        let other = GameHoldings(
            collectionIds: Set([Fixture.founders, Fixture.companions]),
            address: "ACCOUNT"
        )
        #expect(forwards.active(for: other).map(\.id) == forwards.active(for: holdings).map(\.id))
    }

    // MARK: - Refusals

    @Test("Two perks claiming one collection is refused, naming the id")
    func duplicateIdsRefuse() {
        #expect(throws: GameConfigurationError.duplicateCollectionId("twice")) {
            try GamePerks([CollectionPerk(id: "twice"), CollectionPerk(id: "twice")])
        }
    }

    @Test("A perk with no id could never match anything, so it is refused")
    func blankIdRefuses() {
        #expect(throws: GameConfigurationError.emptyCollectionId) {
            try GamePerks([CollectionPerk(id: "   ")])
        }
    }

    @Test("An id with whitespace round it is refused, not quietly trimmed or kept")
    func paddedIdRefuses() {
        // Ids are matched exactly, so a padded one is a perk that validates, raises
        // nothing, and can never fire. Refused at the configuration, which is where
        // the host can see it, rather than three weeks later in somebody's forage.
        #expect(throws: GameConfigurationError.paddedCollectionId(collectionId: " founders ")) {
            try GamePerks([CollectionPerk(id: " founders ", dailyBonusChips: 50)])
        }
        #expect(throws: GameConfigurationError.paddedCollectionId(collectionId: "founders\n")) {
            try GamePerks([CollectionPerk(id: "founders\n")])
        }
    }

    @Test("An id the configuration would have normalised is refused, not left to never fire")
    func unnormalizedIdRefuses() {
        // The silent failure this refusal exists for. A host reads one variable
        // for the whole product, the rest of it normalises the name to
        // `founders_pass`, and this perk is handed the name as typed. It is
        // non-empty, unpadded and unique, so nothing else here objects, and it
        // then matches no holding for as long as the server runs.
        #expect(throws: GameConfigurationError.unnormalizedCollectionId(collectionId: "Founders Pass")) {
            try GamePerks([CollectionPerk(id: "Founders Pass", dailyBonusChips: 50)])
        }
        for typed in ["the founders", "FOUNDERS", "Founders", "founders-pass", "founders.pass", "#1"] {
            #expect(throws: GameConfigurationError.unnormalizedCollectionId(collectionId: typed)) {
                try GamePerks([CollectionPerk(id: typed)])
            }
        }
    }

    @Test("Every shape a normalised id can take is accepted, so nobody correct is refused")
    func normalizedIdsAreAccepted() {
        // Lowercase letters, digits and underscores, which is everything a
        // normaliser can produce. The accented and non-Latin ids are here on
        // purpose: a normaliser lowercases a name and keeps its letters, so
        // "Café" survives as `café`, and an ASCII-only rule would refuse a server
        // that had configured itself correctly.
        let shapes = [
            "founders",
            "founders_pass",
            "second_edition_2",
            "a1",
            "2024_drop",
            "caf\u{00e9}",
            "cafe\u{0301}",
            "\u{043a}\u{043e}\u{043b}\u{043b}\u{0435}\u{043a}\u{0446}\u{0438}\u{044f}",
            "_leading",
            "trailing_"
        ]
        for shape in shapes {
            #expect(throws: Never.self) {
                try GamePerks([CollectionPerk(id: shape)])
            }
        }
    }

    @Test("A bonus that takes chips away is refused rather than paid")
    func negativeBonusRefuses() {
        #expect(throws: GameConfigurationError.negativeDailyBonus(collectionId: "bad", value: -5)) {
            try GamePerks([CollectionPerk(id: "bad", dailyBonusChips: -5)])
        }
    }

    @Test("A nonsensical cooldown factor is refused, naming the collection")
    func badCooldownRefuses() {
        #expect(throws: GameConfigurationError.invalidCooldownFactor(collectionId: "bad", value: -1)) {
            try GamePerks([CollectionPerk(id: "bad", forageCooldownFactor: -1)])
        }
        #expect(
            throws: GameConfigurationError.invalidCooldownFactor(
                collectionId: "bad",
                value: Double.infinity
            )
        ) {
            try GamePerks([CollectionPerk(id: "bad", forageCooldownFactor: .infinity)])
        }
    }

    @Test("A nonsensical loot weight is refused, naming the kind")
    func badWeightRefuses() {
        #expect(
            throws: GameConfigurationError.invalidWeight(
                collectionId: "bad",
                kind: "gold",
                value: -2
            )
        ) {
            try GamePerks([
                CollectionPerk(
                    id: "bad",
                    weightAdjustments: [LootWeightAdjustment(kind: .gold, operation: .add(-2))]
                )
            ])
        }
    }

    @Test("A chance outside nought to one is refused, naming the setting")
    func badProbabilityRefuses() {
        #expect(
            throws: GameConfigurationError.invalidProbability(
                collectionId: "bad",
                setting: "the reroll chance",
                value: 1.5
            )
        ) {
            try GamePerks([
                CollectionPerk(id: "bad", reroll: PerkReroll(probability: 1.5, kinds: [.twig]))
            ])
        }
        #expect(
            throws: GameConfigurationError.invalidProbability(
                collectionId: "bad",
                setting: "the extra-find chance",
                value: -0.1
            )
        ) {
            try GamePerks([CollectionPerk(id: "bad", extraFind: PerkExtraFind(probability: -0.1))])
        }
    }

    @Test("A reroll nothing can trigger is a typo, so it is refused")
    func emptyRerollRefuses() {
        #expect(throws: GameConfigurationError.emptyRerollTrigger(collectionId: "bad")) {
            try GamePerks([CollectionPerk(id: "bad", reroll: PerkReroll(probability: 0.5, kinds: []))])
        }
    }

    @Test("Every refusal says which collection and which setting to fix")
    func refusalsNameTheFix() {
        let messages: [String] = [
            GameConfigurationError.emptyCollectionId,
            .paddedCollectionId(collectionId: " founders "),
            .unnormalizedCollectionId(collectionId: "Founders Pass"),
            .duplicateCollectionId("twice"),
            .negativeDailyBonus(collectionId: "bad", value: -5),
            .invalidCooldownFactor(collectionId: "bad", value: -1),
            .invalidWeight(collectionId: "bad", kind: "gold", value: -2),
            .invalidProbability(collectionId: "bad", setting: "the reroll chance", value: 2),
            .emptyRerollTrigger(collectionId: "bad")
        ].map { $0.errorDescription ?? "" }
        for message in messages {
            #expect(!message.isEmpty)
        }
        #expect(messages[1].contains(" founders "))
        #expect(messages[2].contains("Founders Pass"))
        #expect(messages[2].contains("lowercase"))
        #expect(messages[3].contains("twice"))
        #expect(messages[6].contains("gold"))
        #expect(messages[7].contains("the reroll chance"))
    }

    // MARK: - Loot weights

    @Test("The base loot table leaves the locked kind unreachable")
    func baseWeights() {
        #expect(Shiny.weights(perks: []) == [40, 22, 16, 10, 7, 3.5, 1.5, 0])
        #expect(Shiny.baseWeight(.rune) == 0)
    }

    @Test("Adjustments apply in order, so a multiply and an add mean one thing")
    func adjustmentsApplyInOrder() throws {
        let doubleThenAdd = CollectionPerk(
            id: "a",
            weightAdjustments: [
                LootWeightAdjustment(kind: .twig, operation: .multiply(2)),
                LootWeightAdjustment(kind: .twig, operation: .add(10))
            ]
        )
        let addThenDouble = CollectionPerk(
            id: "a",
            weightAdjustments: [
                LootWeightAdjustment(kind: .twig, operation: .add(10)),
                LootWeightAdjustment(kind: .twig, operation: .multiply(2))
            ]
        )
        #expect(Shiny.weights(perks: [doubleThenAdd])[0] == 90)
        #expect(Shiny.weights(perks: [addThenDouble])[0] == 100)
    }

    @Test("Only a set can unlock a kind sitting at zero, and two holders do not stack it")
    func setUnlocksAndDoesNotStack() throws {
        let one = CollectionPerk(
            id: "a",
            weightAdjustments: [LootWeightAdjustment(kind: .rune, operation: .set(3))]
        )
        let two = CollectionPerk(
            id: "b",
            weightAdjustments: [LootWeightAdjustment(kind: .rune, operation: .set(3))]
        )
        #expect(Shiny.weights(perks: [one]).last == 3)
        #expect(Shiny.weights(perks: [one, two]).last == 3)
        // Multiplying a zero cannot raise it, which is what "locked" means.
        let futile = CollectionPerk(
            id: "c",
            weightAdjustments: [LootWeightAdjustment(kind: .rune, operation: .multiply(100))]
        )
        #expect(Shiny.weights(perks: [futile]).last == 0)
    }
}
