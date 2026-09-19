import Foundation
import Testing
@testable import Games

/// Higher or lower: the streak, the payout, and what a stale click does.
@Suite("Higher or lower")
struct HighLowTests {

    private func context(seed: UInt32 = 0, at instant: Date? = nil) -> GameContext {
        Fixture.context(seed: seed, at: instant)
    }

    private func card(_ rank: Rank, _ suit: Suit = .spades) -> Card {
        Card(rank: rank, suit: suit, id: "0-\(rank.rawValue)\(suit.rawValue)")
    }

    /// Filler under the cards a case cares about, deep enough that nothing refills.
    private func padding(_ count: Int) -> [Card] {
        (0..<count).map { Card(rank: .two, suit: .clubs, id: "pad-\($0)") }
    }

    /// An idle table that shows `shown` on the next open and draws `drawn` on
    /// settle.
    private func idleTable(shown: Rank, drawn: Rank, streak: Int = 0) -> HighLowState {
        HighLowState(
            phase: .idle,
            shoe: padding(18) + [card(drawn, .hearts), card(shown, .spades)],
            streak: streak
        )
    }

    /// An open table already showing `shown`, with `drawn` waiting on top.
    private func openTable(
        shown: Rank,
        drawn: Rank,
        streak: Int = 0,
        called: HighLowCall? = nil
    ) -> HighLowState {
        HighLowState(
            phase: .open,
            shown: card(shown, .spades),
            shoe: padding(18) + [card(drawn, .hearts)],
            streak: streak,
            called: called
        )
    }

    // MARK: - Shape

    @Test("A fresh table is idle with a whole deck waiting")
    func initialTable() {
        var ctx = context()
        let state = HighLow.initial(context: &ctx)
        #expect(state.phase == .idle)
        #expect(state.shown == nil)
        #expect(state.next == nil)
        #expect(state.shoe.count == Cards.deckSize)
        #expect(state.streak == 0)
        #expect(state.result == nil)
        #expect(state.payout == 0)
        #expect(state.seed == 0)
        #expect(HighLow.legalActions(state) == ["open"])
    }

    @Test("Drawing shows the top card, records the seed, and moves no chips")
    func openShowsACard() {
        var ctx = context(seed: 0)
        let opened = HighLow.open(idleTable(shown: .five, drawn: .king), context: &ctx)
        #expect(opened.chipDelta == 0)
        #expect(opened.state.phase == .open)
        #expect(opened.state.shown == card(.five, .spades))
        #expect(opened.state.next == nil)
        #expect(opened.state.shoe.count == 19)
        #expect(opened.state.shoe.last == card(.king, .hearts))
        // The deal itself spent no draws, so the seed on the card is the stream's
        // first forked seed. It is printed so a player can see the deal they were
        // dealt was not re-rolled under them.
        #expect(opened.state.seed == 1_144_304_737)
        #expect(HighLow.legalActions(opened.state) == ["higher", "lower"])
    }

    @Test("Drawing again clears the last result but keeps the run going")
    func reopenKeepsTheStreak() {
        var ctx = context()
        var resolved = openTable(shown: .five, drawn: .king, streak: 3)
        resolved.phase = .resolved
        resolved.result = .win
        resolved.judgedCall = .higher
        resolved.payout = 12
        resolved.next = card(.king, .hearts)
        resolved.called = .higher
        let reopened = HighLow.open(resolved, context: &ctx)
        #expect(reopened.chipDelta == 0)
        #expect(reopened.state.phase == .open)
        #expect(reopened.state.result == nil)
        #expect(reopened.state.judgedCall == nil)
        #expect(reopened.state.payout == 0)
        #expect(reopened.state.next == nil)
        #expect(reopened.state.streak == 3)
        #expect(reopened.state.shown == card(.king, .hearts))
    }

    @Test("A thin shoe is replaced before the table has to think about it")
    func refillThreshold() {
        var ctx = context()
        var thin = idleTable(shown: .five, drawn: .king)
        thin.shoe = Array(thin.shoe.suffix(12))
        let refilled = HighLow.open(thin, context: &ctx)
        #expect(refilled.state.shoe.count == Cards.deckSize - 1)
        #expect(!refilled.state.shoe.contains(where: { $0.id.hasPrefix("pad-") }))

        var other = context()
        var deep = idleTable(shown: .five, drawn: .king)
        deep.shoe = Array(deep.shoe.suffix(13))
        let dealt = HighLow.open(deep, context: &other)
        #expect(dealt.state.shoe.count == 12)
        #expect(dealt.state.shown == card(.five, .spades))
    }

