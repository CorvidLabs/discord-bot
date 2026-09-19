---
module: games
version: 1
status: active
files:
  - Sources/Games/Blackjack.swift
  - Sources/Games/Cards.swift
  - Sources/Games/Chips.swift
  - Sources/Games/GameConfigurationError.swift
  - Sources/Games/GameContext.swift
  - Sources/Games/GameHoldings.swift
  - Sources/Games/GameMessage.swift
  - Sources/Games/GamePerks.swift
  - Sources/Games/GamePlayer.swift
  - Sources/Games/GameRNG.swift
  - Sources/Games/HighLow.swift
  - Sources/Games/ReduceResult.swift
  - Sources/Games/Shiny.swift
db_tables: []
depends_on: []
---

# Games

## Purpose

Play three games for a score that cannot be cashed out: blackjack against the
dealer, higher or lower against the deck, and a foraging ladder built out of
junk. Each game is a set of pure reducers. A reducer takes the table as it
stands plus a `GameContext`, and answers with the next table, the one chip
movement it is allowed to ask for, and the card a member reads. The same
functions drive a button, a test and a replay from a seed.

Chips are a score. They are not a token, not an asset id, not a coin, and not a
balance of anything that can be sent. The only value that leaves a reducer is
`ReduceResult.chipDelta`, an `Int`, and the module imports Foundation and
nothing else, so there is no dependency through which a game could acquire the
ability to sign, send or convert (`PLAY-1.a`).

It reads no clock, reaches no global generator, reads no environment variable
and asks nothing of a chain. The wall clock, the player, the host's perk
configuration and the seeded generator all arrive as parameters on
`GameContext`, so a stored table replays card for card and every rule is pinned
by an offline test. What a player holds arrives as a set of the host's own
collection ids, already read from whatever cache the host keeps, so however much
anybody plays it costs no chain request (`PLAY-11`). Those ids are matched
exactly and arrive normalised, so `GamePerks.init` refuses a perk whose id is
not: a mismatch between the two spellings is a perk that fires for nobody and
says nothing about it. Rendering is data:
`GameMessage`, `GameField` and `GameButton` name no chat client's types, and
whatever drives the games maps them.

## Public API

Every exported symbol of the `Games` library target, in source order. A name
that several types share is described once, at its first declaration, and the
other meanings are named in the same line.

