---
spec: games.spec.md
---

## Automated Testing

`swift test` runs the whole package: 389 tests in 26 suites. The `Games`
target's own share is 158 tests in 9 suites, all offline, with no network, no
key and no database (`swift test --filter GamesTests`).

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `BlackjackTests.swift` | Unit | The deal, the settle precedence, the four chip deltas, the refusals that must cost nothing, the shoe thresholds, and the cards a hand renders. |
| `CardsTests.swift` | Unit | Rank order, the stored card identity, a whole shoe from one seed, and the ace that demotes itself out of a bust. |
| `ChipsTests.swift` | Unit | The claim, the streak payout, the stacking cooldown and its floor, the UTC day key, and the clamps at both ends. |
| `GamePerksTests.swift` | Unit | A host's configuration: what an empty one does, what configuration order means, the id shapes accepted and refused, and every refusal with the setting it names. |
| `GameRNGTests.swift` | Unit | The ported generator, value for value against the original, the shuffle, and the weighted pick that never lands on a zero. |
| `GameTypesTests.swift` | Unit | The values the games are made of, the round trips, and the two vocabulary promises: chips are chips, and nothing offers to convert them. |
| `HighLowTests.swift` | Unit | The streak, the push, the payout sized after the streak moves, and what a stale click does. |
| `ShinyDrawOrderTests.swift` | Unit | The five forage stages and the draw each one spends. The suite that fails if somebody tidies `Shiny.forage` up. |
| `ShinyTests.swift` | Unit | The pouch, the chips a find pays, the cooldown boundary, the nest ladder, and the card. |
| `GameFixtures.swift` | Fixture | A worked example of a host's configuration: four perks that between them exercise every perk field. |

## Requirement Coverage

### REQ-games-001, chips are a score

- `GameTypesTests.swift`: "Nothing anywhere in the engine offers to turn chips
  into anything else"; "The only thing an action can move is a number of
  chips"; "Every game names its chips chips, and none of them names them a
  nest".
- `ChipsTests.swift`: "A player can lose a hand but can never owe".

### REQ-games-002, one seed deals one table

- `GameRNGTests.swift`: "The same seed deals the same stream, value for
  value"; "Every draw lands in [0, 1) and two seeds do not agree"; "A bounded
  draw and a forked seed follow the same stream"; "An impossible bound still
  spends its draw, so the stream stays in step"; "A stored generator picks the
  stream up exactly where it stopped"; "A shuffle is a permutation, and the
  same seed permutes it the same way"; "A weighted pick costs exactly one
  draw".
- `BlackjackTests.swift`: "The same seed deals the same hand, every time".
- `ShinyDrawOrderTests.swift`: "One seed and one configuration produce one
  sequence, every time".
- `HighLowTests.swift`: "Nothing here reads a clock, so the hour never changes
  the cards".
- `CardsTests.swift`: "A shoe is whole decks with unique cards, and one seed
  deals one shoe".

### REQ-games-003, the five forage stages

- `ShinyDrawOrderTests.swift`: "With no perks configured a forage spends
  exactly one draw (ADOPT-3)"; "Configuring perks changes nothing for somebody
  who holds none of them"; "Holding a collection nobody wrote a perk for spends
  no extra draw"; "A reroll that lands costs the coin and the second roll"; "A
  reroll that misses still costs the coin"; "A find the reroll does not cover
  costs no coin at all"; "A perk with no reroll spends no coin however poor the
  find"; "A free find goes in the pouch, pays nothing, and spends no draw"; "An
  extra find fills the pouch and pays nothing for itself"; "An extra find that
  misses still costs its coin"; "Every stage firing at once spends five draws
  in one fixed order"; "A perk that is only a daily bonus never touches the
  loot stream".

### REQ-games-004, the perks are the host's

- `GamePerksTests.swift`: "A server that owns no collections has a perfectly
  valid configuration"; "A perk that says nothing does nothing"; "Only the
  collections somebody holds earn them anything"; "Perks apply in the order
  they were written down, not in holdings order"; "The base loot table leaves
  the locked kind unreachable"; "Adjustments apply in order, so a multiply and
  an add mean one thing"; "Only a set can unlock a kind sitting at zero, and
  two holders do not stack it".
- `ShinyDrawOrderTests.swift`: "The host's order decides the sequence, so
  reordering perks is a real change"; "A locked kind turns up once a collection
  unlocks it".
- `ShinyTests.swift`: "The locked kind never turns up for somebody with no
  collections"; "A configuration that zeroes the whole table still does not
  unlock the rare one".
- `GameTypesTests.swift`: "Holding nothing and having linked nothing is a valid
  way to play"; "Holdings name collections by the host's own ids"; "A context
  with nothing said about perks has none, which is fine".

### REQ-games-005, a bad configuration refuses at construction