    // MARK: - Calling

    @Test("A right call settles at once and pays the streak")
    func winPays() {
        var ctx = context()
        let called = HighLow.call(openTable(shown: .five, drawn: .king), side: .higher, context: &ctx)
        #expect(called.chipDelta == 8)
        #expect(called.state.phase == .resolved)
        #expect(called.state.result == .win)
        #expect(called.state.judgedCall == .higher)
        #expect(called.state.streak == 1)
        #expect(called.state.payout == 8)
        #expect(called.state.next == card(.king, .hearts))
        #expect(called.state.shoe.count == 18)
    }

    @Test("Calling lower wins when the draw falls")
    func lowerWins() {
        var ctx = context()
        let called = HighLow.call(openTable(shown: .queen, drawn: .three), side: .lower, context: &ctx)
        #expect(called.chipDelta == 8)
        #expect(called.state.result == .win)
        #expect(called.state.judgedCall == .lower)
        #expect(called.state.streak == 1)
    }

    @Test("A wrong call costs the run, not a chip")
    func lossZeroesTheStreak() {
        var ctx = context()
        let called = HighLow.call(
            openTable(shown: .king, drawn: .five, streak: 3),
            side: .higher,
            context: &ctx
        )
        // Nothing is staked to play, so losing pays nothing rather than taking
        // anything: the game stays free (`PLAY-8`).
        #expect(called.chipDelta == 0)
        #expect(called.state.result == .lose)
        #expect(called.state.streak == 0)
        #expect(called.state.payout == 0)
        #expect(called.state.judgedCall == .higher)
        #expect(called.state.next == card(.five, .hearts))
    }

    @Test("Equal ranks push and hold the run where it was")
    func equalRanksPush() {
        var ctx = context()
        let called = HighLow.call(
            openTable(shown: .nine, drawn: .nine, streak: 3),
            side: .lower,
            context: &ctx
        )
        #expect(called.chipDelta == 0)
        #expect(called.state.result == .push)
        #expect(called.state.streak == 3)
        #expect(called.state.payout == 0)
        #expect(called.state.judgedCall == .lower)
    }

    @Test("A settle with nothing called is a push and judges no call")
    func settleWithoutACall() {
        var ctx = context()
        let settled = HighLow.settle(openTable(shown: .five, drawn: .king), context: &ctx)
        #expect(settled.chipDelta == 0)
        #expect(settled.state.result == .push)
        #expect(settled.state.judgedCall == nil)
        #expect(settled.state.payout == 0)
    }

    @Test("The win that reaches a streak is the win paid at it")
    func streakPayouts() {
        var ctx = context()
        let second = HighLow.settle(
            openTable(shown: .five, drawn: .king, streak: 1, called: .higher),
            context: &ctx
        )
        #expect(second.state.streak == 2)
        #expect(second.chipDelta == 10)
        #expect(second.state.payout == 10)

        let ninth = HighLow.settle(
            openTable(shown: .five, drawn: .king, streak: 8, called: .higher),
            context: &ctx
        )
        #expect(ninth.state.streak == 9)
        #expect(ninth.chipDelta == 24)

        let far = HighLow.settle(
            openTable(shown: .five, drawn: .king, streak: 20, called: .higher),
            context: &ctx
        )
        #expect(far.state.streak == 21)
        #expect(far.chipDelta == 24)
    }

    @Test("A click from a card that has moved on changes nothing")
    func refusalsLeaveTheTableAlone() {
        var ctx = context()
        var idle = idleTable(shown: .five, drawn: .king)
        idle.streak = 6
        #expect(HighLow.call(idle, side: .higher, context: &ctx).state == idle)
        #expect(HighLow.call(idle, side: .higher, context: &ctx).chipDelta == 0)
        #expect(HighLow.settle(idle, context: &ctx).state == idle)

        var resolved = openTable(shown: .five, drawn: .king)
        resolved.phase = .resolved
        resolved.result = .win
        resolved.payout = 10
        #expect(HighLow.call(resolved, side: .higher, context: &ctx).state == resolved)

        var headless = openTable(shown: .five, drawn: .king)
        headless.shown = nil
        #expect(HighLow.settle(headless, context: &ctx).state == headless)
    }