| Export | Description |
|--------|-------------|
| `BlackjackPhase` | Where a hand is in its life. The phase, not a greyed-out button, is what refuses a stale click. |
| `BlackjackOutcome` | How a settled hand finished. |
| `BlackjackState` | One blackjack table: the shoe, both hands, and what the last action decided. |
| `phase` | Which phase a table is in: betting, playing or settled here, idle, open or resolved on a higher-or-lower table. |
| `bet` | Chips staked on this hand. Doubling rewrites it to the doubled stake. |
| `shoe` | Cards left, drawn from the end. Refilled when it runs low. |
| `player` | The player's hand. On `GameContext`, the player taking the action. |
| `dealer` | The dealer's hand. |
| `hideHole` | Hide the dealer's second card while the hand is live. |
| `outcome` | Set once the hand settles. Nil while it is still being played. |
| `payout` | Whole chip return of the hand, stake included. Zero on a loss. On a higher-or-lower table, the chips the last settle paid. |
| `doubled` | The hand took its one extra card and stood. |
| `message` | The line a card shows for the last action, a refusal included. |
| `Blackjack` | Blackjack against the dealer, played in chips. Every entry point is a pure reducer. |
| `stakes` | The one-tap stakes on the betting card, smallest first. Public so a rules page quotes the stakes the game deals for. |
| `brokeRoute` | What to tell somebody whose chips will not cover the smallest hand. |
| `initial` | A fresh blackjack table: a shuffled single-deck shoe, no stake, nothing dealt. On a higher-or-lower table, an idle table with a whole deck waiting. |
| `deal` | Take the stake and deal two cards each, settling at once on a natural. |
| `hit` | Draw one card. Busting settles the hand; the stake is already gone either way. |
| `stand` | Turn the hole card over, play the dealer out, and settle. |
| `double` | Stake the bet again, take exactly one card, and stand. |
| `next` | Clear the blackjack table for another hand, keeping the cards that are left. On `HighLowState`, the card turned over at settle; on `GameRNG`, one draw in `[0, 1)`. |
| `legalActions` | Action names the table will accept right now, for a card or a handler to gate on. |
| `card` | The table as a card: pure data, mapped to a message by whatever drives it. |
| `init` | Memberwise initializer. Every state and value type here has one, so a host can rebuild a stored table without going through a reducer. |
| `betting` | Waiting for a bet. |
| `playing` | The bet is down and the player is acting. |
| `settled` | The hand is over and its chip delta has been taken. |
| `win` | Beat the dealer on totals, or the dealer busted. On a higher-or-lower table, the call was right. |
| `lose` | Lost on totals, or to the dealer's natural. On a higher-or-lower table, the call was wrong. |
| `push` | Equal totals; the stake comes back. On a higher-or-lower table, the cards tied. |
| `blackjack` | Natural twenty-one on the first two cards. |
| `bust` | Over twenty-one. |
| `Rank` | A French rank. Raw values are the face text a card shows, and the declaration order fixes the deck a seed is applied to. |
| `Suit` | A French suit. Raw values are the single lowercase letters used in card ids. |
| `pip` | The pip a card face is drawn with. Presentation only, kept apart from the stored raw letter. |
| `Card` | One card in a shoe. |
| `rank` | Face rank. |
| `suit` | Suit, as one of the four French suits. |
| `id` | Unique within a shoe: `"{deck}-{rank}{suit}"`. On `GamePlayer` and `CollectionPerk`, the host's own id, carried and compared but never parsed; on `GameButton`, the action id, empty for a link. |
| `label` | Short face for a card, for example `A` followed by the spade pip. On `ShinyMeta` and `GameButton`, the name a member reads. |
| `code` | The card as a lowercase deck code, for example `ks` or `10h`. |
| `Cards` | Deck building, drawing, and blackjack totals. Pure; randomness arrives as a `GameRNG`. |
| `deckSize` | Cards in one deck. A shoe is this times the deck count. |
| `faceDownCode` | The code a face-down card is drawn with. |
| `order` | Rank strength for a high-card compare: ace high at 14 down to two. |
| `compare` | Positive when the left rank beats the right, negative when it loses, zero on a tie. |
| `makeShoe` | A shuffled shoe of `decks * 52` cards. Built deck-major, then suit, then rank before the shuffle, so the starting order is part of the contract. |
| `draw` | The next card off the top of the shoe plus what is left, or nil when it is empty. |
| `pipValue` | Blackjack pip value with the ace high at 11. |
| `handValue` | Best total for a hand, and whether an ace is still worth 11 in it. |
| `isBlackjack` | A natural: exactly two cards totalling 21. A drawn-to 21 is not one. |
| `ace` | Eleven in a blackjack hand until it would bust, then one. |
| `two` | Rank two. |
| `three` | Rank three. |
| `four` | Rank four. |
| `five` | Rank five. |
| `six` | Rank six. |
| `seven` | Rank seven. |
| `eight` | Rank eight. |
| `nine` | Rank nine. |
| `ten` | Rank ten. |
| `jack` | Rank jack. Worth ten. |
| `queen` | Rank queen. Worth ten. |
| `king` | Rank king. Worth ten. |
| `spades` | Suit spades. |
| `hearts` | Suit hearts. |
| `diamonds` | Suit diamonds. |
| `clubs` | Suit clubs. |
| `Chips` | The chip economy: the starting pile, the daily claim, the streak payout and the forage cooldown. A score, never a currency. |
| `starting` | A new player's pile. Nothing in the module reads it; whatever creates a player does. |
| `minimumBet` | Smallest stake `Blackjack` will deal for. |
| `streakWinBase` | Chips a won call pays before the streak multiplier. |
| `streakSteps` | Quarter-steps the streak multiplier climbs before it flattens. |
| `baseDailyStipend` | Chips the daily claim pays before any collection bonus. |
| `defaultForageCooldown` | Seconds between forages with no collections held. |
| `minimumForageCooldown` | The absolute floor on the wait between forages, whatever perks stack. |
| `utcDay` | UTC `yyyy-MM-dd` key for the daily claim, on a fixed Gregorian UTC calendar rather than the process locale. |
| `dailyStipend` | Chips the daily claim pays: the base, plus each held collection's bonus. Saturating, and always at least one. |
| `streakPayout` | Chips a won call pays at the streak the win produced. |
| `forageCooldown` | Seconds a player waits between forages, after their collections shorten it. Never below the floor. |
| `applying` | A chip total after a delta, floored at zero and saturating at both ends. |
| `GameConfigurationError` | A perk configuration that refuses to exist, and why. Every case names the collection and the setting to fix. |
| `errorDescription` | The refusal written out for a person: what went wrong, and which setting to change. |
| `emptyCollectionId` | A perk with a blank collection id, which nothing could ever match. |
| `paddedCollectionId` | A collection id with whitespace around it. Refused rather than trimmed, because trimming guesses which spelling the rest of the configuration uses. |
| `unnormalizedCollectionId` | A collection id that is not lowercase letters, digits and underscores. Refused rather than normalised, because the ids arrive already normalised and an exactly matched id in any other shape fires for nobody. |
| `duplicateCollectionId` | Two perks claim the same collection id. Refused rather than merged or last-wins. |
| `negativeDailyBonus` | A daily bonus below zero, which would take chips away for holding something. |
| `invalidCooldownFactor` | A cooldown factor that is negative or not a number. |
| `invalidWeight` | A loot weight that is negative or not a number. |
| `invalidProbability` | A probability outside `0...1`, or not a number. |
| `emptyRerollTrigger` | A reroll with no kinds that trigger it, which spends no draw and does nothing, and is therefore always a typo. |
| `GameContext` | Everything impure a game needs, handed in from the outside: the clock, the player, the host's perks and the seeded stream. |
| `now` | Wall clock for this step. Injected, never read from the system. |
| `perks` | What holding one of the host's collections is worth. Carried rather than reached for as a global. |
| `rng` | Seeded generator, mutated as the game draws. |
| `activePerks` | The perks this player's holdings actually earn, in configuration order. |
| `GameHoldings` | Which of the host's collections a player holds, plus the account they were read from. Ids, not flags for two named collections. |
| `collectionIds` | Collection ids the player holds at least one of. |
| `address` | The account the ids were read from, empty when nothing is linked. Carried for a card to name; never parsed, validated or looked up here. |
| `pictureUrl` | A picture this player holds, for the corner of a card. Read from the host's cache, never from a chain. |
| `empty` | No collections and no account: the ordinary case, not a degraded one. Also `GamePerks.empty`, no perks configured at all, and `Shiny.empty(cooldown:)`, a fresh pouch at nest one. |
| `holds` | Whether the player holds anything from a collection id. |
| `GameButtonStyle` | The button styles a chat client is expected to understand. Plain cases, no client types. |
| `GameButton` | One button under a game card. |
| `style` | Which of the five button styles this button is drawn in. |
| `url` | Destination for a `link` button. Nil for every other style. |
| `disabled` | Greyed out and unclickable. |
| `GameField` | One field on a game card. |
| `name` | Field heading. On `CollectionPerk`, what a member reads when the perk fires; on `GamePlayer`, the display name on a card. |
| `value` | Field body. On `LootWeightOperation`, the number the operation carries; on `ShinyMeta`, nest points per item. |
| `inline` | Sit beside the previous field instead of below it. |
| `GameMessage` | A rendered game card, in a chat client's shape but with none of its types. |
| `title` | Card title. |
| `description` | Card body. |
| `fields` | Extra fields under the body. |
| `color` | Card colour as `0xRRGGBB`. |
| `buttons` | Buttons under the card. |
| `footer` | Small print under the card. |
| `thumbnailUrl` | Picture for the card's corner, as a plain url, so this module still names no client types. |
| `hand` | The dealt cards to draw, top row first, as deck codes, with `Cards.faceDownCode` for a hole card. |
| `primary` | The call to action. |
| `secondary` | A quieter alternative. |
| `success` | A positive action. |
| `danger` | A destructive or losing action. |
| `link` | Navigation. Carries a url and sends no interaction back. |
| `LootWeightAdjustment` | One change a collection makes to the loot table. |
| `kind` | The kind whose weight moves. |
| `operation` | How it moves: multiply, add or set. |
| `LootWeightOperation` | How a `LootWeightAdjustment` changes a weight. Only `set` can raise a kind off a base weight of zero, and only it ignores what an earlier perk did. |
| `PerkReroll` | A perk that rerolls a disappointing find. |
| `probability` | Chance in `0...1` that a poor find is rerolled once. On `PerkExtraFind`, the chance of a second find. |
| `kinds` | Finds poor enough to be worth rerolling. Anything else spends no draw at all. |
| `PerkExtraFind` | A perk that sometimes turns up a second find. The extra goes in the pouch and pays no chips: it is loot, not income. |
| `CollectionPerk` | What holding one of a host's collections is worth at the tables. Never required: every field has a do-nothing default. |
| `dailyBonusChips` | Chips added to the daily claim for holding one. |
| `forageCooldownFactor` | Multiplies the wait between forages. Factors stack; the floor does not move. |
| `weightAdjustments` | Changes to the loot table, applied in this order. |
| `reroll` | Rerolls a poor find. Nil for a collection that does not. |
| `freeFind` | A kind tucked into the pouch on every single forage, free, no draw spent. |
| `extraFind` | Sometimes turns up a second find. Nil for a collection that does not. |
| `GamePerks` | The host's whole perk configuration, in the order it was written down. The order is the contract. |
| `ordered` | Every configured perk, in configuration order. |
| `isEmpty` | Whether any perk is configured at all. |
| `active` | The perks these holdings earn, in configuration order rather than holdings order. |
| `perk` | The configured perk for a collection id, or nil. |
| `multiply` | Scale the weight so far. `0.6` makes a kind rarer. |
| `add` | Add to the weight so far. |
| `set` | Replace the weight so far, whatever it was. |
| `GamePlayer` | What a game reducer is allowed to read about the player at the table. Deliberately small. |
| `chips` | Chips the player holds right now: a score, not a balance of anything that can be sent. On `ShinyMeta`, the chips a forage pays for that find. |
| `holdings` | Collections the player holds, which is what sizes their perks. |
| `GameRNG` | Mulberry32, ported literally from the JavaScript engine these games came from. A value type; a draw mutates it in place. |
| `int` | A draw in `0..<upperBound`, floored. Always consumes one draw, even for an empty range, so a caller that guards its own bounds cannot knock the stream out of step. |
| `seed32` | A fresh 32-bit seed derived from one draw, for handing a sub-game its own stream. |
| `GameShuffle` | Seeded shuffling and weighted picks. Both take the generator `inout` so one stream deals a whole table. |
| `fisherYates` | Copy-shuffle, walking the index down from the end and swapping with `0...index`, in the original's direction and bound. |
| `pickIndex` | Index picked in proportion to the weights, consuming exactly one draw. A zero weight is never picked. |
| `HighLowCall` | Which way the player called the card about to be turned over. |
| `HighLowPhase` | Where a table is in its cycle: nothing dealt, a card up, or a call settled. |
| `HighLowResult` | How a settled call landed. |
| `HighLowState` | A higher-or-lower table: the shoe it deals from, the open call, and the last result. One player, and the shoe and seed travel with it. |
| `shown` | The up-card being called against. Nil until the first draw. |
| `streak` | Consecutive wins. Sizes the payout: a win increments, a push holds, a loss zeroes. |
| `called` | The call made on the open card. Nil until one is made. |
| `result` | How the last settle landed. Nil until a settle. |
| `judgedCall` | The call the settle judged. Written here and read by nothing in this module; carried for whatever renders a feed of finished hands. |
| `seed` | Seed drawn for this deal, printed on the card so a player can see the deal was not re-rolled under them. |
| `HighLow` | Higher or lower against the deck, played in chips. Costs nothing to play and pays on a win. |
| `open` | Turn the up-card over and take a call, from any phase. Also the phase in which a card is up and a call can be made. |
| `call` | Record the call and settle it, because there is nobody else to wait for. |
| `settle` | Draw against the up-card and pay the streak if the call was right. |
| `higher` | The next card is higher. |
| `lower` | The next card is lower. |
| `idle` | No call is open. |
| `resolved` | The call has been settled. |
| `ReduceResult` | The next state of a table plus the only chip movement it is allowed to ask for. |
| `state` | State after the action. On `GameRNG`, the 32-bit generator state, which advances by one step per draw. |
| `chipDelta` | Chips won (positive) or staked (negative). Zero when nothing moved. |
| `note` | One line for an audit trail or a card footer. |
| `ShinyKind` | The eight things a forage can come back with, cheapest first. The weight table is read positionally, so the declaration order is part of the seed contract. |
| `ShinyMeta` | What one kind of junk is worth: its face, its nest points, and its chip sprinkle. |
| `labelPlural` | Plural of the label, stored rather than derived, because appending an `s` to every label promised members "3 glasss". |
| `ShinyState` | One player's pouch: what they have found, how high the nest is, and when they may forage again. |
| `inventory` | Counts keyed by `ShinyKind.rawValue`, so the pouch encodes to a plain JSON object and a kind added later reads back as absent. |
| `nestLevel` | Nest height, 1 through `Shiny.maxNestLevel`. Multiplies the pouch score, and names the ladder and nothing else. |
| `lastForageAt` | When the last forage landed. Nil means they have never foraged. |
| `lastFind` | What the last forage turned up. Nil until the first find. |
| `lastBonus` | The line a card shows under the find: the perks that fired, or why a forage was refused. |
| `cooldown` | Seconds between forages, carried on the state so a perk can shorten it per player and a stored pouch still knows its own wait. |
| `count` | How many of a kind are in the pouch. A kind never found reads as zero. |
| `Shiny` | Shiny: forage junk, build a nest out of it. Every entry point is a pure reducer. |
| `meta` | Label, nest points, and chip sprinkle per kind. Chips start at beetle, so the bulk of every pouch pays none. |
| `nestCosts` | What each nest level above the first costs, in junk. The ladder is spent, not banked. |
| `maxNestLevel` | The top of the ladder. A nest here refuses to rise and drops the upgrade action. |
| `nestScore` | The pouch's worth: every item at its nest points, multiplied by the nest level. |
| `forage` | Forage once, in five fixed stages: roll a find, reroll it, pouch it, add free finds, add extra finds. Pays the chips of the kind it settled on and nothing else. |
| `upgrade` | Spend the next rung's ingredients to raise the nest. Never a chip movement in either direction. |
| `remainingCooldown` | Seconds until the next forage is legal. Zero once it is, and for somebody who has never foraged. |
| `baseWeight` | Base odds per kind, in `ShinyKind` order. The rune shard sits at zero, unreachable until one of the host's collections sets a weight for it. |
| `weights` | The odds a player actually forages on, after their perks adjust them, returned in `ShinyKind` order because the picker reads it positionally. |
| `twig` | The commonest find, and the first rung of the nest ladder. |
| `feather` | Common, worth a little more than a twig, and pays no chips. |
| `pebble` | Common, worth two nest points, and pays no chips. |
| `beetle` | The cheapest find that pays chips. |
| `glass` | Uncommon: eight nest points and four chips. |
| `silver` | Rare: fifteen nest points and ten chips. |
| `gold` | The rarest of the ordinary finds: forty nest points and twenty-five chips. |
| `rune` | Unreachable at its base weight of zero. A locked find, worth twenty-four nest points and twelve chips once a collection unlocks it. |

