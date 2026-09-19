import Foundation

/// Where a blackjack hand is in its life.
///
/// The phase is the only gate on what a button may do: a stale click on an old
/// card lands in the wrong phase and is refused rather than paying twice. A chat
/// client will happily deliver a click from a card that has since moved on, so a
/// disabled button is never the whole guard.
public enum BlackjackPhase: String, Sendable, Codable, Equatable {
    /// Waiting for a bet.
    case betting
    /// The bet is down and the player is acting.
    case playing
    /// The hand is over and its chip delta has been taken.
    case settled
}

/// How a settled hand finished.
///
/// `bust` is kept apart from `lose` because the two pay the same but read
/// differently on a card, and `blackjack` apart from `win` because only a natural
/// pays 3:2.
public enum BlackjackOutcome: String, Sendable, Codable, Equatable {
    /// Beat the dealer on totals, or the dealer busted.
    case win
    /// Lost on totals, or to the dealer's natural.
    case lose
    /// Equal totals; the stake comes back.
    case push
    /// Natural twenty-one on the first two cards.
    case blackjack
    /// Over twenty-one.
    case bust
}

/// One blackjack table: the shoe, both hands, and what the last action decided.
///
/// The shoe travels inside the state rather than beside it, so a hand dealt from a
/// seed replays card for card, and ``Blackjack/next(_:context:)`` can keep the
/// cards that are left.
///
/// ``payout`` is the whole return of the hand, never the net: the stake was already
/// taken on the deal, and netting it twice is the bug this shape exists to stop.
public struct BlackjackState: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Betting, playing, or settled.
    public var phase: BlackjackPhase

    /// Chips staked on this hand. Doubling rewrites it to the doubled stake.
    public var bet: Int

    /// Cards left, drawn from the end. Refilled when it runs low.
    public var shoe: [Card]

    /// The player's hand.
    public var player: [Card]

    /// The dealer's hand.
    public var dealer: [Card]

    /// Hide the dealer's second card while the hand is live.
    public var hideHole: Bool

    /// Set once the hand settles. Nil while it is still being played.
    public var outcome: BlackjackOutcome?

    /// Whole chip return of the hand, stake included. Zero on a loss.
    public var payout: Int

    /// The hand took its one extra card and stood.
    public var doubled: Bool

    /// The line a card shows for the last action.
    public var message: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - phase: Betting, playing, or settled.
    ///   - bet: Chips staked.
    ///   - shoe: Cards left, top card last.
    ///   - player: The player's hand.
    ///   - dealer: The dealer's hand.
    ///   - hideHole: Hide the dealer's second card.
    ///   - outcome: How the hand finished.
    ///   - payout: Whole chip return, stake included.
    ///   - doubled: The hand doubled.
    ///   - message: The line for the last action.
    public init(
        phase: BlackjackPhase = .betting,
        bet: Int = 0,
        shoe: [Card] = [],
        player: [Card] = [],
        dealer: [Card] = [],
        hideHole: Bool = true,
        outcome: BlackjackOutcome? = nil,
        payout: Int = 0,
        doubled: Bool = false,
        message: String = ""
    ) {
        self.phase = phase
        self.bet = bet
        self.shoe = shoe
        self.player = player
        self.dealer = dealer
        self.hideHole = hideHole
        self.outcome = outcome
        self.payout = payout
        self.doubled = doubled
        self.message = message
    }
}

/// Blackjack against the dealer, played in chips.
///
/// Every entry point is a pure reducer: it takes a state, takes the context `inout`
/// so the shoe advances a seeded stream, and answers with the next state plus the
/// only chip movement it is allowed to ask for. Nothing here reads a clock, a
/// global generator or a balance.
///
/// The accounting is the part worth stating twice: ``deal(_:amount:context:)``
/// returns `-bet`, ``stand(_:context:)`` returns the payout,
/// ``double(_:context:)`` returns `-extra + payout`, and ``hit(_:context:)``
/// returns nothing. A caller that nets a payout against a stake again pays the hand
/// twice.
public enum Blackjack: Sendable {

    // MARK: - Properties

    /// The one-tap stakes on the betting card, smallest first.
    ///
    /// The last one is the primary button. A stake the player cannot cover is shown
    /// disabled rather than hidden, so the card still says what the game costs
    /// while making plain which of them they can actually take.
    ///
    /// Public because a rules page has to quote the stakes the game actually deals
    /// for, rather than a number somebody retyped (`LEARN-6`).
    public static let stakes: [Int] = [10, 25, 50]

