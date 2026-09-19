import Foundation

/// Which way the player called the card about to be turned over.
public enum HighLowCall: String, Sendable, Codable, Equatable {
    /// The next card is higher.
    case higher
    /// The next card is lower.
    case lower
}

/// Where a table is in its cycle: nothing dealt, a card up, or a call settled.
public enum HighLowPhase: String, Sendable, Codable, Equatable {
    /// No call is open.
    case idle
    /// A card is up and a call can be made.
    case open
    /// The call has been settled.
    case resolved
}

/// How a settled call landed.
///
/// `push` is equal ranks: nothing paid, nothing lost, streak untouched.
public enum HighLowResult: String, Sendable, Codable, Equatable {
    /// The call was right.
    case win
    /// The call was wrong.
    case lose
    /// The cards tied.
    case push
}

/// A higher-or-lower table: the shoe it deals from, the open call, and the last
/// result.
///
/// One player. The table belongs to whoever dealt it and nobody else can act on
/// it (`PLAY-2`). The original arrived with a channel-wide variant where the whole
/// room voted on one hand, and it was removed rather than kept behind an option: a
/// table the room can play is not your table. What the room gets is the result
/// (`PLAY-7`).
///
/// The shoe and the seed live on the table rather than in the context because a
/// table is stored whole between interactions: reloaded from storage it deals on
/// from exactly where it left off, and the seed on the card proves it was not
/// re-rolled.
public struct HighLowState: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Idle, open, or resolved.
    public var phase: HighLowPhase

    /// The up-card being called against. Nil until the first draw.
    public var shown: Card?

    /// The card turned over at settle. Nil until then, and cleared by the next
    /// draw.
    public var next: Card?

    /// Cards left to deal. The top of the shoe is the last element.
    public var shoe: [Card]

    /// Consecutive wins.
    ///
    /// Sizes the payout: a win increments, a push holds, a loss zeroes.
    public var streak: Int

    /// The call made on the open card. Nil until one is made.
    public var called: HighLowCall?

    /// How the last settle landed. Nil until a settle.
    public var result: HighLowResult?

    /// The call the settle judged. Nil when a settle found no call at all.
    ///
    /// Equal to ``called`` once a hand has settled, and nothing in this module
    /// reads it: ``HighLow/card(_:pictureUrl:)`` draws a resolved table from
    /// ``result`` and ``payout`` alone, and the push branch of
    /// ``HighLow/settle(_:context:)`` writes it rather than reading it. Carried
    /// forward from the engine this was ported from, where it was write-only too,
    /// and kept for whatever renders a feed of finished hands: telling "called and
    /// lost" from "settled with nothing called" after the fact needs it, and
    /// nothing else can recover it once the table has moved on.
    public var judgedCall: HighLowCall?

    /// Chips the last settle paid. Zero on anything but a win.
    public var payout: Int

    /// Seed drawn for this deal, printed on the card so a player can see the deal
    /// was not re-rolled under them.
    public var seed: UInt32

    // MARK: - Initializers

    /// - Parameters:
    ///   - phase: Idle, open, or resolved.
    ///   - shown: The up-card.
    ///   - next: The card turned over at settle.
    ///   - shoe: Cards left, top card last.
    ///   - streak: Consecutive wins.
    ///   - called: The call made on the open card.
    ///   - result: How the last settle landed.
    ///   - judgedCall: The call the settle judged.
    ///   - payout: Chips the last settle paid.
    ///   - seed: Seed for this deal.
    public init(
        phase: HighLowPhase,
        shown: Card? = nil,
        next: Card? = nil,
        shoe: [Card],
        streak: Int = 0,
        called: HighLowCall? = nil,
        result: HighLowResult? = nil,
        judgedCall: HighLowCall? = nil,
        payout: Int = 0,
        seed: UInt32 = 0
    ) {
        self.phase = phase
        self.shown = shown
        self.next = next
        self.shoe = shoe
        self.streak = streak
        self.called = called
        self.result = result
        self.judgedCall = judgedCall
        self.payout = payout
        self.seed = seed
    }
}

/// Higher or lower against the deck, played in chips.
///
/// A pure reducer. Every step takes the table plus a ``GameContext`` and hands back
/// the next table and the only chip movement it is allowed to ask for, so one set
/// of functions drives a button, a test, and a replay from a seed. Nothing here
/// reads a clock, a global generator or a balance.
///
/// It costs nothing to play and pays on a win, which is what makes it the way back
/// for somebody who has run their chips down (`PLAY-8`).
public enum HighLow: Sendable {

    // MARK: - Properties

    /// Deal a fresh shoe once this many cards or fewer are left.
    ///
    /// A call needs two cards and the shoe is single-deck, so the cut is generous
    /// on purpose: the table never has to think about running dry mid-settle.
    private static let refillThreshold: Int = 12

    /// Card title, identical in every phase so an edited message stays the same
    /// card.
    private static let title: String = "Higher or Lower"

    private static let idleColor: Int = 0x2a2723
    private static let openColor: Int = 0x3a342c
    private static let winColor: Int = 0x6e8b6e
    private static let loseColor: Int = 0xb54a4a
    private static let pushColor: Int = 0x6a6560

    private static let openButtonId: String = "ng_highlow_open"
    private static let higherButtonId: String = "ng_highlow_higher"
    private static let lowerButtonId: String = "ng_highlow_lower"

    // MARK: - Public Methods

    /// A fresh table: idle, no streak, one shuffled deck in the shoe.
    ///
    /// The shoe is dealt here rather than at the first draw so the table can be
    /// stored and replayed from the moment it was created.
    public static func initial(context: inout GameContext) -> HighLowState {
        HighLowState(
            phase: .idle,
            shown: nil,
            next: nil,
            shoe: refilled([], context: &context),
            streak: 0,
            result: nil,
            judgedCall: nil,
            payout: 0,
            seed: 0
        )
    }