## Invariants

1. Chips are a score. The only value a reducer can move is
   `ReduceResult.chipDelta`, an `Int`, and nothing in the module can sign, send
   or convert. The module imports Foundation alone, so the property is held by
   the package graph rather than by a reviewer noticing (`PLAY-1.a`).
2. The module reads no clock and no global generator. `GameContext.now` is the
   wall clock for a step and `GameContext.rng` is the only source of
   randomness, so every figure in the test suite is pinned and a stored table
   resumes exactly where it stopped.
3. Nothing here reaches a network, a chain, a database or an environment
   variable. What a player holds arrives on `GameHoldings`, already read from
   whatever cache the host keeps, so no amount of play costs a chain request
   (`PLAY-11`).
4. The number of draws an action spends is part of the contract, not an
   implementation detail. A coin is spent whenever its perk is eligible,
   whether or not the outcome is used, and `GameRNG.int(below:)` spends a draw
   even for an empty range. Spending one fewer draw than a replay expects
   changes every card dealt afterwards.
5. `Shiny.forage` walks five stages in a fixed order, and the order does not
   change with which perks a host configured or which collections a player
   holds. A player who holds nothing, and a host who configured nothing, spend
   exactly one draw (`ADOPT-3`).
6. Perks apply in `GamePerks.ordered` order, never in holdings order.
   `GameHoldings.collectionIds` is a `Set`, and a `Set`'s iteration order is
   not something a replay can depend on.