    // MARK: - The card

    @Test("The idle and open cards carry the copy, the colours and the button ids")
    func idleAndOpenCards() {
        var ctx = context()
        let idleCard = HighLow.card(HighLow.initial(context: &ctx))
        #expect(idleCard.title == "Higher or Lower")
        #expect(idleCard.description == "A card comes off the top. Higher or lower?")
        #expect(idleCard.color == 0x2a2723)
        #expect(idleCard.fields.isEmpty)
        #expect(idleCard.footer == "Streak 0")
        #expect(idleCard.buttons.map(\.id) == ["ng_highlow_open"])
        #expect(idleCard.buttons.map(\.label) == ["Draw"])
        #expect(idleCard.buttons.map(\.style) == [.primary])

        var opening = context(seed: 0)
        let opened = HighLow.open(idleTable(shown: .ten, drawn: .three), context: &opening)
        let openCard = HighLow.card(opened.state)
        #expect(openCard.description == "Showing **10\u{2660}**. Is the next card higher or lower?")
        #expect(openCard.color == 0x3a342c)
        // No tally of anybody else's calls: there is one player and it is the
        // person reading the card (`PLAY-2`).
        #expect(openCard.fields.isEmpty)
        #expect(openCard.buttons.map(\.id) == ["ng_highlow_higher", "ng_highlow_lower"])
        #expect(openCard.buttons.map(\.label) == ["Higher", "Lower"])
        #expect(openCard.buttons.map(\.style) == [.success, .danger])
        #expect(openCard.footer == "Streak 0 \u{00b7} seed 4434b461")
    }

    @Test("The settled card names the draw and the verdict")
    func resolvedCards() {
        var ctx = context()
        let win = HighLow.call(openTable(shown: .five, drawn: .king), side: .higher, context: &ctx)
        let winCard = HighLow.card(win.state)
        #expect(winCard.description == "Was **5\u{2660}**. Drew **K\u{2665}**. Right call. +8 chips.")
        #expect(winCard.color == 0x6e8b6e)
        #expect(winCard.footer == "Streak 1")
        #expect(winCard.buttons.map(\.id) == ["ng_highlow_open"])
        #expect(winCard.buttons.map(\.label) == ["Again"])
        #expect(HighLow.legalActions(win.state) == ["open"])

        let loss = HighLow.call(openTable(shown: .king, drawn: .five), side: .higher, context: &ctx)
        #expect(HighLow.card(loss.state).description == "Was **K\u{2660}**. Drew **5\u{2665}**. Wrong call.")
        #expect(HighLow.card(loss.state).color == 0xb54a4a)

        let push = HighLow.call(
            openTable(shown: .nine, drawn: .nine, streak: 2),
            side: .higher,
            context: &ctx
        )
        #expect(HighLow.card(push.state).description == "Was **9\u{2660}**. Drew **9\u{2665}**. Push.")
        #expect(HighLow.card(push.state).color == 0x6a6560)
        #expect(HighLow.card(push.state).footer == "Streak 2")
    }

    @Test("A card shows only the picture it was handed")
    func cardPicture() {
        var ctx = context()
        let idle = HighLow.initial(context: &ctx)
        #expect(HighLow.card(idle).thumbnailUrl == nil)
        #expect(HighLow.card(idle, pictureUrl: "https://example.test/a.png").thumbnailUrl
            == "https://example.test/a.png")
    }

    @Test("A table survives a round trip through storage")
    func codableRoundTrip() throws {
        var ctx = context(seed: 7)
        let opened = HighLow.open(idleTable(shown: .six, drawn: .jack), context: &ctx)
        let called = HighLow.call(opened.state, side: .higher, context: &ctx)
        let data = try JSONEncoder().encode(called.state)
        #expect(try JSONDecoder().decode(HighLowState.self, from: data) == called.state)
    }

    @Test("Nothing here reads a clock, so the hour never changes the cards")
    func clockIsIrrelevant() {
        var morning = context(seed: 3, at: Fixture.now)
        var midnight = context(seed: 3, at: Fixture.now.addingTimeInterval(60 * 60 * 12))
        let first = HighLow.open(HighLow.initial(context: &morning), context: &morning)
        let second = HighLow.open(HighLow.initial(context: &midnight), context: &midnight)
        #expect(first.state == second.state)
    }
}
