---
spec: games.spec.md
---

## User Stories

- As a member, I want something to do in the server that costs me nothing real,
  and that nobody can mistake for money, so that a bad hand is a bad hand and
  not a loss (PLAY-1, PLAY-1.a).
- As a member who has run out of chips, I want the game itself to tell me what
  is still free, so that running out is a pause rather than the end (PLAY-8).
- As somebody running this for my own community, I want what holding one of my
  collections is worth at the tables to be something I write down, and I want
  the games to play perfectly well when I write nothing down at all (ADOPT-1.b,
  ADOPT-3, ADOPT-3.a).
- As somebody running this, I want to be told I have set the perks up wrongly
  when the process starts, not when a member's forage behaves oddly three weeks
  later (ADOPT-2).
- As somebody running this, I want a busy evening at the card table to cost me
  nothing: no chain request, no token, no signing key anywhere near it
  (PLAY-11).
- As a maintainer, I want a stored table to replay card for card from its seed,
  so that a rule is something a test pins rather than something a reviewer
  hopes (BUILD-2).

## Acceptance Criteria

### REQ-games-001

Chips SHALL be a score. The only value a reducer may move SHALL be
`ReduceResult.chipDelta`, an `Int`, there SHALL be no conversion in either
direction, and no member-visible string SHALL offer one.

- Covered by `GameTypesTests.swift` and `ChipsTests.swift` (PLAY-1, PLAY-1.a).

### REQ-games-002

One seed, one configuration and one starting table SHALL always produce the
same cards and the same finds, and the number of draws an action spends SHALL
be asserted directly rather than inferred from what the action found.

- Covered by `GameRNGTests.swift`, `ShinyDrawOrderTests.swift`,
  `BlackjackTests.swift` and `HighLowTests.swift` (BUILD-2).

### REQ-games-003

`Shiny.forage` SHALL spend its draws in five fixed stages in one order, the
order SHALL NOT vary with the host's configuration or the player's holdings, a
perk coin SHALL be spent whether or not it lands, and a player holding nothing
SHALL spend exactly one draw.

- Covered by `ShinyDrawOrderTests.swift` (ADOPT-3, ADOPT-3.a).

### REQ-games-004

What a collection is worth SHALL be configuration the host writes down, keyed
by the host's own collection ids; perks SHALL apply in configuration order
rather than holdings order; and a host who configures none SHALL get a game
that plays exactly as it does for somebody who holds nothing.

- Covered by `GamePerksTests.swift`, `GameTypesTests.swift` and
  `ShinyTests.swift` (ADOPT-1.b, ADOPT-1.c, ADOPT-3.a, ADOPT-6.a, ADOPT-6.b).

### REQ-games-005

A perk configuration that is blank, padded, duplicated, negative, not a number,
outside `0...1`, or triggered by nothing SHALL be refused by `GamePerks.init`,
and the refusal SHALL name the collection and the setting to change.

- Covered by `GamePerksTests.swift` (ADOPT-2).

### REQ-games-005.a

A collection id SHALL be lowercase with nothing in it but letters, digits and
underscores, which is the shape the operator configuration these ids come from
produces. `GamePerks.init` SHALL refuse any other shape, naming the id and the
shape required, because ids are matched exactly and a perk whose id is spelled
differently from the holdings it is compared against fires for nobody and
reports nothing. The shape SHALL be checked rather than applied: this module
depends on nothing, and a copied transform would be a second definition free to
drift.

- Covered by `GamePerksTests.swift` (ADOPT-1.b, ADOPT-2).

### REQ-games-006

Chips SHALL move once per hand: `deal` takes the stake, `hit` moves nothing,
`stand` returns the payout and `double` takes the extra and returns the payout.
An action arriving in the wrong phase, and an action refused for any reason,
SHALL move no chips and spend no draw, and SHALL return the state it was handed
with at most the `message` line replaced. No refusal SHALL return the state
exactly as it arrived, because a card re-rendered unchanged is what a button
that does not work looks like.