7. The declaration order of `Rank`, `Suit` and `ShinyKind` is part of the seed
   contract. `Cards.makeShoe` walks `allCases` to build the deck the shuffle
   permutes, and the loot weight table is read positionally.
8. A refused action returns the state it was handed, with at most one line of
   text replaced. No chips move, no draws are spent, and nothing is queued: a
   bet under the minimum, a bet over the pile, a double that cannot be paid for
   and a forage inside the cooldown all cost nothing.
9. The phase is the gate, not the button. A chat client will deliver a click
   from a card that has since moved on, so every reducer checks the phase it
   requires and a greyed-out button is never the whole guard.
10. Blackjack accounting happens once per hand. `deal` returns `-bet` plus any
    immediate return on a natural, `hit` returns zero, `stand` returns the
    payout, and `double` returns `-extra + payout`. `BlackjackState.payout` is
    the whole return of the hand, stake included, never the net.
11. Arithmetic saturates rather than traps, and chip totals floor at zero. A
    host can configure a daily bonus that leaves a player at the ceiling, and a
    table that traps is a table nobody can play.
12. `Chips.minimumForageCooldown` is an absolute floor. No combination of
    collection cooldown factors gets a forage under it.
13. Rendering is data. `Blackjack.card`, `HighLow.card` and `Shiny.card` build
    a `GameMessage` out of plain strings and integers, take the context
    read-only, and draw no cards from the stream.
