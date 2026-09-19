---
spec: games.spec.md
---

## Key Decisions

- The draw order is the game, not an implementation detail. A coin is spent
  whenever its perk is eligible, whether or not the outcome is used, and
  `GameRNG.int(below:)` spends a draw even for a bound it cannot honour.
  Skipping a draw because its result turned out to be unused consumes the
  stream differently, and every table dealt after it diverges from the seed it
  claims to be replaying. The tests count draws as well as outcomes for exactly
  this reason: a find that happens to be right while the count is wrong is a
  delayed failure, not a pass.
- Perks apply in the host's configuration order and never in the player's
  holdings order. Holdings are a `Set`, and a `Set`'s iteration order is not
  something a replay can depend on. `GamePerks.active(for:)` is the single
  place that decides the sequence, so there is one thing to read when a replay
  disagrees with itself.
- Making perks configurable at all is what threatened replay in the first
  place, and this is the subtle part. A draw that happens only when some perk
  is present makes the stream a function of the configuration. Fixing the five
  stages means a host with no perks gets exactly the stream a player with no
  collections always got, and adding a perk only ever adds draws for the people
  who hold that collection.
- The generator is a literal port of the JavaScript mulberry32, wrapping
  arithmetic and all, rather than anything from the standard library. A seed
  has to deal the same shoe wherever it is replayed, so `&+`, `&*` and the
  divide by 2^32 reproduce `|0`, `Math.imul` and `>>>` exactly. The test
  compares against the raw 32-bit values bit for bit rather than within a
  tolerance, because both sides of that divide are exact in a `Double`.
- Declaration order is a compatibility surface. `Rank`, `Suit` and `ShinyKind`
  are walked by `allCases` to build the deck the shuffle permutes and the
  weight table the picker reads positionally. Reordering a case would re-deal
  every stored seed and every saved table would come back different.
- `GameShuffle.pickIndex` never falls out of its walk onto a zero weight. A
  table that never drives the remainder negative answers the last index
  carrying a positive weight rather than the last index outright, because the
  last index is exactly where a locked kind sits: `ShinyKind.rune` is at weight
  zero until one of the host's collections unlocks it, and "never" has to mean
  never. With no positive weight anywhere it answers the first index, which is
  the commonest thing in every table this package deals rather than the rarest.
- The chips floor at zero, the daily claim saturates and the payout legs
  saturate, all for the same stated reason: a total that traps is a table
  nobody can play. Nothing caps a stake, and a host can configure a daily bonus
  that leaves a player at the ceiling, so the function that decides the return
  is exactly where an absurd stake must not take the process down.
- The order of the two guards in `Chips.floorToInt` is the whole point and is
  not tidy-up-able. A cooldown product that overflowed a `Double` is an
  enormous wait, not a missing one, so infinity clamps to the top with every
  other huge number. Sending it to zero instead handed the host who asked for
  the longest wait the shortest one: the eight second floor.
- The forage wait is floored to whole milliseconds at every step rather than
  once at the end. The two give different answers, and the stepwise one is what
  the original played by. `Chips.minimumForageCooldown` is then an absolute
  floor rather than a suggestion, because without it a host who configures six
  generous collections has built a button to hold down.
- The daily claim's day key is pinned to a Gregorian UTC calendar rather than
  the process locale or timezone. The claim has to roll over at the same
  instant for every player, and a container restarted in another zone must not
  hand out a second daily.
- `BlackjackState.payout` is the whole return of the hand, stake included,
  never the net. The stake was taken on the deal, and netting it twice is the
  bug this shape exists to stop. The four deltas are stated twice, in the type
  and in `Blackjack`'s own documentation, because a caller that nets a payout
  against a stake again pays the hand twice.
- The settle precedence is a rule, not a tidy-up: the player busting beats
  everything, then two naturals push, then the player's natural pays 3:2, then
  the dealer's natural collects, then a dealer bust pays even, and only then
  are totals compared. Judging a dealer bust before a natural would pay hands
  that lost. `settleWith` is `internal` rather than `private` so the payout
  table can be asserted directly, because two naturals pushing and a dealer
  natural beating a drawn 21 are cases a seed sweep cannot be relied on to
  produce and both are real payout bugs.
- Both card renderers threw `message` away and hardcoded their own line, so
  every refusal the reducers wrote was written and never shown. A Double that
  could not be taken, a bet under the minimum and a bet the player could not
  cover all looked like a dead button. The fix was in two places: the cards now
  show the line, and `Blackjack.double` writes one instead of returning the
  state untouched, because returning it untouched re-renders an identical card.
- The phase is the gate, not the disabled button. A chat client will happily
  deliver a click from a card that has since moved on, so every reducer checks
  the phase it requires. `Shiny.legalActions` offers "forage" even while the
  pouch is cooling for the same reason: the reducer enforces the cooldown.
- `GamePerks.empty` is named `empty` and not `none`. A static member called
  `none` on a struct collides with `Optional.none` at a comparison site, so
  `perks == .none` compiles, resolves to the optional and is always false. That
  shipped once in this project's history, as four always-false comparisons the
  compiler warned about every time and nobody read.
- A padded collection id is refused rather than trimmed, and a duplicate id is
  refused rather than merged or last-wins. Trimming guesses which of two
  spellings the rest of the host's configuration uses, and merging guesses
  which of two half-written perks they meant. Validation happens in the form
  the id is stored and matched in, because checking a trimmed copy while
  keeping the raw one let a padded id through as structurally valid and unable
  to match anything.