- Covered by `BlackjackTests.swift` and `HighLowTests.swift` (PLAY-1).

### REQ-games-007

The settle SHALL judge a hand in one fixed precedence: the player busting, then
two naturals pushing, then the player's natural at 3:2, then the dealer's
natural, then a dealer bust, then totals. A natural SHALL be exactly two cards
totalling 21, and an ace SHALL count eleven until it would bust the hand.

- Covered by `BlackjackTests.swift` and `CardsTests.swift`.

### REQ-games-008

Every chip and cooldown calculation SHALL saturate rather than trap, a chip
total SHALL floor at zero, and a wait too large to hold SHALL clamp to the
longest wait rather than to the shortest.

- Covered by `ChipsTests.swift` and `BlackjackTests.swift`.

### REQ-games-009

The daily claim SHALL roll over on a Gregorian UTC day key whatever the process
timezone, SHALL pay at least the base to somebody holding nothing, and SHALL
add each held collection's bonus. The forage wait SHALL be shortened by held
collections in configuration order and SHALL never fall below
`Chips.minimumForageCooldown`; a forage inside it SHALL be refused rather than
queued.

- Covered by `ChipsTests.swift` and `ShinyTests.swift` (PLAY-8, ADOPT-3).

### REQ-games-010

The nest ladder SHALL be bought with junk and never with chips, an upgrade
SHALL burn its ingredients, a short pouch SHALL be told which ingredient is
missing, and the ladder SHALL stop at `Shiny.maxNestLevel` while foraging keeps
working.

- Covered by `ShinyTests.swift`.

### REQ-games-011

A card SHALL be plain data with no chat client's types in it, SHALL show the
line the last action wrote rather than discarding it, SHALL quote the constants
the games actually play by, and SHALL give somebody who cannot cover the
smallest hand the way back rather than the rules of a game they cannot start.
Every stored table SHALL survive a round trip through `Codable`.

- Covered by `BlackjackTests.swift`, `HighLowTests.swift`, `ShinyTests.swift`,
  `ChipsTests.swift` and `GameTypesTests.swift` (LEARN-5, LEARN-6, PLAY-8).

### REQ-games-012

The module SHALL depend on Foundation alone, SHALL be its own library product,
SHALL reach no network, chain, database, clock or global generator, and its
whole test suite SHALL run offline with no credentials of any kind.

- Covered by `Package.swift`, the whole `GamesTests` suite and source review
  (PLAY-9, PLAY-11, BUILD-2, BUILD-2.a).

## Constraints

- Swift 6 with strict concurrency enabled. Every type here is `Sendable`.
- Platforms: macOS 11, iOS 15, tvOS 15, watchOS 8, visionOS 1 and up.
- No force unwrap, no `try!`, no `as!`.
- No clock reads and no global randomness inside the module. `now` and the
  generator are parameters on `GameContext`.
- Floating point is confined to the generator, the loot weights, the perk
  probabilities, the streak multiplier and the `TimeInterval` cooldowns. All of
  those are a score, a chance or a wait rather than money, and every one of
  them clamps rather than traps. Nothing here touches an asset amount.
- The declaration order of `Rank`, `Suit` and `ShinyKind`, and the draw order
  of every reducer, are a compatibility surface: changing either re-deals every
  stored seed.

## Out of Scope

- Sending, signing, converting or pricing anything. There is no path from a
  game to a wallet in either direction, and a game result never changes a
  payout.
- Storing a player, a table or a pouch. The host stores what a reducer returns.
- Deciding who may press a button, and which channel a card goes in. The module
  hands back one player's table; ownership and placement are the host's
  (PLAY-2, PLAY-5, PLAY-7).
- Announcing a hand worth seeing to the room (PLAY-6).
- Reading a chain for what somebody holds. Holdings arrive already read.