14. A member-visible string calls the currency chips. "Nest" names the Shiny
    ladder and nothing else.
15. `GamePerks.init` is the only validation gate, and it runs before a table
    exists. A `GamePerks` value in hand has unique, unpadded, non-empty ids in
    normalised form, non-negative bonuses and weights, finite factors, and
    probabilities inside `0...1` (`ADOPT-2`).
16. A collection id is lowercase, and letters, digits and underscores only.
    That is the shape the operator configuration these ids come from produces,
    and ids here are compared exactly, so any other shape is a perk that can
    never match a holding. The shape is checked and never applied: this module
    depends on nothing, and a transform copied in from elsewhere would be a
    second definition free to drift from the one that actually ran.

## Behavioral Examples

### Scenario: A forage with nothing configured spends exactly one draw

- **Given** a host who has configured no perks and a player who holds no
  collections
- **When** `Shiny.forage` is called on a pouch that is off cooldown
- **Then** the generator has advanced by exactly one draw, the find is the one
  the base weight table gives for that seed, and the chip delta is that find's
  chips and nothing else (`ADOPT-3`, `PLAY-1`)

### Scenario: Every perk stage firing at once spends five draws in one order

- **Given** a player holding collections that between them reroll a poor find,
  tuck in a free find and sometimes turn up an extra one
