import Foundation
import Testing
@testable import Games

/// Decks, draws and blackjack totals.
@Suite("Cards")
struct CardsTests {

    private func card(_ rank: Rank, _ suit: Suit = .spades) -> Card {
        Card(rank: rank, suit: suit, id: "\(rank.rawValue)\(suit.rawValue)")
    }

    @Test("An ace beats a king, and the compare is the gap between them")
    func rankOrder() {
        #expect(Cards.order(.ace) == 14)
        #expect(Cards.order(.king) == 13)
        #expect(Cards.order(.jack) == 11)
        #expect(Cards.order(.two) == 2)
        #expect(Cards.compare(.ace, .king) == 1)
        #expect(Cards.compare(.two, .king) == -11)
        #expect(Cards.compare(.nine, .nine) == 0)
    }

    @Test("A card reads as a rank and a pip, and files as a letter")
    func facesAndCodes() {
        #expect(card(.ace, .spades).label == "A\u{2660}")
        #expect(card(.ten, .hearts).label == "10\u{2665}")
        #expect(card(.king, .clubs).label == "K\u{2663}")
        #expect(card(.ace, .spades).code == "as")
        #expect(card(.ten, .hearts).code == "10h")
        #expect(card(.king, .clubs).code == "kc")
    }

    @Test("The stored identity is the letter, not the pip")
    func suitRawValuesDoNotMove() {
        // The pip is presentation. The raw letter is what a saved table encodes and
        // what a seed shuffles, so changing the face must not move it.
        #expect(Suit.spades.rawValue == "s")
        #expect(Suit.hearts.rawValue == "h")
        #expect(Suit.diamonds.rawValue == "d")
        #expect(Suit.clubs.rawValue == "c")
        #expect(card(.ace, .spades).id.hasSuffix("As"))
    }

    @Test("A shoe is whole decks with unique cards, and one seed deals one shoe")
    func shoeIsWholeDecks() {
        var rng = GameRNG(seed: 1)
        let shoe = Cards.makeShoe(decks: 1, using: &rng)
        #expect(shoe.count == 52)
        #expect(Set(shoe.map(\.id)).count == 52)
        #expect(shoe.prefix(5).map(\.id) == ["0-Qh", "0-6c", "0-Jh", "0-Js", "0-5c"])
        #expect(shoe.last?.id == "0-7d")

        var replay = GameRNG(seed: 1)
        #expect(Cards.makeShoe(decks: 1, using: &replay).map(\.id) == shoe.map(\.id))

        var double = GameRNG(seed: 3)
        let two = Cards.makeShoe(decks: 2, using: &double)
        #expect(two.count == 104)
        #expect(Set(two.map(\.id)).count == 104)
    }

    @Test("Asking for no decks builds nothing rather than something empty-ish")
    func noDecks() {
        var rng = GameRNG(seed: 3)
        #expect(Cards.makeShoe(decks: 0, using: &rng).isEmpty)
        var negative = GameRNG(seed: 3)
        #expect(Cards.makeShoe(decks: -1, using: &negative).isEmpty)
    }

    @Test("A draw takes the top card, and an empty shoe answers nothing at all")
    func drawFromShoe() {
        let shoe = [card(.two), card(.three), card(.ace)]
        let drawn = Cards.draw(shoe)
        #expect(drawn?.card.id == card(.ace).id)
        #expect(drawn?.shoe.map(\.id) == [card(.two).id, card(.three).id])
        // Nil rather than a trap: an exhausted shoe is a table to reshuffle, not a
        // crash in the middle of somebody's hand.
        #expect(Cards.draw([]) == nil)
    }

    @Test("An ace is eleven until it would bust the hand")
    func handValues() {
        let natural = Cards.handValue([card(.ace), card(.king)])
        #expect(natural.total == 21)
        #expect(natural.soft)

        let twoAces = Cards.handValue([card(.ace), card(.ace, .hearts), card(.nine)])
        #expect(twoAces.total == 21)
        #expect(twoAces.soft)

        let bust = Cards.handValue([card(.ten), card(.five), card(.seven)])
        #expect(bust.total == 22)
        #expect(!bust.soft)

        let hardened = Cards.handValue([card(.ace), card(.six), card(.king)])
        #expect(hardened.total == 17)
        #expect(!hardened.soft)

        let fourAces = Cards.handValue([
            card(.ace), card(.ace, .hearts), card(.ace, .diamonds), card(.ace, .clubs)
        ])
        #expect(fourAces.total == 14)
        #expect(fourAces.soft)

        let nothing = Cards.handValue([])
        #expect(nothing.total == 0)
        #expect(!nothing.soft)
    }

    @Test("Only two cards make a natural; a drawn 21 is a 21")
    func naturals() {
        #expect(Cards.isBlackjack([card(.ace), card(.king)]))
        #expect(Cards.isBlackjack([card(.ten), card(.ace, .hearts)]))
        #expect(!Cards.isBlackjack([card(.ace), card(.ace, .hearts), card(.nine)]))
        #expect(!Cards.isBlackjack([card(.ace), card(.nine)]))
        #expect(!Cards.isBlackjack([card(.ace)]))
        #expect(!Cards.isBlackjack([]))
    }

    @Test("Court cards are worth ten and the ace opens at eleven")
    func pipValues() {
        #expect(Cards.pipValue(.ace) == 11)
        #expect(Cards.pipValue(.king) == 10)
        #expect(Cards.pipValue(.queen) == 10)
        #expect(Cards.pipValue(.jack) == 10)
        #expect(Cards.pipValue(.ten) == 10)
        #expect(Cards.pipValue(.nine) == 9)
        #expect(Cards.pipValue(.two) == 2)
    }
}