    /// Turn the up-card over and take a call. Clears the last result; keeps the
    /// streak.
    ///
    /// Legal from any phase, because a card's Draw and Again buttons are the same
    /// action.
    public static func open(
        _ state: HighLowState,
        context: inout GameContext
    ) -> ReduceResult<HighLowState> {
        guard let dealt = deal(state.shoe, context: &context) else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        var table = state
        table.phase = .open
        table.shown = dealt.card
        table.next = nil
        table.shoe = dealt.shoe
        table.called = nil
        table.result = nil
        table.judgedCall = nil
        table.payout = 0
        table.seed = context.rng.seed32()
        return ReduceResult(state: table, chipDelta: 0)
    }

    /// Record the call and settle it, because there is nobody else to wait for.
    public static func call(
        _ state: HighLowState,
        side: HighLowCall,
        context: inout GameContext
    ) -> ReduceResult<HighLowState> {
        guard state.phase == .open, state.shown != nil else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        var table = state
        table.called = side
        return settle(table, context: &context)
    }

    /// Draw against the up-card and pay the streak if the call was right.
    ///
    /// The streak is moved before the payout is sized, so the win that reaches a
    /// streak is the win that is paid at it.
    public static func settle(
        _ state: HighLowState,
        context: inout GameContext
    ) -> ReduceResult<HighLowState> {
        guard state.phase == .open, let shown = state.shown else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        guard let dealt = deal(state.shoe, context: &context) else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        var table = state
        table.phase = .resolved
        table.next = dealt.card
        table.shoe = dealt.shoe
        guard let side = state.called else {
            table.result = .push
            table.judgedCall = nil
            table.payout = 0
            return ReduceResult(state: table, chipDelta: 0)
        }
        let result = resolve(shown: shown.rank, drawn: dealt.card.rank, side: side)
        let streak: Int
        switch result {
        case .win:
            streak = state.streak + 1
        case .push:
            streak = state.streak
        case .lose:
            streak = 0
        }
        let payout = result == .win ? Chips.streakPayout(streakAfterWin: streak) : 0
        table.result = result
        table.judgedCall = side
        table.payout = payout
        table.streak = streak
        return ReduceResult(state: table, chipDelta: payout)
    }

    /// Actions the table will accept now. Matches the buttons ``card(_:pictureUrl:)``
    /// shows.
    public static func legalActions(_ state: HighLowState) -> [String] {
        state.phase == .open ? ["higher", "lower"] : ["open"]
    }

    /// The table as a card: pure data, mapped to a message by whatever drives it.
    ///
    /// - Parameters:
    ///   - state: The table as it stands.
    ///   - pictureUrl: Picture for the card's corner, or nil.
    /// - Returns: The card.
    public static func card(_ state: HighLowState, pictureUrl: String? = nil) -> GameMessage {
        if state.phase == .idle {
            return GameMessage(
                title: title,
                description: "A card comes off the top. Higher or lower?",
                color: idleColor,
                buttons: [GameButton(id: openButtonId, label: "Draw", style: .primary)],
                footer: "Streak \(state.streak)",
                thumbnailUrl: pictureUrl
            )
        }
        if state.phase == .open, let shown = state.shown {
            return GameMessage(
                title: title,
                description: "Showing **\(shown.label)**. Is the next card higher or lower?",
                color: openColor,
                buttons: [
                    GameButton(id: higherButtonId, label: "Higher", style: .success),
                    GameButton(id: lowerButtonId, label: "Lower", style: .danger)
                ],
                footer: "Streak \(state.streak) \u{00b7} seed \(String(state.seed, radix: 16))",
                thumbnailUrl: pictureUrl
            )
        }
        let drawnFace = state.next?.label ?? "?"
        let shownFace = state.shown?.label ?? "?"
        let tone: Int
        let verdict: String
        if state.result == .win {
            tone = winColor
            verdict = "Right call. +\(state.payout) chips."
        } else if state.result == .lose {
            tone = loseColor
            verdict = "Wrong call."
        } else {
            tone = pushColor
            verdict = "Push."
        }
        return GameMessage(
            title: title,
            description: "Was **\(shownFace)**. Drew **\(drawnFace)**. \(verdict)",
            color: tone,
            buttons: [GameButton(id: openButtonId, label: "Again", style: .primary)],
            footer: "Streak \(state.streak)",
            thumbnailUrl: pictureUrl
        )
    }

    // MARK: - Private Methods

    /// The shoe to deal from: what is left while it is deep enough, else a fresh
    /// deck.
    private static func refilled(_ leftover: [Card], context: inout GameContext) -> [Card] {
        if leftover.count > refillThreshold {
            return leftover
        }
        return Cards.makeShoe(decks: 1, using: &context.rng)
    }

    /// Top card and the rest, refilling first. Nil only if a refilled shoe came
    /// back empty.
    private static func deal(
        _ shoe: [Card],
        context: inout GameContext
    ) -> (card: Card, shoe: [Card])? {
        Cards.draw(refilled(shoe, context: &context))
    }

    /// How `side` fares when `drawn` lands against `shown`. Equal ranks push.
    private static func resolve(shown: Rank, drawn: Rank, side: HighLowCall) -> HighLowResult {
        let comparison = Cards.compare(drawn, shown)
        if comparison == 0 {
            return .push
        }
        let wentHigher = comparison > 0
        if side == .higher {
            return wentHigher ? .win : .lose
        }
        return wentHigher ? .lose : .win
    }
}