- **When** a forage rolls a kind the reroll covers, and both coins land
- **Then** the draws are spent in exactly this order: the find, the reroll
  coin, the rerolled find, the extra-find coin, the extra find, for five in
  total, with the free find costing none

### Scenario: A hand that busts is never debited twice

- **Given** a dealt hand whose stake was already taken by `deal`
- **When** `hit` draws the player past 21
- **Then** the hand settles as `bust` with `payout` zero and a chip delta of
  zero, because the stake left on the deal

### Scenario: Somebody too poor for the smallest hand is given the way back

- **Given** a player holding fewer chips than `Chips.minimumBet`
- **When** the betting card is rendered
- **Then** it says what they hold and what the smallest bet is, carries
  `Blackjack.brokeRoute` as its footer, and shows every stake button disabled
  rather than hiding them (`PLAY-8`, `LEARN-6`)

### Scenario: A click from a card that has moved on costs nothing

- **Given** a settled blackjack hand or a resolved higher-or-lower table
- **When** `hit`, `stand` or `call` arrives from the stale card
- **Then** no chips move and the generator has not advanced; a blackjack table
  comes back with only `message` replaced by the phase it is in, so a duplicate
  tap is answered rather than re-rendered unchanged

### Scenario: A perk id in the shape the operator typed is refused at the door

