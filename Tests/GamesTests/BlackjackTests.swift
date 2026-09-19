import Foundation
import Testing
@testable import Games

/// Blackjack: the deal, the settle precedence, and where the chips actually move.
///
/// Every case asserts the chip delta as well as the state. The delta is the only
/// thing that leaves this module, so a hand that looks right and pays wrong is the
/// failure worth catching.
@Suite("Blackjack")
struct BlackjackTests {

    private func table(seed: UInt32, chips: Int = 200) -> GameContext {
        Fixture.context(seed: seed, chips: chips)
    }

    /// A fresh table plus the opening deal, the start of nearly every case below.
    private func dealt(
        seed: UInt32,
        amount: Int = 10,
        chips: Int = 200
    ) -> (state: BlackjackState, delta: Int, context: GameContext) {
        var context = table(seed: seed, chips: chips)
        let start = Blackjack.initial(context: &context)
        let result = Blackjack.deal(start, amount: amount, context: &context)
        return (result.state, result.chipDelta, context)
    }

    private func card(_ rank: Rank, _ suit: Suit = .spades) -> Card {
        Card(rank: rank, suit: suit, id: "x-\(rank.rawValue)\(suit.rawValue)")
    }

    // MARK: - Shape

    @Test("A fresh table waits for a bet on a full shoe")
    func freshTable() {
        var context = table(seed: 2)
        let start = Blackjack.initial(context: &context)
        #expect(start.phase == .betting)
        #expect(start.bet == 0)
        #expect(start.shoe.count == 52)
        #expect(start.player.isEmpty)
        #expect(start.dealer.isEmpty)
        #expect(start.hideHole)
        #expect(start.outcome == nil)
        #expect(start.payout == 0)
        #expect(!start.doubled)
        #expect(start.message == "Put down a bet in chips. The dealer stands on 17.")
        #expect(Blackjack.legalActions(start) == ["bet"])
    }

    // MARK: - Refusals

    @Test("A bet under the minimum is refused and costs nothing at all")
    func belowMinimumBet() {
        var context = table(seed: 2)
        let start = Blackjack.initial(context: &context)
        let before = context.rng.state
        let result = Blackjack.deal(start, amount: Chips.minimumBet - 1, context: &context)
        var expected = start
        expected.message = "Minimum bet is 10. You have 200."
        #expect(result.chipDelta == 0)
        #expect(result.state == expected)
        // No cards dealt and no draws spent: a fat-fingered bet must not walk the
        // shoe on under the hand that follows it.
        #expect(context.rng.state == before)
    }

    @Test("A bet bigger than the pile is refused and says so")
    func overTheChipsHeld() {
        var context = table(seed: 2, chips: 200)
        let start = Blackjack.initial(context: &context)
        let before = context.rng.state
        let result = Blackjack.deal(start, amount: 500, context: &context)
        var expected = start
        expected.message = "Not enough chips: that bet is 500 and you have 200."
        #expect(result.chipDelta == 0)
        #expect(result.state == expected)
        #expect(context.rng.state == before)
    }

    @Test("Betting everything is allowed")
    func betEverything() {
        let opened = dealt(seed: 2, amount: 200, chips: 200)
        #expect(opened.state.phase == .playing)
        #expect(opened.state.bet == 200)
        #expect(opened.delta == -200)
    }

    @Test("Dealing on a hand already in play does nothing")
    func dealOutOfPhase() {
        let opened = dealt(seed: 2)
        var context = opened.context
        let before = context.rng.state
        let again = Blackjack.deal(opened.state, amount: 25, context: &context)
        #expect(again.chipDelta == 0)
        #expect(again.state == opened.state)
        #expect(context.rng.state == before)
    }

    // MARK: - The deal