- `GamePerksTests.swift`: "Two perks claiming one collection is refused, naming
  the id"; "A perk with no id could never match anything, so it is refused";
  "An id with whitespace round it is refused, not quietly trimmed or kept"; "A
  bonus that takes chips away is refused rather than paid"; "A nonsensical
  cooldown factor is refused, naming the collection"; "A nonsensical loot
  weight is refused, naming the kind"; "A chance outside nought to one is
  refused, naming the setting"; "A reroll nothing can trigger is a typo, so it
  is refused"; "Every refusal says which collection and which setting to fix".

### REQ-games-005.a, an id that could never match is refused

- `GamePerksTests.swift`: "An id the configuration would have normalised is
  refused, not left to never fire", which walks the shapes an operator actually
  types: a display name, a capitalised name, a hyphen, a full stop and a hash;
  "Every shape a normalised id can take is accepted, so nobody correct is
  refused", which walks lowercase words, digits, underscores at both ends and
  accented and non-Latin ids, because the normaliser these come from keeps any
  letter and an ASCII-only rule would refuse a server that configured itself
  correctly.

### REQ-games-006, chips move once, and a refusal costs nothing

- `BlackjackTests.swift`: "A bet under the minimum is refused and costs nothing
  at all"; "A bet bigger than the pile is refused and says so"; "Betting
  everything is allowed"; "Dealing on a hand already in play costs nothing and says why";
  "The deal takes the stake and puts two cards on each side"; "A hit draws one
  card, names it, and moves no chips"; "Hitting into a bust settles for nothing
  and never debits twice"; "Hitting twice into a bust still moves no chips";
  "Hitting a hand that is over costs nothing
  and says why"; "Standing on the better total
  returns the stake and the win"; "Standing under the dealer pays nothing
  beyond the stake already taken"; "Standing before a bet costs nothing and says why";
  "Doubling stakes a second bet, takes one card, and settles"; "Doubling into a
  bust loses only the extra stake"; "A doubled push returns both halves of the
  stake"; "A double that cannot be taken says why instead of looking dead"; "A
  hand cannot be doubled twice"; "The next hand keeps the cards that are left";
  "Asking for the next hand mid-hand costs nothing and says why"; "No press
  answers with the card that was pressed, however stale it is".
- `HighLowTests.swift`: "A click from a card that has moved on changes
  nothing"; "Drawing shows the top card, records the seed, and moves no chips".

### REQ-games-007, the settle precedence

- `BlackjackTests.swift`: "A bust loses even when the dealer would have busted
  too"; "The dealer's natural beats a drawn twenty-one"; "A drawn twenty-one is
  not a natural and pays even, not three to two"; "Two naturals push rather
  than one of them winning"; "A natural settles on the deal and pays three to
  two"; "The dealer's natural takes the stake on the deal"; "Two naturals push
  and the stake comes straight back"; "A three to two return keeps the odd half
  chip out of the payout"; "An odd stake floors the half chip out of a three to
  two payout"; "The dealer hits under seventeen and stands the moment it gets
  there"; "A dealer already on seventeen or better draws nothing"; "A dealer
  bust pays even money".
- `CardsTests.swift`: "An ace is eleven until it would bust the hand"; "Only
  two cards make a natural; a drawn 21 is a 21"; "Court cards are worth ten and
  the ace opens at eleven"; "An ace beats a king, and the compare is the gap
  between them".

### REQ-games-008, nothing traps and nothing owes

- `ChipsTests.swift`: "An absurd bonus gives an absurd claim rather than a dead
  process"; "A wait too big to hold clamps to the longest, never to the
  shortest"; "A player can lose a hand but can never owe"; "An absurd win or
  loss clamps rather than taking the table down".
- `BlackjackTests.swift`: "A stake nothing capped pays out instead of taking
  the process down"; "A hand dealt for everything a saturated pile holds still
  settles"; "Doubling a stake at the ceiling clamps rather than trapping".

### REQ-games-009, the claim and the cooldown

- `ChipsTests.swift`: "The claim rolls over at midnight UTC wherever the
  process is running"; "Somebody who holds nothing can still claim tomorrow";
  "Every collection held adds its own bonus to the claim"; "Holding a
  collection nobody configured a perk for changes nothing"; "Collections
  shorten the wait between forages, and they stack"; "The wait is floored at
  each step, not rounded once at the end"; "No arrangement of collections gets
  a forage under the floor"; "A perk that says nothing about the wait leaves it
  alone"; "A run of wins pays a quarter more each time and then stops
  climbing".
- `ShinyTests.swift`: "A forage too soon is refused, and only the line under it
  changes"; "Part of a second still reads as a second to wait"; "On the
  boundary the forage goes ahead"; "Somebody who has never foraged is ready,
  and a zero wait never blocks"; "A forage pays the chips of what it found and
  stamps the clock"; "A run of forages pays only for the rare finds".

### REQ-games-010, the nest ladder is bought with junk

- `ShinyTests.swift`: "Each rung of the nest ladder costs more junk than the
  last"; "An upgrade with too little junk changes nothing and says what is
  missing"; "A shortage is named with a plural somebody would actually write";
  "An upgrade burns its ingredients and raises the nest"; "The ladder runs to
  the top and then refuses to rise"; "Raising the nest never moves a chip in
  either direction"; "Foraging still works at the top of the ladder"; "A new
  pouch is empty, at nest one, and ready to forage"; "Common junk pays no
  chips; only the rarer finds do".

