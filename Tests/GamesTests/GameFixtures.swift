import Foundation
import Testing
@testable import Games

/// Fixtures for the game suites.
///
/// The four perks below are a **worked example of a host's configuration**, not
/// anything this package ships. They are shaped deliberately: between them they
/// exercise every perk field, and their numbers are the ones the engine this was
/// ported from hardcoded for its own two collections. Reproducing those numbers
/// through configuration is how the port proves it did not change the game while
/// it was making the game configurable.
enum Fixture {

    /// A fixed instant. Every case pins the clock so a cooldown is arithmetic
    /// rather than a race.
    static let now = Date(timeIntervalSince1970: 1_757_808_000)

    static let founders = "founders"
    static let companions = "companions"
    static let wardens = "wardens"
    static let relics = "relics"

    /// A perk that rerolls poor finds, thins the commons and fattens the rares.
    static func foundersPerk() -> CollectionPerk {
        CollectionPerk(
            id: founders,
            name: "Founders",
            dailyBonusChips: 80,
            forageCooldownFactor: 0.5,
            weightAdjustments: [
                LootWeightAdjustment(kind: .twig, operation: .multiply(0.6)),
                LootWeightAdjustment(kind: .gold, operation: .add(1.5)),
                LootWeightAdjustment(kind: .silver, operation: .add(2)),
                LootWeightAdjustment(kind: .glass, operation: .add(2))
            ],
            reroll: PerkReroll(probability: 0.5, kinds: [.twig, .pebble])
        )
    }

    /// A perk that sometimes turns up a second find.
    static func companionsPerk() -> CollectionPerk {
        CollectionPerk(
            id: companions,
            name: "Companions",
            dailyBonusChips: 25,
            forageCooldownFactor: 0.85,
            weightAdjustments: [
                LootWeightAdjustment(kind: .feather, operation: .add(8)),
                LootWeightAdjustment(kind: .beetle, operation: .add(4))
            ],
            extraFind: PerkExtraFind(probability: 0.2)
        )
    }

    /// A perk that tucks a free twig in on every forage and spends no draw.
    static func wardensPerk() -> CollectionPerk {
        CollectionPerk(id: wardens, name: "Wardens", dailyBonusChips: 15, freeFind: .twig)
    }

    /// A perk that unlocks a kind sitting at a base weight of zero.
    static func relicsPerk() -> CollectionPerk {
        CollectionPerk(
            id: relics,
            name: "Relics",
            dailyBonusChips: 10,
            weightAdjustments: [LootWeightAdjustment(kind: .rune, operation: .set(3))]
        )
    }

    /// All four, in the order the loot weights are meant to be applied in.
    static func perks() throws -> GamePerks {
        try GamePerks([foundersPerk(), companionsPerk(), wardensPerk(), relicsPerk()])
    }

    /// Holdings naming collections by id.
    static func holding(_ ids: String...) -> GameHoldings {
        GameHoldings(collectionIds: Set(ids), address: "ACCOUNT")
    }

    /// A seeded table for one player.
    static func context(
        seed: UInt32,
        holdings: GameHoldings = .empty,
        perks: GamePerks = .empty,
        chips: Int = 200,
        at instant: Date? = nil
    ) -> GameContext {
        GameContext(
            now: instant ?? now,
            player: GamePlayer(id: "player-1", name: "Wren", chips: chips, holdings: holdings),
            perks: perks,
            rng: GameRNG(seed: seed)
        )
    }

    /// The generator state after `times` draws from `seed`.
    ///
    /// How many draws an action spent is the replay contract, so it is asserted
    /// directly rather than inferred from what the action found.
    static func stateAfterDraws(seed: UInt32, times: Int) -> UInt32 {
        var rng = GameRNG(seed: seed)
        for _ in 0..<times {
            _ = rng.next()
        }
        return rng.state
    }

    /// Only the kinds actually in the pouch, for readable expectations.
    static func pouch(_ state: ShinyState) -> [ShinyKind: Int] {
        var held: [ShinyKind: Int] = [:]
        for kind in ShinyKind.allCases where state.count(kind) > 0 {
            held[kind] = state.count(kind)
        }
        return held
    }

    /// Card faces, for readable expectations.
    static func labels(_ cards: [Card]) -> [String] {
        cards.map(\.label)
    }
}