    @Test("The deal takes the stake and puts two cards on each side")
    func dealTakesTheStake() {
        let opened = dealt(seed: 2)
        #expect(opened.delta == -10)
        #expect(opened.state.phase == .playing)
        #expect(opened.state.bet == 10)
        #expect(Fixture.labels(opened.state.player) == ["K\u{2666}", "2\u{2665}"])
        #expect(Fixture.labels(opened.state.dealer) == ["4\u{2665}", "A\u{2666}"])
        #expect(opened.state.shoe.count == 48)
        #expect(opened.state.hideHole)
        #expect(opened.state.outcome == nil)
        #expect(opened.state.message == "Hit, stand, or double.")
        #expect(Blackjack.legalActions(opened.state) == ["hit", "stand", "double"])
    }

    @Test("A natural settles on the deal and pays three to two")
    func naturalPaysThreeToTwo() {
        let ten = dealt(seed: 7)
        #expect(ten.state.phase == .settled)
        #expect(Fixture.labels(ten.state.player) == ["A\u{2660}", "10\u{2663}"])
        #expect(ten.state.outcome == .blackjack)
        #expect(ten.state.payout == 25)
        #expect(ten.delta == 15)
        #expect(!ten.state.hideHole)
        #expect(ten.state.message == "21 on two. Pays 3:2.")
        #expect(Blackjack.legalActions(ten.state) == ["next"])

        let forty = dealt(seed: 7, amount: 40)
        #expect(forty.state.payout == 100)
        #expect(forty.delta == 60)
    }

    @Test("A three to two return keeps the odd half chip out of the payout")
    func naturalFloorsTheOddHalf() {
        let odd = dealt(seed: 7, amount: 25)
        #expect(odd.state.payout == 25 + 37)
        #expect(odd.delta == 37)
    }

    @Test("The dealer's natural takes the stake on the deal")
    func dealerNaturalCollects() {
        let opened = dealt(seed: 1)
        #expect(opened.state.phase == .settled)
        #expect(Fixture.labels(opened.state.dealer) == ["A\u{2660}", "10\u{2663}"])
        #expect(opened.state.outcome == .lose)
        #expect(opened.state.payout == 0)
        #expect(opened.delta == -10)
        #expect(!opened.state.hideHole)
        #expect(opened.state.message == "Dealer 21. You lose the bet.")
    }

    @Test("Two naturals push and the stake comes straight back")
    func twoNaturalsPush() {
        let opened = dealt(seed: 26)
        #expect(opened.state.outcome == .push)
        #expect(opened.state.payout == 10)
        #expect(opened.delta == 0)
        #expect(opened.state.message == "Two 21s. Push.")
    }

    // MARK: - Hitting

    @Test("A hit draws one card, names it, and moves no chips")
    func hitDrawsWithoutMovingChips() {
        let opened = dealt(seed: 2)
        var context = opened.context
        let result = Blackjack.hit(opened.state, context: &context)
        #expect(result.chipDelta == 0)
        #expect(result.state.phase == .playing)
        #expect(Fixture.labels(result.state.player) == ["K\u{2666}", "2\u{2665}", "4\u{2663}"])
        #expect(result.state.shoe.count == 47)
        #expect(result.state.message == "Drew 4\u{2663}. 16.")
        #expect(Blackjack.legalActions(result.state) == ["hit", "stand"])
    }

    @Test("Hitting into a bust settles for nothing and never debits twice")
    func hitBustSettles() {
        let opened = dealt(seed: 3)
        var context = opened.context
        let result = Blackjack.hit(opened.state, context: &context)
        // The stake left on the deal. A bust that debited again would take two.
        #expect(result.chipDelta == 0)
        #expect(result.state.phase == .settled)
        #expect(result.state.outcome == .bust)
        #expect(result.state.payout == 0)
        #expect(!result.state.hideHole)
        #expect(Fixture.labels(result.state.player) == ["Q\u{2666}", "10\u{2665}", "J\u{2666}"])
        #expect(result.state.message == "Drew J\u{2666}. 30, bust. The dealer collects.")
    }

    @Test("Hitting twice into a bust still moves no chips")
    func hitTwiceIntoBust() {
        let opened = dealt(seed: 8)
        var context = opened.context
        let first = Blackjack.hit(opened.state, context: &context)
        #expect(first.chipDelta == 0)
        #expect(first.state.message == "Drew 3\u{2666}. 15.")
        let second = Blackjack.hit(first.state, context: &context)
        #expect(second.chipDelta == 0)
        #expect(second.state.outcome == .bust)
        #expect(second.state.message == "Drew 9\u{2665}. 24, bust. The dealer collects.")
    }