- A collection id has to arrive normalised: lowercase, and letters, digits and
  underscores only. These ids come from the same operator configuration the
  rest of the product reads, and that configuration normalises a name it is
  given to exactly that shape before anything matches on it. A host who reads
  one variable and configures both sides from it would otherwise hand a perk
  `Founders Pass` while every holding says `founders_pass`, and that perk is
  non-empty, unpadded and unique, so nothing else here objects and it then
  fires for nobody, forever, silently. The shape is checked rather than
  applied, and the check is written from the id itself rather than borrowed:
  this module depends on nothing, and a copied transform would be a second
  definition free to drift from the one that actually ran. The alphabet is
  Unicode's, not ASCII's, because a normaliser lowercases a name and keeps
  whatever is a letter in it, so `café` is a correct id and refusing it would
  refuse a correctly configured server to buy a rule that only looked stricter.
  Each character is judged by its first scalar, which is what `isLetter` and
  `isNumber` already do, and which is also what keeps a combining mark landing
  straight after a separator from reading as punctuation.
- Every refusal in `Blackjack` writes a line, including the wrong-phase ones
  that used to return the state exactly as it arrived. That is the Double bug
  again: a duplicate tap, or a tap on a card the table has moved on from,
  re-rendered a card nothing had changed on, which is indistinguishable from a
  button that does not work. The cost is real and is accepted rather than
  hidden: on a settled hand the refusal replaces the verdict line until the
  next deal, and the hands, the totals and the colour are what still say how it
  went. `HighLow` is left alone, because its table carries no line and giving
  it one changes the shape a host stores rather than the behaviour of a
  reducer.
- `GameHoldings` carries the host's collection ids rather than the four
  booleans the original welded into the type. Two named collections meant a
  host with three could not describe theirs and a host with none was carrying
  somebody else's nouns around. For the same reason `CollectionPerk.name`
  defaults to the id: any default this package supplied would be somebody
  else's word in somebody else's server.
- The channel-wide variant of higher or lower, where the whole room voted on
  one hand, was removed rather than kept behind an option. A table the room can
  play is not your table. What the room gets is the result.
- Nothing in a game reads a chain. Holdings, including the picture on a card,
  arrive from whatever cache the host already keeps, so a busy evening of
  blackjack cannot be the reason a role sweep runs out of request budget in the
  morning. This is a property of the package graph, not of a review: the module
  imports Foundation and has no dependency through which it could acquire the
  ability.
- The currency is called chips in every string a member reads. The word it
  replaces meant the currency, the collectible ladder, the profile card and a
  button all at once, and a sentence using it could not be read. "Nest" now
  names the Shiny ladder and nothing else, and a test asserts the vocabulary
  rather than trusting it.
- `ShinyMeta.labelPlural` is stored rather than derived because the original
  appended an `s` to every label and told members they needed "3 glasss".
  `ShinyState.inventory` is keyed by raw value rather than by the enum so the
  pouch encodes to a plain JSON object and a kind added later reads back as
  absent instead of failing the decode, and `Shiny.empty` writes every kind in
  at zero so a fresh pouch and a spent one have the same shape.
- The two shoe refill thresholds in `Blackjack` are the original's and both are
  kept, even though the mid-draw one cannot fire while every caller takes one
  card at a time. Replacing a shoe spends draws, so a table replayed from a
  seed only deals the same cards if it refills at the same points. Removing the
  unreachable branch would be safe today and would change the deal the moment
  somebody draws two cards at once.

## Files to Read First

- `Sources/Games/Shiny.swift`: the five forage stages, in the order they have
  to happen in, with the reasons in the doc comment.
- `Sources/Games/GameRNG.swift`: the ported generator and the weighted pick,
  including what happens when no weight is positive.
- `Sources/Games/GamePerks.swift`: everything one collection can be worth, and
  every refusal that stops a host finding out later.
- `Sources/Games/Blackjack.swift`: the settle precedence and where the chips
  actually move.
- `Sources/Games/Chips.swift`: the economy constants a rules page quotes, and
  the two clamps.
- `Tests/GamesTests/ShinyDrawOrderTests.swift`: the tests that fail if somebody
  tidies the forage up.
- `hi/play.md`: what the games are for, and the one thing that would ruin them.

## Current Status

Implemented and covered by 158 tests in 9 suites, all offline. `Games` is one
of three library targets in the package, beside `Reserve` and `Gating`. There
is no bot here yet: no gateway, no commands, no storage and no chain access, so
nothing in this module is wired to anything a member can press.

## Notes

- These games are a port of a private TypeScript gamebot that ran a live
  community for months. It is not named here, and nothing in this repository
  names it. Most of the decisions above are that bot's production scars, and
  the numbers in `Tests/GamesTests/GameFixtures.swift` are the ones it
  hardcoded for its own two collections. Reproducing them
  through configuration rather than through hardcoded collections is the whole
  claim this port makes, which is why the fixtures are shaped as a worked
  example of a host's configuration rather than as anything this package ships.
- The original's treasury commands were deliberately left behind. A money path with
  caps and an audit log belongs to whatever eventually drives these games, and
  a game that could reach one would stop being a score.
- `HighLowState.judgedCall` is written and never read, here or in the engine
  this came from. It is kept because telling "called and lost" from "settled
  with nothing called" after the fact needs it, and nothing else can recover it
  once the table has moved on.
- `Chips.starting`, `GameHoldings.address` and the `link` button style are
  exported for the host and used by nothing in this module. They are part of
  the surface on purpose, not leftovers.