- **Given** a host whose collection is configured as `Founders Pass`, which the
  rest of the product normalises to `founders_pass` before it matches anything
- **When** that name is handed to `CollectionPerk(id:)` and the perks are built
- **Then** `GamePerks.init` throws `.unnormalizedCollectionId` naming the id and
  the shape required, rather than accepting a perk that would fire for nobody
  (`ADOPT-2`)

## Error Cases

Only one error is thrown in this module: a perk configuration that will not
validate. Everything a player can do wrong is refused by value, as the state
that went in plus a line saying why.

| Condition | Behavior |
|-----------|----------|
| A perk with a blank collection id | `GameConfigurationError.emptyCollectionId` from `GamePerks.init` |
| A collection id with whitespace around it | `.paddedCollectionId`, refused rather than trimmed |
| A collection id that is not lowercase letters, digits and underscores | `.unnormalizedCollectionId`, naming the id and the shape required |
| Two perks claiming one collection id | `.duplicateCollectionId`, refused rather than merged |
| A daily bonus below zero | `.negativeDailyBonus`, naming the collection and the value |
| A cooldown factor that is negative or not a number | `.invalidCooldownFactor` |
| A loot weight that is negative or not a number | `.invalidWeight`, naming the kind |
| A reroll or extra-find chance outside `0...1` | `.invalidProbability`, naming the setting |
| A reroll with no trigger kinds | `.emptyRerollTrigger` |
| A bet under `Chips.minimumBet`, or over the player's chips | The table comes back untouched with only `message` replaced. No chips, no draws |
| `deal` on a hand already in play, or already over | The table comes back with only `message` replaced by the phase it landed in. No chips, no draws |
| `hit` or `stand` on a settled or unbet hand | The same, with the phase on `message`. Chip delta zero |
| `double` in the wrong phase, after a hit, twice, or with too few chips | The table comes back with `message` naming the reason, no card drawn |
| `next` before the hand has settled | The same, with the phase on `message` |
| A forage inside the cooldown | The pouch comes back with only `lastBonus` replaced by the wait, rounded up to whole seconds. No chips, no draws |
| An upgrade at `Shiny.maxNestLevel`, or short of an ingredient | The same pouch plus a note naming the shortage, never a chip movement |
| `Cards.draw` on an empty shoe | Nil, rather than the throw the JavaScript original did |
| `GameShuffle.pickIndex` where nothing is positive | The first index, the commonest thing in every table this package deals |
| `GameShuffle.pickIndex` on empty weights | `0`; callers check first |
| A chip total that would overflow | Clamped at `Int.max` or at zero, never trapped |
| A cooldown factor product that overflows a `Double` | Clamped to the longest wait, never to the shortest |
| A `ShinyKind` with no `meta` entry | A fallback meta, so a kind added later cannot trap a card drawing itself |

## Dependencies

- Foundation, and nothing else. The module has no package dependencies and is
  its own library product, so a host that does not want a card table does not
  build one (`PLAY-9`).
- The host supplies `GameContext`: the wall clock, the `GamePlayer` with their
  chips and holdings, the validated `GamePerks`, and the seeded `GameRNG`. The
  chips on that player must already have every earlier `chipDelta` applied,
  because that is what `deal` and `double` check a stake against.
- The host stores the state a reducer returns. Nothing here persists anything;
  `BlackjackState`, `HighLowState`, `ShinyState`, `GameHoldings` and `GameRNG`
  are `Codable` so a table can be written out and read back.
- The host maps `GameMessage` onto its chat client. No client type is named
  here.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-18 | maintainers | Spec written for the shipped `Games` library target. |
| 2026-09-18 | maintainers | Perk ids must arrive normalised; `GamePerks.init` refuses any other shape. |
| 2026-09-18 | maintainers | Every blackjack refusal writes a line, so no press answers with the card that was pressed. |