    @Test("Hitting a hand that is over does nothing")
    func hitOutOfPhase() {
        let opened = dealt(seed: 7)
        var context = opened.context
        let before = context.rng.state
        let result = Blackjack.hit(opened.state, context: &context)
        #expect(result.chipDelta == 0)
        #expect(result.state == opened.state)
        #expect(context.rng.state == before)
    }

    // MARK: - Standing

    @Test("Standing on the better total returns the stake and the win")
    func standWinsOnTotal() {
        let opened = dealt(seed: 4)
        var context = opened.context
        let result = Blackjack.stand(opened.state, context: &context)
        #expect(result.state.outcome == .win)
        #expect(result.state.payout == 20)
        // The payout alone, because the stake was taken on the deal. Netting it
        // against the stake again pays the hand twice.
        #expect(result.chipDelta == 20)
        #expect(!result.state.hideHole)
        #expect(Fixture.labels(result.state.dealer) == ["4\u{2665}", "5\u{2660}", "J\u{2663}"])
        #expect(result.state.message == "The dealer drew J\u{2663}. 20 over 19. Even money.")
    }

    @Test("Standing under the dealer pays nothing beyond the stake already taken")
    func standLosesOnTotal() {
        let opened = dealt(seed: 2)
        var context = opened.context
        let hit = Blackjack.hit(opened.state, context: &context)
        let result = Blackjack.stand(hit.state, context: &context)
        #expect(result.state.outcome == .lose)
        #expect(result.state.payout == 0)
        #expect(result.chipDelta == 0)
        #expect(result.state.message == "The dealer drew 4\u{2666}. 16 under the dealer's 19.")
    }

    @Test("The dealer hits under seventeen and stands the moment it gets there")
    func dealerStandsOnSeventeen() {
        let opened = dealt(seed: 11)
        var context = opened.context
        #expect(Cards.handValue(opened.state.dealer).total == 5)
        let result = Blackjack.stand(opened.state, context: &context)
        #expect(Cards.handValue(result.state.dealer).total == 17)
        #expect(result.state.outcome == .lose)
        #expect(result.chipDelta == 0)
        #expect(result.state.message == "The dealer drew 2\u{2663}, K\u{2665}. 16 under the dealer's 17.")
    }

    @Test("A dealer already on seventeen or better draws nothing")
    func dealerStandsPat() {
        let opened = dealt(seed: 28)
        var context = opened.context
        #expect(Cards.handValue(opened.state.dealer).total == 20)
        let result = Blackjack.stand(opened.state, context: &context)
        #expect(result.state.dealer.count == 2)
        #expect(result.state.shoe.count == opened.state.shoe.count)
        #expect(result.state.outcome == .push)
        #expect(result.state.payout == 10)
        #expect(result.chipDelta == 10)
        #expect(result.state.message == "The dealer stood. Both 20. Push.")
    }

    @Test("A dealer bust pays even money")
    func dealerBustPaysEven() {
        let opened = dealt(seed: 3)
        var context = opened.context
        let result = Blackjack.stand(opened.state, context: &context)
        #expect(Cards.handValue(result.state.dealer).total == 26)
        #expect(result.state.outcome == .win)
        #expect(result.state.payout == 20)
        #expect(result.chipDelta == 20)
        #expect(result.state.message == "The dealer drew J\u{2666}, J\u{2663}. Dealer busts. Pays even money.")
    }

    @Test("Standing before a bet does nothing")
    func standOutOfPhase() {
        var context = table(seed: 2)
        let start = Blackjack.initial(context: &context)
        let before = context.rng.state
        let result = Blackjack.stand(start, context: &context)
        #expect(result.chipDelta == 0)
        #expect(result.state == start)
        #expect(context.rng.state == before)
    }

    // MARK: - Doubling