    /// What to tell somebody whose chips will not cover the smallest hand.
    ///
    /// Named as games rather than as commands, because this module knows nothing
    /// about any chat client. Running out is a pause, not the end, and the game is
    /// what has to say so (`PLAY-8`).
    public static let brokeRoute: String =
        "Higher or Lower costs nothing to play and pays on a win, foraging is free, "
        + "and the daily claim tops your chips back up."

    /// Below this many cards the shoe is replaced before a draw.
    ///
    /// Kept as a named constant, but it is not free to change: replacing the shoe
    /// spends draws, so a table replayed from a seed only deals the same cards if
    /// it refills at the same points.
    private static let refillBeforeDraw: Int = 12

    /// Below this many cards the shoe is replaced part way through a multi-card
    /// draw.
    private static let refillMidDraw: Int = 4

    /// The deal replaces a shoe thinner than this before it starts.
    private static let refillBeforeDeal: Int = 16

    // MARK: - Public Methods

    /// A fresh table: a shuffled single-deck shoe, no stake, nothing dealt.
    public static func initial(context: inout GameContext) -> BlackjackState {
        BlackjackState(
            phase: .betting,
            bet: 0,
            shoe: Cards.makeShoe(decks: 1, using: &context.rng),
            player: [],
            dealer: [],
            hideHole: true,
            outcome: nil,
            payout: 0,
            doubled: false,
            message: "Put down a bet in chips. The dealer stands on 17."
        )
    }

