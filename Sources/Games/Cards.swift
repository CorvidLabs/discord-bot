import Foundation

/// A French rank. Raw values are the face text a card shows.
///
/// Declaration order is the JavaScript original's `RANKS` order and `makeShoe`
/// walks `allCases`, so changing it would change every shuffled shoe for a given
/// seed and every stored table would deal differently on reload.
public enum Rank: String, Sendable, Codable, CaseIterable, Equatable {
    /// Eleven in a blackjack hand until it would bust, then one.
    case ace = "A"
    /// Rank two.
    case two = "2"
    /// Rank three.
    case three = "3"
    /// Rank four.
    case four = "4"
    /// Rank five.
    case five = "5"
    /// Rank six.
    case six = "6"
    /// Rank seven.
    case seven = "7"
    /// Rank eight.
    case eight = "8"
    /// Rank nine.
    case nine = "9"
    /// Rank ten.
    case ten = "10"
    /// Rank jack. Worth ten.
    case jack = "J"
    /// Rank queen. Worth ten.
    case queen = "Q"
    /// Rank king. Worth ten.
    case king = "K"
}

/// A French suit. Raw values are the single lowercase letters used in card ids.
///
/// Declaration order is fixed for the same reason ``Rank``'s is: it fixes the
/// pre-shuffle deck a seed is applied to.
public enum Suit: String, Sendable, Codable, CaseIterable, Equatable {
    /// Suit spades.
    case spades = "s"
    /// Suit hearts.
    case hearts = "h"
    /// Suit diamonds.
    case diamonds = "d"
    /// Suit clubs.
    case clubs = "c"

    /// The pip a card face is drawn with.
    ///
    /// Kept apart from `rawValue`: the raw letter is the stored and seeded
    /// identity, so it must not move, while this is presentation only and can
    /// change without reshuffling every saved table.
    public var pip: String {
        switch self {
        case .spades: return "\u{2660}"
        case .hearts: return "\u{2665}"
        case .diamonds: return "\u{2666}"
        case .clubs: return "\u{2663}"
        }
    }
}

/// One card in a shoe.
///
/// `id` carries the deck index as well as rank and suit, so a multi-deck shoe
/// still has a unique handle for every physical card.
public struct Card: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Face rank.
    public let rank: Rank

    /// Suit.
    public let suit: Suit

    /// Unique within a shoe: `"{deck}-{rank}{suit}"`.
    public let id: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - rank: Face rank.
    ///   - suit: Suit.
    ///   - id: Unique handle within the shoe.
    public init(rank: Rank, suit: Suit, id: String) {
        self.rank = rank
        self.suit = suit
        self.id = id
    }

    // MARK: - Public Methods

    /// Short face for a card, for example `A` followed by the spade pip.
    ///
    /// Presentation only. The stored identity is `rank`, `suit` and `id`, so a
    /// table saved by an older build still reads back and re-renders here.
    public var label: String {
        rank.rawValue + suit.pip
    }

    /// The card as a lowercase deck code, for example `ks` or `10h`.
    ///
    /// A string rather than a picture, because drawing the picture is somebody
    /// else's job. A renderer is a later layer; this layer only has to say which
    /// card is on the table, and it must be able to say so without one.
    public var code: String {
        rank.rawValue.lowercased() + suit.rawValue
    }
}

/// Deck building, drawing, and blackjack totals. Pure; randomness arrives as a
/// ``GameRNG``.
public enum Cards: Sendable {

    // MARK: - Properties

    /// Cards in one deck. A shoe is this times the deck count.
    public static let deckSize: Int = 52

    /// The code a face-down card is drawn with.
    public static let faceDownCode: String = "back"

    // MARK: - Public Methods

    /// Rank strength for a high-card compare: ace high at 14 down to two.
    public static func order(_ rank: Rank) -> Int {
        switch rank {
        case .ace: return 14
        case .king: return 13
        case .queen: return 12
        case .jack: return 11
        case .ten: return 10
        case .nine: return 9
        case .eight: return 8
        case .seven: return 7
        case .six: return 6
        case .five: return 5
        case .four: return 4
        case .three: return 3
        case .two: return 2
        }
    }

    /// Positive when `left` beats `right`, negative when it loses, zero on a tie.
    public static func compare(_ left: Rank, _ right: Rank) -> Int {
        order(left) - order(right)
    }

    /// A shuffled shoe of `decks * 52` cards.
    ///
    /// Built deck-major, then suit, then rank before the shuffle: the shuffle is
    /// applied to that exact order, so the starting order is part of the contract.
    ///
    /// - Parameters:
    ///   - decks: How many decks go into the shoe. Zero or fewer builds nothing.
    ///   - rng: The stream the shuffle spends draws from.
    /// - Returns: The shuffled shoe, top card last.
    public static func makeShoe(decks: Int, using rng: inout GameRNG) -> [Card] {
        guard decks > 0 else { return [] }
        var raw: [Card] = []
        raw.reserveCapacity(decks * deckSize)
        for deck in 0..<decks {
            for suit in Suit.allCases {
                for rank in Rank.allCases {
                    raw.append(
                        Card(rank: rank, suit: suit, id: "\(deck)-\(rank.rawValue)\(suit.rawValue)")
                    )
                }
            }
        }
        return GameShuffle.fisherYates(raw, using: &rng)
    }

    /// The next card off the top of the shoe plus what is left, or nil when it is
    /// empty.
    ///
    /// The JavaScript original throws on an empty shoe. A Swift table would rather
    /// reshuffle than trap, so an exhausted shoe is a value the caller has to
    /// handle instead of a crash in the middle of somebody's hand.
    public static func draw(_ shoe: [Card]) -> (card: Card, shoe: [Card])? {
        guard let card = shoe.last else { return nil }
        return (card, Array(shoe.dropLast()))
    }

    /// Blackjack pip value with the ace high at 11. ``handValue(_:)`` demotes it
    /// when it busts.
    public static func pipValue(_ rank: Rank) -> Int {
        switch rank {
        case .ace: return 11
        case .king, .queen, .jack, .ten: return 10
        case .nine: return 9
        case .eight: return 8
        case .seven: return 7
        case .six: return 6
        case .five: return 5
        case .four: return 4
        case .three: return 3
        case .two: return 2
        }
    }

    /// Best total for a hand, and whether an ace is still worth 11 in it.
    ///
    /// Counts every ace as 11 and then knocks 10 off one at a time while the hand
    /// is over 21, which lands on the highest total that is not a bust. `soft` is
    /// true only while a surviving ace could still be demoted by a later hit.
    public static func handValue(_ cards: [Card]) -> (total: Int, soft: Bool) {
        var total = 0
        var aces = 0
        for card in cards {
            if card.rank == .ace {
                aces += 1
                total += 11
            } else {
                total += pipValue(card.rank)
            }
        }
        while total > 21 && aces > 0 {
            total -= 10
            aces -= 1
        }
        return (total, aces > 0 && total <= 21)
    }

    /// A natural: exactly two cards totalling 21. A drawn-to 21 is not one.
    public static func isBlackjack(_ cards: [Card]) -> Bool {
        cards.count == 2 && handValue(cards).total == 21
    }
}