    @Test("Doubling stakes a second bet, takes one card, and settles")
    func doubleStakesAndSettles() {
        let opened = dealt(seed: 8)
        var context = opened.context
        let result = Blackjack.double(opened.state, context: &context)
        #expect(result.state.phase == .settled)
        #expect(result.state.bet == 20)
        #expect(result.state.doubled)
        #expect(result.state.outcome == .win)
        #expect(result.state.payout == 40)
        // The extra stake and the return in one delta, because the extra is taken
        // here rather than on the deal.
        #expect(result.chipDelta == 30)
        #expect(!result.state.hideHole)
        #expect(
            result.state.message
                == "Doubled, drew 3\u{2666}. The dealer drew 9\u{2665}. Dealer busts. Pays even money."
        )
    }

    @Test("Doubling into a bust loses only the extra stake")
    func doubleBustLosesTheExtra() {
        let opened = dealt(seed: 3)
        var context = opened.context
        let result = Blackjack.double(opened.state, context: &context)
        #expect(result.state.phase == .settled)
        #expect(result.state.bet == 20)
        #expect(result.state.doubled)
        #expect(result.state.outcome == .bust)
        #expect(result.state.payout == 0)
        #expect(result.chipDelta == -10)
        // The dealer never plays out a hand that already lost.
        #expect(result.state.dealer.count == 2)
        #expect(result.state.message == "Double bust. The dealer collects.")
    }

    @Test("A doubled push returns both halves of the stake")
    func doublePushReturnsBoth() {
        let opened = dealt(seed: 10)
        var context = opened.context
        let result = Blackjack.double(opened.state, context: &context)
        #expect(result.state.bet == 20)
        #expect(result.state.outcome == .push)
        #expect(result.state.payout == 20)
        #expect(result.chipDelta == 10)
    }

    @Test("A double that cannot be taken says why instead of looking dead")
    func refusedDoublesExplain() {
        // A player whose remaining chips will not cover a second stake. The
        // context carries the balance as the caller read it, so it is the caller
        // who hands in the post-deal figure; the reducer only compares.
        var poorTable = BlackjackState(phase: .playing, bet: 50)
        poorTable.player = [card(.five), card(.six)]
        var poorContext = table(seed: 2, chips: 10)
        // The card must say so: an untouched state re-renders an identical card
        // and reads as a button that did nothing.
        let poor = Blackjack.double(poorTable, context: &poorContext)
        #expect(poor.chipDelta == 0)
        #expect(poor.state.message == "Not enough chips to double.")

        var fresh = table(seed: 2)
        let start = Blackjack.initial(context: &fresh)
        let early = Blackjack.double(start, context: &fresh)
        #expect(early.state.message == "Put a bet down first.")
        #expect(early.chipDelta == 0)

        let settled = dealt(seed: 7)
        var over = settled.context
        let late = Blackjack.double(settled.state, context: &over)
        #expect(late.state.message == "That hand is over. Deal the next one.")

        let played = dealt(seed: 2)
        var context3 = played.context
        let hit = Blackjack.hit(played.state, context: &context3)
        let afterHit = Blackjack.double(hit.state, context: &context3)
        #expect(afterHit.state.message == "Doubling is only on your first two cards.")
        #expect(afterHit.chipDelta == 0)
    }

    @Test("A hand cannot be doubled twice")
    func doubleOnlyOnce() {
        var state = BlackjackState(phase: .playing, bet: 10, doubled: true)
        state.player = [card(.five), card(.six)]
        var context = table(seed: 2)
        let result = Blackjack.double(state, context: &context)
        #expect(result.state.message == "Already doubled. One card is all a double gets.")
        #expect(result.chipDelta == 0)
    }

    // MARK: - The next hand

    @Test("The next hand keeps the cards that are left")
    func nextKeepsTheShoe() {
        let opened = dealt(seed: 7)
        var context = opened.context
        let result = Blackjack.next(opened.state, context: &context)
        #expect(result.chipDelta == 0)
        #expect(result.state.phase == .betting)
        #expect(result.state.bet == 0)
        #expect(result.state.player.isEmpty)
        #expect(result.state.shoe.count == opened.state.shoe.count)
        #expect(result.state.shoe.map(\.id) == opened.state.shoe.map(\.id))
    }

    @Test("Asking for the next hand mid-hand does nothing")
    func nextOutOfPhase() {
        let opened = dealt(seed: 2)
        var context = opened.context
        let result = Blackjack.next(opened.state, context: &context)
        #expect(result.state == opened.state)
        #expect(result.chipDelta == 0)
    }

    // MARK: - The shoe

    /// Filler that is obvious in an expectation: a refill replaces every one of
    /// these with a real card.
    private func padding(_ count: Int) -> [Card] {
        (0..<count).map { Card(rank: .two, suit: .clubs, id: "pad-\($0)") }
    }

    private func pads(_ cards: [Card]) -> Bool {
        cards.allSatisfy { $0.id.hasPrefix("pad-") }
    }

    @Test("A shoe thin enough is replaced before the deal, and one card deeper is not")
    func refillBeforeTheDeal() {
        // Both sides of the boundary, because a refill spends draws: a table
        // replayed from a seed deals the same cards only if it refills at the same
        // points. No test reached this before, since every case starts from a full
        // shoe.
        var context = table(seed: 2)
        let deep = BlackjackState(phase: .betting, shoe: padding(16))
        let before = context.rng.state
        let dealt = Blackjack.deal(deep, amount: 10, context: &context)
        #expect(dealt.state.shoe.count == 12)
        #expect(pads(dealt.state.shoe))
        #expect(context.rng.state == before)

        var thinContext = table(seed: 2)
        let thin = BlackjackState(phase: .betting, shoe: padding(15))
        let beforeRefill = thinContext.rng.state
        let refilled = Blackjack.deal(thin, amount: 10, context: &thinContext)
        #expect(refilled.state.shoe.count == Cards.deckSize - 4)
        #expect(!refilled.state.shoe.contains { $0.id.hasPrefix("pad-") })
        // A refill is a shuffle, so it spends draws. That is the reason the
        // threshold cannot be moved without changing every replay.
        #expect(thinContext.rng.state != beforeRefill)
    }

    @Test("A shoe thin enough is replaced before a draw, and one card deeper is not")
    func refillBeforeTheDraw() {
        let hand = [card(.two), card(.two, .hearts)]
        var context = table(seed: 2)
        let deep = BlackjackState(phase: .playing, bet: 10, shoe: padding(12), player: hand, dealer: hand)
        let before = context.rng.state
        let drawn = Blackjack.hit(deep, context: &context)
        #expect(drawn.state.shoe.count == 11)
        #expect(pads(drawn.state.shoe))
        #expect(context.rng.state == before)

        var thinContext = table(seed: 2)
        let thin = BlackjackState(phase: .playing, bet: 10, shoe: padding(11), player: hand, dealer: hand)
        let refilled = Blackjack.hit(thin, context: &thinContext)
        #expect(refilled.state.shoe.count == Cards.deckSize - 1)
        #expect(!refilled.state.shoe.contains { $0.id.hasPrefix("pad-") })
    }

    // MARK: - The settle precedence

    @Test("A bust loses even when the dealer would have busted too")
    func bustBeatsEverything() {
        let hand = [card(.king), card(.queen), card(.five)]
        let dealerHand = [card(.king, .hearts), card(.queen, .hearts), card(.five, .hearts)]
        let settled = Blackjack.settleWith(player: hand, dealer: dealerHand, bet: 10)
        #expect(settled.outcome == .bust)
        #expect(settled.payout == 0)
    }

    @Test("The dealer's natural beats a drawn twenty-one")
    func dealerNaturalBeatsADrawnTwentyOne() {
        // Judging the totals first would pay this hand, and judging a dealer bust
        // before a natural would pay hands that lost. The order is the rule.
        let drawnTwentyOne = [card(.seven), card(.seven, .hearts), card(.seven, .clubs)]
        let natural = [card(.ace, .hearts), card(.king, .hearts)]
        let settled = Blackjack.settleWith(player: drawnTwentyOne, dealer: natural, bet: 10)
        #expect(settled.outcome == .lose)
        #expect(settled.payout == 0)
    }

    @Test("A drawn twenty-one is not a natural and pays even, not three to two")
    func drawnTwentyOnePaysEven() {
        let drawnTwentyOne = [card(.seven), card(.seven, .hearts), card(.seven, .clubs)]
        let twenty = [card(.king, .hearts), card(.queen, .hearts)]
        let settled = Blackjack.settleWith(player: drawnTwentyOne, dealer: twenty, bet: 10)
        #expect(settled.outcome == .win)
        #expect(settled.payout == 20)
    }

    @Test("Two naturals push rather than one of them winning")
    func naturalsPush() {
        let natural = [card(.ace), card(.king)]
        let other = [card(.ace, .hearts), card(.king, .hearts)]
        let settled = Blackjack.settleWith(player: natural, dealer: other, bet: 10)
        #expect(settled.outcome == .push)
        #expect(settled.payout == 10)
    }

    @Test("A stake nothing capped pays out instead of taking the process down")
    func payoutSaturates() {
        // Nothing in this package caps a pile: a host can configure a daily bonus
        // that leaves somebody on the ceiling (`stipendSaturates`), `Chips.applying`
        // pays it, and `deal` accepts any bet that pile covers (`betEverything`).
        // Every leg of the payout has to survive the whole of it.
        let natural = [card(.ace), card(.king)]
        let twenty = [card(.king, .hearts), card(.queen, .hearts)]
        let busted = [card(.king, .hearts), card(.queen, .hearts), card(.five, .hearts)]
        let drawnTwentyOne = [card(.seven), card(.seven, .hearts), card(.seven, .clubs)]
        #expect(Blackjack.settleWith(player: natural, dealer: twenty, bet: .max).payout == .max)
        #expect(Blackjack.settleWith(player: drawnTwentyOne, dealer: twenty, bet: .max).payout == .max)
        #expect(Blackjack.settleWith(player: drawnTwentyOne, dealer: busted, bet: .max).payout == .max)
        #expect(Blackjack.settleWith(player: twenty, dealer: twenty, bet: .max).payout == .max)

        // The clamp is a ceiling, not a rounding: the biggest stake whose 3:2 still
        // fits pays the exact figure.
        let biggest = Int.max / 3
        #expect(
            Blackjack.settleWith(player: natural, dealer: twenty, bet: biggest).payout
                == 7_686_143_364_045_646_505
        )
    }

    @Test("A hand dealt for everything a saturated pile holds still settles")
    func dealForEverything() {
        var context = table(seed: 7, chips: .max)
        let start = Blackjack.initial(context: &context)
        let result = Blackjack.deal(start, amount: .max, context: &context)
        #expect(result.state.bet == .max)
        // Seed 7 turns up a natural on the deal, which is the leg that multiplied
        // the stake by three.
        #expect(result.state.phase == .settled)
        #expect(result.state.outcome == .blackjack)
        #expect(result.state.payout == .max)
        #expect(Chips.applying(result.chipDelta, to: .max) == .max)
    }

    @Test("Doubling a stake at the ceiling clamps rather than trapping")
    func doubleSaturates() {
        var context = table(seed: 2, chips: .max)
        let start = Blackjack.initial(context: &context)
        let opened = Blackjack.deal(start, amount: .max, context: &context)
        #expect(opened.state.phase == .playing)
        let doubled = Blackjack.double(opened.state, context: &context)
        #expect(doubled.state.doubled)
        #expect(doubled.state.bet == .max)
        #expect(doubled.state.phase == .settled)
    }

    @Test("An odd stake floors the half chip out of a three to two payout")
    func oddStakeFloors() {
        let natural = [card(.ace), card(.king)]
        let twenty = [card(.king, .hearts), card(.queen, .hearts)]
        #expect(Blackjack.settleWith(player: natural, dealer: twenty, bet: 25).payout == 62)
        #expect(Blackjack.settleWith(player: natural, dealer: twenty, bet: 1).payout == 2)
    }

    // MARK: - The card

    @Test("The betting card shows the stakes and greys the ones out of reach")
    func bettingCard() {
        var context = table(seed: 2, chips: 30)
        let start = Blackjack.initial(context: &context)
        let card = Blackjack.card(start, context: context)
        #expect(card.title == "Blackjack")
        #expect(card.fields.map(\.name) == ["Chips"])
        #expect(card.fields[0].value == "30")
        #expect(card.buttons.map(\.id) == [
            "ng_blackjack_bet_10", "ng_blackjack_bet_25", "ng_blackjack_bet_50"
        ])
        #expect(card.buttons.map(\.disabled) == [false, false, true])
        #expect(card.buttons.map(\.style) == [.secondary, .secondary, .primary])
        #expect(card.description.contains("The dealer stands on 17"))
        #expect(card.footer == nil)
    }

    @Test("A refused bet is shown on the card rather than thrown away")
    func bettingCardShowsRefusals() {
        var context = table(seed: 2)
        let start = Blackjack.initial(context: &context)
        let refused = Blackjack.deal(start, amount: 1, context: &context)
        let card = Blackjack.card(refused.state, context: context)
        #expect(card.description.hasPrefix("Minimum bet is 10. You have 200."))
    }

    @Test("Too few chips for the smallest hand gets the way back, not the rules")
    func brokeCardRoutesOnwards() {
        var context = table(seed: 2, chips: 3)
        let start = Blackjack.initial(context: &context)
        let card = Blackjack.card(start, context: context)
        #expect(card.description == "You have **3** chips, and the smallest bet is **10**.")
        #expect(card.footer == Blackjack.brokeRoute)
        #expect(card.buttons.map(\.disabled) == [true, true, true])
        // Running out is a pause, not the end (`PLAY-8`).
        #expect(Blackjack.brokeRoute.contains("costs nothing to play"))
        #expect(Blackjack.brokeRoute.contains("daily claim"))
    }

    @Test("A live hand hides the hole card in the text and in the deck codes alike")
    func playingCardHidesTheHole() {
        let opened = dealt(seed: 2)
        let card = Blackjack.card(opened.state, context: opened.context)
        #expect(card.fields[0].name == "Dealer  (4+)")
        #expect(card.fields[0].value == "4\u{2665}  ??")
        #expect(card.fields[1].name == "You  (12)")
        #expect(card.hand[0] == ["4h", "back"])
        #expect(card.hand[1] == ["kd", "2h"])
        #expect(card.buttons.map(\.id) == [
            "ng_blackjack_hit", "ng_blackjack_stand", "ng_blackjack_double"
        ])
        #expect(card.description.hasPrefix("Hit, stand, or double."))
        #expect(card.description.contains("Bet: 10 chips."))
    }

    @Test("A settled hand turns the hole card over everywhere at once")
    func settledCardRevealsTheHole() {
        let opened = dealt(seed: 7)
        let card = Blackjack.card(opened.state, context: opened.context)
        #expect(!card.hand[0].contains(Cards.faceDownCode))
        #expect(!card.fields[0].value.contains("??"))
        #expect(card.buttons.map(\.id) == ["ng_blackjack_next"])
        #expect(card.footer == "Bet 10 \u{00b7} chips 200")
        #expect(card.color == 0x6e8b6e)
    }

    @Test("The stakes a card offers are the stakes the game deals for")
    func stakesAreTheOnesPlayed() {
        #expect(Blackjack.stakes == [10, 25, 50])
        // A rules page quotes these, so they must be read rather than retyped
        // (`LEARN-6`).
        #expect(Blackjack.stakes.filter { $0 >= Chips.minimumBet } == Blackjack.stakes)
    }

    // MARK: - Storage

    @Test("A hand survives a round trip through storage")
    func codableRoundTrip() throws {
        let opened = dealt(seed: 2)
        let data = try JSONEncoder().encode(opened.state)
        #expect(try JSONDecoder().decode(BlackjackState.self, from: data) == opened.state)
    }

    @Test("The same seed deals the same hand, every time")
    func handsReplay() {
        let first = dealt(seed: 99, amount: 25)
        let second = dealt(seed: 99, amount: 25)
        #expect(first.state == second.state)
        #expect(first.delta == second.delta)
    }
}
