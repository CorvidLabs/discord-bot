---
spec: games.spec.md
---

## Tasks

- [x] Port the generator, the shuffle and the weighted pick value for value,
      and pin them to the sequences the original produces.
- [x] Deck building, drawing and blackjack totals, with an empty shoe answering
      nil rather than throwing.
- [x] The chip economy: the daily claim, the streak payout, the forage
      cooldown, the zero floor and the clamps at both ends.
- [x] Three games as pure reducers, each returning one chip delta and one card.
- [x] Turn the original's two hardcoded collections into `CollectionPerk`, and
      reproduce their numbers through configuration.
- [x] Refuse a perk configuration that cannot work, naming the collection and
      the setting.
- [x] Refuse a collection id that is not in the shape the operator
      configuration these ids come from produces, so a host who configures both
      sides from one variable hears about the mismatch instead of running with
      perks that fire for nobody.
- [x] Cards as plain data, with the constants a rules page has to quote
      exported rather than retyped.
- [ ] Let a host name things: the game titles, the dealer, the currency and the
      button faces are constants here, and PLAY-10 says they are the host's.
- [ ] Let a host set what junk is worth and what a rung costs. `Shiny.meta` and
      `Shiny.nestCosts` are shipped numbers, and LEARN-8.b asks for this
      server's numbers.
- [ ] Publish the module's documentation once the package is released.

## Gaps

- **The vocabulary is ours, not the host's (PLAY-10).** The game titles, the
  word "dealer", the word "chips" and every button face are private constants
  in this module. A host can name their collections and what those are worth,
  but not the table they sit at.
- **The economy's numbers are shipped, not configured (LEARN-8.b).**
  `Chips.minimumBet`, `Blackjack.stakes`, `Chips.baseDailyStipend`,
  `Shiny.meta` and `Shiny.nestCosts` are the numbers this package plays by
  everywhere. They are exported so a rules page quotes rather than retypes them
  (LEARN-6), which is a smaller promise than LEARN-8.b makes.
- **Ownership is the host's to enforce (PLAY-2, PLAY-7).** Every state here is
  one player's table, which makes a private hand possible, but nothing in the
  module knows who pressed a button. A host that hands one player's state to
  another player's click gets no complaint from here.
- **Silent refusals, in higher or lower only.** Blackjack's wrong-phase
  refusals were the shape the refused Double had before it was found to look
  like a dead button: a duplicate tap returned the state exactly as it arrived
  and re-rendered a card nothing had changed on. They now write the phase on
  `message`, which costs the line the last action wrote. On a settled hand that
  means the verdict is replaced until the next deal; the hands, the totals and
  the colour still say how it went, and saying nothing at all was worse.
  `HighLow.call` and `HighLow.settle` in the wrong phase still answer nothing,
  because `HighLowState` carries no line and giving it one is a change to the
  shape a host stores rather than a change to a reducer. `HighLow.open` on a
  shoe that will not deal is not in this list: `refilled` hands back a whole
  deck, so that branch is unreachable and is kept as a total function rather
  than as a refusal anybody can meet.
- **The context's chips are a contract the types do not hold.**
  `Blackjack.deal` and `Blackjack.double` check a stake against
  `GameContext.player.chips`, so a host that passes a balance from before an
  earlier delta was applied can let a player stake chips they no longer have.
- **The port is verified by transcription.** The expected values in
  `GameRNGTests` and `ShinyDrawOrderTests` were taken from the original once.
  Nothing re-derives them, so a divergence introduced upstream would not be
  caught here.
- **`Blackjack.refillMidDraw` is unreachable today.** The entry threshold is
  three times it and every caller takes one card, so nothing exercises it. It
  is kept because removing it would change the deal the moment somebody draws
  two cards at once.

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