### REQ-games-011, the cards are data and quote the real numbers

- `BlackjackTests.swift`: "The betting card shows the stakes and greys the ones
  out of reach"; "A refused bet is shown on the card rather than thrown away";
  "Too few chips for the smallest hand gets the way back, not the rules"; "A
  live hand hides the hole card in the text and in the deck codes alike"; "A
  settled hand turns the hole card over everywhere at once"; "The stakes a card
  offers are the stakes the game deals for"; "A hand survives a round trip
  through storage".
- `HighLowTests.swift`: "The idle and open cards carry the copy, the colours
  and the button ids"; "The settled card names the draw and the verdict"; "A
  card shows only the picture it was handed"; "A table survives a round trip
  through storage".
- `ShinyTests.swift`: "An empty pouch draws a card with the forage button
  live"; "A cooling pouch greys the button and shows the wait"; "The pouch line
  lists the kinds in table order"; "A card carries the player's own picture and
  nobody else's"; "A pouch survives the round trip a stored player goes
  through".
- `ChipsTests.swift`: "The table constants are the ones the games actually play
  by".
- `GameTypesTests.swift`: "A card fills in the parts nobody asked for";
  "Holdings survive a round trip through storage".

### REQ-games-012, Foundation and nothing else

- `Package.swift` and source review: the target declares no dependency, and the
  module imports Foundation alone.
- The whole `GamesTests` suite: every case runs offline, with a pinned clock
  and a pinned seed, and none of them opens a socket, reads an environment
  variable or touches a file.

## Manual Testing

- [ ] Deal a hundred hands from one seed, twice, and confirm the two runs are
      identical card for card and chip for chip.
- [ ] Configure a perk, forage with it and without it from the same seed, and
      confirm the player who holds nothing spends exactly one draw.
- [ ] Read `hi/play.md` and confirm each criterion is either cited by a
      requirement here or named as a gap in `tasks.md`.
- [ ] Read every member-visible string in the module and confirm none of them
      names a collection, a token or a project this host did not configure.
- [ ] Configure one collection id from the same variable the rest of the
      product reads, in the shape an operator would type it, and confirm the
      process refuses at startup rather than starting with a perk that never
      fires.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| A bet under the minimum, or over the pile | The table comes back with a line saying so. No chips, no draws, no cards. |
| A hit, stand or deal from a card that has moved on | Only `message` changes, to the phase the table is in. No chips, and the generator has not advanced. |
| A double after a hit, twice, or with too few chips | Refused with the reason on the message, and no card drawn. |
| A hand that busts | Settles at `payout` zero with a chip delta of zero. The stake left on the deal. |
| Two naturals | Push, and the stake comes straight back. |
| A drawn 21 against a dealer's natural | The dealer's natural wins. A drawn 21 is not a natural. |
| An odd stake paying 3:2 | The half chip is floored out, the way integer division does it. |
| A stake at `Int.max` | Every payout leg clamps rather than trapping. |
| A shoe at the refill threshold, and one card deeper | Replaced at the threshold, kept one card deeper. Both are pinned, because the refill spends draws. |
| An empty shoe | `Cards.draw` answers nil. The JavaScript original threw. |
| `Cards.makeShoe(decks: 0)` | An empty shoe, and no draw spent. |
| A forage inside the cooldown | Refused. Only `lastBonus` changes, and the wait is rounded up to whole seconds. |
| A forage exactly on the cooldown boundary | Goes ahead. |
| A player who has never foraged | Ready, whatever the clock says. |
| Every perk stage firing at once | Five draws, in the order the find, the reroll coin, the reroll, the extra coin, the extra. |
| A reroll coin that misses | Still spent. The stream must not depend on the outcome. |
| A free find | Spends no draw at all, and pays no chips. |
| A player holding nothing, with perks configured | One draw, and the same find as a host with no perks configured. |
| A weight table with nothing positive | The first index. A locked kind at the end is never reached. |
| A loot weight adjustment that unlocks a kind at zero | Only `set` can do it, and two holders of the same collection do not stack it. |
| A cooldown factor product that overflows a `Double` | The longest wait, never the shortest. |
| Six generous cooldown factors | The floor at `Chips.minimumForageCooldown`, whatever they multiply out to. |
| A daily bonus large enough to overflow | Clamped at `Int.max`, and the process stays up. |
| A chip delta larger than the pile | The total floors at zero. Nobody owes. |
| An upgrade at the top of the ladder | The same pouch and a note. Foraging still works. |
| A padded or duplicated collection id | Refused at construction, naming the id. |
| A collection id in any shape but lowercase letters, digits and underscores | Refused at construction, naming the id and the shape. |
| An accented or non-Latin id in normalised form | Accepted. It is what a normaliser produces, and refusing it would refuse a correct configuration. |
