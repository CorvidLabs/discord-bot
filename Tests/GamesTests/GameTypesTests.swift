import Foundation
import Testing
@testable import Games

/// The values the games are made of, and the promises they carry.
@Suite("Game types")
struct GameTypesTests {

    @Test("Holding nothing and having linked nothing is a valid way to play")
    func emptyHoldings() {
        let holdings = GameHoldings.empty
        #expect(holdings.collectionIds.isEmpty)
        #expect(holdings.address == "")
        #expect(holdings.pictureUrl == nil)
        #expect(!holdings.holds("anything"))
        #expect(holdings == GameHoldings())
    }

    @Test("Holdings name collections by the host's own ids")
    func holdingsById() {
        let holdings = Fixture.holding("passes", "founders")
        #expect(holdings.holds("passes"))
        #expect(holdings.holds("founders"))
        #expect(!holdings.holds("PASSES"))
        #expect(holdings.address == "ACCOUNT")
    }

    @Test("Holdings survive a round trip through storage")
    func holdingsRoundTrip() throws {
        let holdings = GameHoldings(
            collectionIds: ["a", "b"],
            address: "ACCOUNT",
            pictureUrl: "https://example.test/a.png"
        )
        let data = try JSONEncoder().encode(holdings)
        #expect(try JSONDecoder().decode(GameHoldings.self, from: data) == holdings)
    }

    @Test("A context carries the clock, the player, the perks and the stream")
    func contextCarriesEverything() throws {
        let player = GamePlayer(id: "1", name: "Wren", chips: 200)
        let context = GameContext(
            now: Fixture.now,
            player: player,
            perks: try Fixture.perks(),
            rng: GameRNG(seed: 42)
        )
        #expect(context.now == Fixture.now)
        #expect(context.player.chips == 200)
        #expect(context.player.holdings == .empty)
        #expect(context.rng.state == 42)
        #expect(context.perks.ordered.count == 4)
        #expect(context.activePerks.isEmpty)
    }

    @Test("A context with nothing said about perks has none, which is fine")
    func contextDefaultsToNoPerks() {
        let context = Fixture.context(seed: 1)
        #expect(context.perks.isEmpty)
        #expect(context.activePerks.isEmpty)
    }

    @Test("The only thing an action can move is a number of chips")
    func reduceResultCarriesOneNumber() {
        // The whole money story of this package, in one type. There is one field
        // that moves anything, it is an `Int` of a score, and the module has no
        // dependency that could turn it into something that sends (`PLAY-1.a`).
        let staked = ReduceResult<Int>(state: 3, chipDelta: -10)
        #expect(staked.state == 3)
        #expect(staked.chipDelta == -10)
        #expect(staked.note == nil)

        let won = ReduceResult<Int>(state: 4, chipDelta: 8, note: "Call won")
        #expect(won.note == "Call won")
    }

    @Test("A card fills in the parts nobody asked for")
    func messageDefaults() {
        let message = GameMessage(
            title: "Higher or Lower",
            description: "Higher or lower?",
            color: 0x9370db,
            buttons: [
                GameButton(id: "highlow:higher", label: "Higher", style: .success),
                GameButton(id: "", label: "Rules", style: .link, url: "https://example.test/rules")
            ]
        )
        #expect(message.fields.isEmpty)
        #expect(message.footer == nil)
        #expect(message.thumbnailUrl == nil)
        #expect(message.hand.isEmpty)
        #expect(message.buttons[0].url == nil)
        #expect(!message.buttons[0].disabled)
        // A link button carries no id, because navigation never comes back as an
        // interaction to route.
        #expect(message.buttons[1].id == "")
        #expect(message.buttons[1].style == .link)
        #expect(GameButtonStyle.link.rawValue == "link")
        #expect(!GameField(name: "Chips", value: "200").inline)
    }

    @Test("Every game names its chips chips, and none of them names them a nest")
    func theVocabularyIsChips() throws {
        // The word this package will not use for the currency. It once meant the
        // chips, the collectible ladder, the profile card and a button all at
        // once, and a sentence using it could not be read.
        var context = Fixture.context(seed: 2, chips: 3)
        let broke = Blackjack.card(Blackjack.initial(context: &context), context: context)
        #expect(broke.description.contains("chips"))
        #expect(!broke.description.lowercased().contains("nest"))
        #expect(Blackjack.brokeRoute.contains("chips"))
        #expect(!Blackjack.brokeRoute.lowercased().contains("nest"))

        var table = Fixture.context(seed: 2)
        let dealt = Blackjack.deal(Blackjack.initial(context: &table), amount: 10, context: &table)
        #expect(Blackjack.card(dealt.state, context: table).description.contains("chips"))

        var high = Fixture.context(seed: 0)
        let opened = HighLow.card(HighLow.initial(context: &high))
        #expect(!opened.description.lowercased().contains("nest"))

        // The one place the word is allowed is the collectible ladder, where it
        // is the name of the thing being built.
        let pouch = Shiny.card(Shiny.empty(cooldown: 0), context: Fixture.context(seed: 1))
        #expect(pouch.description.contains("Nest level"))
        #expect(pouch.buttons[1].label == "Upgrade nest, spends junk")
    }

    @Test("Nothing anywhere in the engine offers to turn chips into anything else")
    func chipsDoNotConvert() throws {
        // A crude but honest check on the member-visible copy: the words somebody
        // would have to read before they believed a cash-out was possible.
        var context = Fixture.context(seed: 2, chips: 3)
        var strings: [String] = [Blackjack.brokeRoute]
        strings.append(Blackjack.card(Blackjack.initial(context: &context), context: context).description)
        strings.append(Shiny.card(Shiny.empty(cooldown: 0), context: context).footer ?? "")
        var high = Fixture.context(seed: 0)
        strings.append(HighLow.card(HighLow.initial(context: &high)).description)
        for text in strings {
            let lowered = text.lowercased()
            #expect(!lowered.contains("withdraw"))
            #expect(!lowered.contains("cash out"))
            #expect(!lowered.contains("wallet"))
            #expect(!lowered.contains("token"))
        }
        #expect(Shiny.card(Shiny.empty(cooldown: 0), context: context).footer?.contains("Nothing cashes out.") == true)
    }
}