    /// Take the stake and deal two cards each, settling at once on a natural.
    ///
    /// A stake under ``Chips/minimumBet`` or over what the player holds is refused:
    /// the table comes back untouched with only the message replaced and no chips
    /// and no draws moved, so a fat-fingered bet costs nothing. A natural on either
    /// side skips the playing phase entirely, which is why this can return a
    /// positive delta even though it is the action that takes the stake.
    ///
    /// - Parameters:
    ///   - state: The table as it stands.
    ///   - amount: Chips to stake.
    ///   - context: Clock, player and the seeded stream.
    /// - Returns: The dealt table and the stake taken, plus any immediate return.
    public static func deal(
        _ state: BlackjackState,
        amount: Int,
        context: inout GameContext
    ) -> ReduceResult<BlackjackState> {
        guard state.phase == .betting else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        let bet = amount
        guard bet >= Chips.minimumBet else {
            var refused = state
            refused.message = "Minimum bet is \(Chips.minimumBet). You have \(context.player.chips)."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        guard bet <= context.player.chips else {
            var refused = state
            refused.message = "Not enough chips: that bet is \(bet) and you have \(context.player.chips)."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        var shoe: [Card] = state.shoe
        if shoe.count < refillBeforeDeal {
            shoe = Cards.makeShoe(decks: 1, using: &context.rng)
        }
        let firstPlayer = take(shoe, count: 1, context: &context)
        let firstDealer = take(firstPlayer.shoe, count: 1, context: &context)
        let secondPlayer = take(firstDealer.shoe, count: 1, context: &context)
        let secondDealer = take(secondPlayer.shoe, count: 1, context: &context)
        let player: [Card] = firstPlayer.cards + secondPlayer.cards
        let dealer: [Card] = firstDealer.cards + secondDealer.cards
        shoe = secondDealer.shoe

        if Cards.isBlackjack(player) || Cards.isBlackjack(dealer) {
            let settled = settleWith(player: player, dealer: dealer, bet: bet)
            let dealt = BlackjackState(
                phase: .settled,
                bet: bet,
                shoe: shoe,
                player: player,
                dealer: dealer,
                hideHole: false,
                outcome: settled.outcome,
                payout: settled.payout,
                doubled: false,
                message: settled.message
            )
            return ReduceResult(state: dealt, chipDelta: -bet + settled.payout)
        }
        let dealt = BlackjackState(
            phase: .playing,
            bet: bet,
            shoe: shoe,
            player: player,
            dealer: dealer,
            hideHole: true,
            outcome: nil,
            payout: 0,
            doubled: false,
            message: "Hit, stand, or double."
        )
        return ReduceResult(state: dealt, chipDelta: -bet)
    }

    /// Draw one card. Busting settles the hand; the stake is already gone either
    /// way.
    ///
    /// Always `chipDelta: 0`. A bust pays nothing rather than debiting again,
    /// because ``deal(_:amount:context:)`` took the stake when it dealt the hand.
    public static func hit(
        _ state: BlackjackState,
        context: inout GameContext
    ) -> ReduceResult<BlackjackState> {
        guard state.phase == .playing else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        let drawn = take(state.shoe, count: 1, context: &context)
        var updated = state
        updated.player = state.player + drawn.cards
        updated.shoe = drawn.shoe
        let total = Cards.handValue(updated.player).total
        let face = drawn.cards.first.map(\.label) ?? "?"
        if total > 21 {
            updated.phase = .settled
            updated.hideHole = false
            updated.outcome = .bust
            updated.payout = 0
            updated.message = "Drew \(face). \(total), bust. The dealer collects."
            return ReduceResult(state: updated, chipDelta: 0)
        }
        // Name the card, not just the new total: the picture changes either way,
        // and without this nothing on the card says what the press actually did.
        let soft = Cards.handValue(updated.player).soft
        updated.message = "Drew \(face). \(soft ? "Soft " : "")\(total)."
        return ReduceResult(state: updated, chipDelta: 0)
    }

    /// Turn the hole card over, play the dealer out, and settle.
    ///
    /// The delta is the payout on its own: the stake left on the deal, so an
    /// even-money win returns `bet * 2` and lands the player one stake up.
    public static func stand(
        _ state: BlackjackState,
        context: inout GameContext
    ) -> ReduceResult<BlackjackState> {
        guard state.phase == .playing else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        let played = dealerPlay(dealer: state.dealer, shoe: state.shoe, context: &context)
        let settled = settleWith(player: state.player, dealer: played.dealer, bet: state.bet)
        var updated = state
        updated.phase = .settled
        updated.dealer = played.dealer
        updated.shoe = played.shoe
        updated.hideHole = false
        updated.outcome = settled.outcome
        updated.payout = settled.payout
        updated.message = "\(drawLine(played.drew)) \(settled.message)"
        return ReduceResult(state: updated, chipDelta: settled.payout)
    }

    /// Stake the bet again, take exactly one card, and stand.
    ///
    /// Only legal on the opening two cards of a hand that has not doubled, and only
    /// when the player still covers a second stake. Somebody who cannot pay gets
    /// the table back with a message and no cards drawn. The delta carries the
    /// extra stake as well as the return, because the extra is taken here.
    public static func double(
        _ state: BlackjackState,
        context: inout GameContext
    ) -> ReduceResult<BlackjackState> {
        // Say why. Returning the state untouched re-renders an identical card, so a
        // refused double looked exactly like a button that did nothing at all.
        guard state.phase == .playing else {
            var refused = state
            refused.message = state.phase == .betting
                ? "Put a bet down first."
                : "That hand is over. Deal the next one."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        guard !state.doubled else {
            var refused = state
            refused.message = "Already doubled. One card is all a double gets."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        guard state.player.count == 2 else {
            var refused = state
            refused.message = "Doubling is only on your first two cards."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        guard context.player.chips >= state.bet else {
            var refused = state
            refused.message = "Not enough chips to double."
            return ReduceResult(state: refused, chipDelta: 0)
        }
        let extra = state.bet
        let drawn = take(state.shoe, count: 1, context: &context)
        var updated = state
        updated.phase = .settled
        // Saturating for the same reason the payout legs are: the second stake is
        // whatever the first was, and a pile at the ceiling must not trap here.
        updated.bet = saturatingAdd(state.bet, extra)
        updated.player = state.player + drawn.cards
        updated.shoe = drawn.shoe
        updated.hideHole = false
        updated.doubled = true
        if Cards.handValue(updated.player).total > 21 {
            updated.outcome = .bust
            updated.payout = 0
            updated.message = "Double bust. The dealer collects."
            return ReduceResult(state: updated, chipDelta: -extra)
        }
        let played = dealerPlay(dealer: state.dealer, shoe: drawn.shoe, context: &context)
        let settled = settleWith(player: updated.player, dealer: played.dealer, bet: updated.bet)
        updated.dealer = played.dealer
        updated.shoe = played.shoe
        updated.outcome = settled.outcome
        updated.payout = settled.payout
        let doubledFace = drawn.cards.first.map(\.label) ?? "?"
        updated.message = "Doubled, drew \(doubledFace). \(drawLine(played.drew)) \(settled.message)"
        return ReduceResult(state: updated, chipDelta: -extra + settled.payout)
    }

    /// Clear the table for another hand, keeping the cards that are left.
    ///
    /// The shoe survives on purpose: a hand should not be dealt from a brand new
    /// deck every time, and carrying it over is what makes the refill thresholds
    /// mean anything.
    public static func next(
        _ state: BlackjackState,
        context: inout GameContext
    ) -> ReduceResult<BlackjackState> {
        guard state.phase == .settled else {
            return ReduceResult(state: state, chipDelta: 0)
        }
        var fresh = initial(context: &context)
        fresh.shoe = state.shoe
        return ReduceResult(state: fresh, chipDelta: 0)
    }

    /// Action names the table will accept right now, for a card or a handler to
    /// gate on.
    ///
    /// Double is offered only on an untouched two-card hand; whether the player can
    /// pay for it is checked in ``double(_:context:)``, which is the only place
    /// that can see their chips.
    public static func legalActions(_ state: BlackjackState) -> [String] {
        switch state.phase {
        case .betting:
            return ["bet"]
        case .playing:
            var actions: [String] = ["hit", "stand"]
            if state.player.count == 2 && !state.doubled {
                actions.append("double")
            }
            return actions
        case .settled:
            return ["next"]
        }
    }

    /// The table as a card: one message and the buttons that are live in this
    /// phase.
    ///
    /// Pure data, no client types, so a card can be asserted in a test without a
    /// connection. The context is read-only here: rendering never draws a card.
    public static func card(_ state: BlackjackState, context: GameContext) -> GameMessage {
        if state.phase == .betting {
            return bettingCard(state, context: context)
        }
        let playerTotal = Cards.handValue(state.player).total
        var dealerTotal = Cards.handValue(state.dealer).total
        if state.hideHole {
            dealerTotal = Cards.handValue(Array(state.dealer.prefix(1))).total
        }
        if state.phase == .playing {
            // The line the last action wrote, then the stake. Hardcoding the stake
            // here threw `message` away for the whole of a hand, so every refusal
            // and every "Drew 4, 16." was written and never shown, which is why a
            // Double that could not be taken looked like a dead button.
            let line = state.message.isEmpty
                ? "Bet: \(state.bet) chips."
                : "\(state.message)\n_Bet: \(state.bet) chips._"
            return GameMessage(
                title: title,
                description: line,
                fields: [
                    GameField(
                        name: "Dealer  (\(dealerTotal)+)",
                        value: cardLine(state.dealer, hideSecond: true),
                        inline: true
                    ),
                    GameField(
                        name: "You  (\(playerTotal))",
                        value: cardLine(state.player, hideSecond: false),
                        inline: true
                    )
                ],
                color: playingColor,
                buttons: [
                    GameButton(id: hitButtonId, label: "Hit", style: .primary),
                    GameButton(id: standButtonId, label: "Stand", style: .secondary),
                    GameButton(
                        id: doubleButtonId,
                        label: "Double",
                        style: .success,
                        disabled: state.player.count != 2
                    )
                ],
                thumbnailUrl: context.player.holdings.pictureUrl,
                hand: [
                    faceCodes(state.dealer, hideSecond: true),
                    faceCodes(state.player, hideSecond: false)
                ]
            )
        }
        var tone: Int = pushColor
        if state.outcome == .win || state.outcome == .blackjack {
            tone = winColor
        } else if state.outcome == .lose || state.outcome == .bust {
            tone = loseColor
        }
        return GameMessage(
            title: title,
            description: state.message,
            fields: [
                GameField(
                    name: "Dealer  (\(dealerTotal))",
                    value: cardLine(state.dealer, hideSecond: false),
                    inline: true
                ),
                GameField(
                    name: "You  (\(playerTotal))",
                    value: cardLine(state.player, hideSecond: false),
                    inline: true
                )
            ],
            color: tone,
            buttons: [GameButton(id: nextButtonId, label: "Next hand", style: .primary)],
            footer: "Bet \(state.bet) \u{00b7} chips \(context.player.chips)",
            thumbnailUrl: context.player.holdings.pictureUrl,
            hand: [
                faceCodes(state.dealer, hideSecond: false),
                faceCodes(state.player, hideSecond: false)
            ]
        )
    }

    // MARK: - Internal Methods

    /// Who won and what the hand returns.
    ///
    /// Order is the rule, not a tidy-up: the player busting beats everything, then
    /// two naturals push, then the player's natural pays 3:2, then the dealer's
    /// natural collects, then a dealer bust pays even, and only then do totals get
    /// compared. Judging a dealer bust before a natural would pay hands that lost.
    ///
    /// `bet` is always positive here, so the 3:2 leg floors the way integer
    /// division does, which is what the original played by.
    ///
    /// Every leg saturates rather than traps. Nothing caps a stake: a host can
    /// configure a daily bonus that leaves a player on ``Chips/applying(_:to:)``'s
    /// ceiling, and ``deal(_:amount:context:)`` accepts any bet that pile covers,
    /// so the function that decides the return is exactly where an absurd stake
    /// must not take the process down with it.
    ///
    /// Internal rather than private so the payout table can be asserted directly:
    /// two naturals pushing, and a dealer natural beating a drawn 21, are the cases
    /// a seed sweep cannot be relied on to produce, and both are real payout bugs
    /// if they go wrong.
    internal static func settleWith(
        player: [Card],
        dealer: [Card],
        bet: Int
    ) -> (outcome: BlackjackOutcome, payout: Int, message: String) {
        let playerTotal = Cards.handValue(player).total
        let dealerTotal = Cards.handValue(dealer).total
        let playerNatural = Cards.isBlackjack(player)
        let dealerNatural = Cards.isBlackjack(dealer)
        if playerTotal > 21 {
            return (.bust, 0, "Bust. The dealer collects.")
        }
        if playerNatural && dealerNatural {
            return (.push, bet, "Two 21s. Push.")
        }
        if playerNatural {
            return (.blackjack, saturatingAdd(bet, saturatingMultiply(bet, 3) / 2), "21 on two. Pays 3:2.")
        }
        if dealerNatural {
            return (.lose, 0, "Dealer 21. You lose the bet.")
        }
        if dealerTotal > 21 {
            return (.win, saturatingMultiply(bet, 2), "Dealer busts. Pays even money.")
        }
        if playerTotal > dealerTotal {
            return (.win, saturatingMultiply(bet, 2), "\(playerTotal) over \(dealerTotal). Even money.")
        }
        if playerTotal < dealerTotal {
            return (.lose, 0, "\(playerTotal) under the dealer's \(dealerTotal).")
        }
        return (.push, bet, "Both \(playerTotal). Push.")
    }

    // MARK: - Private Methods

    private static let title: String = "Blackjack"
    private static let bettingColor: Int = 0x1c1a18
    private static let playingColor: Int = 0x2a2723
    private static let winColor: Int = 0x6e8b6e
    private static let loseColor: Int = 0xb54a4a
    private static let pushColor: Int = 0x6a6560

    private static let hitButtonId: String = "ng_blackjack_hit"
    private static let standButtonId: String = "ng_blackjack_stand"
    private static let doubleButtonId: String = "ng_blackjack_double"
    private static let nextButtonId: String = "ng_blackjack_next"
    private static let betButtonPrefix: String = "ng_blackjack_bet_"

    /// The betting card, including the way out for somebody who cannot cover the
    /// smallest hand.
    private static func bettingCard(
        _ state: BlackjackState,
        context: GameContext
    ) -> GameMessage {
        let chips = context.player.chips
        let rules = "Blackjack against the dealer, played in chips. "
            + "The dealer stands on 17. A natural pays 3:2."
        // The betting card threw `message` away exactly the way the playing card
        // did, so every refusal `deal` wrote here, a stake under the minimum or a
        // stake the player could not cover, was never shown, and a Deal button that
        // could not work looked like a dead button.
        var line = state.message.isEmpty ? rules : "\(state.message)\n_\(rules)_"
        var footer: String?
        if chips < Chips.minimumBet {
            // Too few chips for the smallest hand needs the way back, not the rules
            // of a game they cannot start (`PLAY-8`).
            line = "You have **\(chips)** chips, and the smallest bet is **\(Chips.minimumBet)**."
            footer = brokeRoute
        }
        return GameMessage(
            title: title,
            description: line,
            fields: [GameField(name: "Chips", value: "\(chips)", inline: true)],
            color: bettingColor,
            buttons: stakes.map { stake in
                GameButton(
                    id: "\(betButtonPrefix)\(stake)",
                    label: "Deal \(stake)",
                    style: stake == stakes.last ? .primary : .secondary,
                    disabled: stake > chips
                )
            },
            footer: footer,
            thumbnailUrl: context.player.holdings.pictureUrl
        )
    }

    /// `left * right`, clamped at `Int.max` instead of trapping.
    ///
    /// Both sides are stakes and multipliers here, so only the top end can run
    /// away. ``Chips/applying(_:to:)`` and ``Chips/dailyStipend(_:perks:)`` clamp
    /// for the same stated reason: a total that traps is a table nobody can play.
    private static func saturatingMultiply(_ left: Int, _ right: Int) -> Int {
        let (product, overflow) = left.multipliedReportingOverflow(by: right)
        return overflow ? Int.max : product
    }

    /// `left + right`, clamped at `Int.max` instead of trapping.
    private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int.max : sum
    }

    /// Draw `count` cards, refilling the shoe first if it is running out.
    ///
    /// Both thresholds are the original's and both are kept, because replacing a
    /// shoe spends draws: a table replayed from a seed has to consume them in the
    /// same order to deal the same cards.
    ///
    /// Every caller today takes exactly one card, and the entry threshold is three
    /// times the mid-draw one, so ``refillMidDraw`` cannot fire as things stand. It
    /// is kept for the caller that takes more than one at a time, which is the only
    /// thing that could empty a shoe part way through.
    private static func take(
        _ shoe: [Card],
        count: Int,
        context: inout GameContext
    ) -> (cards: [Card], shoe: [Card]) {
        var remaining: [Card] = shoe
        if remaining.count < refillBeforeDraw {
            remaining = Cards.makeShoe(decks: 1, using: &context.rng)
        }
        var drawn: [Card] = []
        guard count > 0 else {
            return (drawn, remaining)
        }
        drawn.reserveCapacity(count)
        for _ in 0..<count {
            if remaining.count < refillMidDraw {
                remaining = Cards.makeShoe(decks: 1, using: &context.rng)
            }
            // A refilled shoe is never empty, so this only guards against a future
            // deck size of zero rather than a reachable state.
            guard let dealt = Cards.draw(remaining) else {
                break
            }
            drawn.append(dealt.card)
            remaining = dealt.shoe
        }
        return (drawn, remaining)
    }

    /// Play the dealer out: hit while under 17, stand on 17 and everything above.
    ///
    /// A soft 17 is hit no differently from a hard one. The original compares the
    /// best total only, and the house edge of the table is quoted on that.
    private static func dealerPlay(
        dealer: [Card],
        shoe: [Card],
        context: inout GameContext
    ) -> (dealer: [Card], shoe: [Card], drew: [Card]) {
        var hand: [Card] = dealer
        var remaining: [Card] = shoe
        var drew: [Card] = []
        while Cards.handValue(hand).total < 17 {
            let drawn = take(remaining, count: 1, context: &context)
            remaining = drawn.shoe
            if drawn.cards.isEmpty {
                break
            }
            hand += drawn.cards
            drew += drawn.cards
        }
        return (hand, remaining, drew)
    }

    /// What the dealer turned over after you stood, as a sentence or nothing.
    ///
    /// The hand goes from one card and a face-down to the whole thing in a single
    /// edit, so without this nothing says the dealer drew at all: it just arrives
    /// on 21 and takes the hand.
    private static func drawLine(_ drew: [Card]) -> String {
        guard !drew.isEmpty else { return "The dealer stood." }
        return "The dealer drew " + drew.map(\.label).joined(separator: ", ") + "."
    }

    /// One hand as deck codes, so a picture would match the text line exactly.
    ///
    /// Mirrors ``cardLine(_:hideSecond:)``: the same hole card is hidden in both, so
    /// a drawn table and a written one can never disagree about what is face up.
    private static func faceCodes(_ cards: [Card], hideSecond: Bool) -> [String] {
        cards.enumerated().map { index, card in
            hideSecond && index == 1 ? Cards.faceDownCode : card.code
        }
    }

    /// One hand as a row of faces, with the hole card masked while it is face down.
    private static func cardLine(_ cards: [Card], hideSecond: Bool) -> String {
        var faces: [String] = []
        faces.reserveCapacity(cards.count)
        for (index, card) in cards.enumerated() {
            faces.append(hideSecond && index == 1 ? "??" : card.label)
        }
        return faces.joined(separator: "  ")
    }
}
