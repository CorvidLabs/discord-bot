---
module: gating
version: 1
status: active
files:
  - Sources/Gating/AdminAllowlist.swift
  - Sources/Gating/CollectionConfiguration.swift
  - Sources/Gating/CollectionProfile.swift
  - Sources/Gating/CombinedBalance.swift
  - Sources/Gating/GatingConfiguration.swift
  - Sources/Gating/GatingConfigurationError.swift
  - Sources/Gating/GatingFormatting.swift
  - Sources/Gating/LiquidityConfiguration.swift
  - Sources/Gating/LiquidityPool.swift
  - Sources/Gating/MemberHoldings.swift
  - Sources/Gating/NumberedEnvironment.swift
  - Sources/Gating/Reading.swift
  - Sources/Gating/RoleDecision.swift
  - Sources/Gating/RoleRules.swift
  - Sources/Gating/Tier.swift
  - Sources/Gating/TierConfiguration.swift
  - Sources/Gating/TokenProfile.swift
db_tables: []
depends_on: []
---

# Gating

## Purpose

Decide which roles a member of a server should hold, from what an operator
configured and what somebody else read about that member. The module loads a
server's own ladder, collections, pools, token and administrators out of
numbered variables, refuses a configuration that does not add up while naming
the variable to fix, and turns one member's holdings into a set of roles to add
and a set to take away.

It touches no Discord, no chain, no database and no clock. A role is a plain
string, a holding is a value somebody hands in, and every fact that could have
failed to be read arrives as a `Reading` rather than as a number. Nothing is
granted or taken away on a fact nobody read, which is the one rule the rest of
the module exists to keep. The library has no dependency beyond Foundation, and
`RoleRules.decide` is a function from values to values, so every rule in it can
be pinned by a test without a guild.

## Public API

Every exported symbol of the `Gating` library target, in source order. A name
declared on more than one type is listed once, where it first appears.

| Export | Description |
|--------|-------------|
| `AdminAllowlist` | The accounts allowed to change a server's gating from outside Discord. Starts empty. |
| `accounts` | The allowed accounts, in the order they were configured, with duplicates removed. |
| `isEmpty` | True when nobody can administer by signing. `CollectionCatalog` and `LiquidityPoolCatalog` spell their own emptiness with the same name. |
| `allows` | True when this account may administer. Compared exactly, never folded for case. |
| `adding` | The list with an account added. Adding one already on it changes nothing. |
| `removing` | The list with an account removed. Any account, including the last one. |
| `load` | Reads configuration from an environment dictionary, or from a lookup the host supplies. Every loader in the module spells this the same way, and none of them falls back to a default. |
| `init` | Builds an allowlist from the accounts an operator named, dropping blanks and repeats and keeping the order they were written in. |
| `CollectionConfiguration` | Builds a `CollectionCatalog` from numbered variables. |
| `CollectionCountRung` | One rung of a collection's stacked count ladder: hold this many pieces, get this role. |
| `minimumCount` | The fewest pieces that reach this rung. Always at least one. |
| `roleId` | The Discord role a rung grants. On `CollectionProfile` it is the badge for holding one piece, on `LiquidityPool` the badge for providing to that pool, and on both it may be nil. |
| `CollectionProfile` | One named collection, how a piece of it is recognised on chain, and what holding pieces of it earns. |
| `id` | Stable key. Persisted, and used to look a collection, a pool or a rung up. |
| `displayName` | What a member sees. The id when the operator named nothing. |
| `creatorAddress` | The account that minted the pieces. Required per collection; there is no default creator. |
| `namePrefix` | Pieces whose name starts with this, ignoring case. Nil matches any name. |
| `unitName` | Pieces whose unit name is exactly this, ignoring case. Nil matches any unit name. |
| `maxSupply` | The largest supply an asset may have and still be a piece of this collection. One unless the operator says otherwise. |
| `countRungs` | Stacked count rungs, ascending. Empty when a count earns nothing. |
| `matches` | True when an asset belongs to this collection: inside the supply ceiling, minted by the creator, and past whatever name rules were set. |
| `rungsToAssign` | Every rung a count or a balance reaches. Stacked, so the rungs underneath the top one are kept. |
| `allRoleIds` | Every role this can grant. Answered by a collection, by either catalogue, and by the whole configuration. |
| `CollectionCatalog` | Every collection a server gates on. |
| `collections` | The collections, in the order they were configured. |
| `collection` | The collection with this id, or nil. |
| `match` | The collection an asset belongs to, or nil for none of them. First match wins, in configured order. |
| `AccountBalance` | What one account is recorded as holding. |
| `account` | The account. |
| `directBaseUnits` | The gated token held directly, in base units. |
| `liquidityBaseUnits` | The gated token inside this account's liquidity positions, in base units. |
| `CombinedBalance` | Adding a member's accounts up without demoting them for owning more than one. |
| `Totals` | A member's holdings across every account, added up. |
| `direct` | Held directly, across every account. |
| `liquidity` | Held inside liquidity positions, across every account. |
| `combined` | The two added together. This is what the ladder is read against. |
| `otherAccountsExist` | Whether the member has more than the one account in hand: more than one account in the list after `across`, and something on record besides the account that just signed after `afterLinking`. |
| `accountCount` | How many accounts the totals were summed over. Distinct from `otherAccountsExist`, which is a yes or no: a caller deciding whether a figure is worth trusting needs the number. |
| `accountsFromStoredBalances` | The accounts whose figure came from what was stored rather than from a fresh read, named rather than counted, so a caller can say which part of a total is old. |
| `across` | Adds every account up, or says that nothing was added up. An empty list is `unknown`, never a total of nothing. |
| `afterLinking` | The totals to decide roles on straight after a member links an account. The linked account is dropped from the stored figures first, so the figure just read wins over the one beside it. |
| `GatingConfiguration` | Everything an operator decides about what holding something earns. One value, loaded once, and the only thing the rules read. |
| `token` | The token the ladder is measured in. |
| `ladder` | The rungs. |
| `tierRoleIds` | Discord role id per rung id. |
| `pools` | Every pool the server counts. |
| `verifiedRoleId` | The role for having verified an account at all, or nil for none. |
| `admins` | The accounts allowed to administer. Empty by default. |
| `verifiedRoleKey` | The variable naming the role for having verified an account. |
| `GatingConfigurationError` | What is wrong with the configuration somebody wrote. Every case names the variable to fix. |
| `errorDescription` | The refusal written out for a person: the variable, what it says now, and why there is no default standing behind it. |
| `missing` | A variable that has no default and was not set. |
| `notANumber` | A variable that has to be a whole number and is not. |
| `zeroMinimum` | A threshold of zero. Everybody reaches it, so it is not a threshold. |
| `zeroSupply` | A supply ceiling of zero. Nothing on chain could ever be under it. |
| `tooManyEntries` | A numbered list that carries on past the last number this module reads. |
| `unusableName` | A name with nothing in it an id can be made from. |
| `unusableURL` | A URL the bot would hand to Discord and Discord would reject. |
| `unusableColor` | A colour that is not six hexadecimal digits. |
| `unsupportedDecimals` | More decimals than ten to that power fits in 64 bits. |
| `duplicateId` | Two entries resolve to the same id, so one would overwrite the other. |
| `duplicateName` | Two entries share a display name, which is what gets stored and counted. |
| `duplicateMinimum` | Two count rungs sit at one threshold, so one can never be reached. A count is compared exactly as it was written. |
| `duplicateThreshold` | Two ladder rungs come to one threshold once converted. Carries both whole numbers that were written and the amount they met at, because two numbers past the token's precision both saturate and neither of them is the threshold the rungs collided on. |
| `duplicateAsset` | Two entries claim the same on-chain asset. |
| `GatingFormatting` | Writing integer smallest units out for a person to read, and keeping a payload inside the bounds Discord accepts. |
| `grouped` | `1234567` as `1,234,567`. Hand-rolled, because `NumberFormatter` is locale-sensitive and not identical on Linux. |
| `amount` | Smallest units written as a decimal amount at the asset's own precision, with no digit lost and trailing zeros of the fraction trimmed. Exact at every precision a `UInt8` can hold, because the point is moved through the digits rather than by dividing. |
| `compact` | A balance shortened to `1.5M` or `250K` for a card where the exact figure is not the point. The one declaration in `GatingFormatting` that goes near `Double` or `pow`, and it throws digits away on purpose: never for money. |
| `clamp` | Clamps text to a number of Swift characters, marking that it was cut. |
| `joinWithinLimit` | Joins lines while staying under a limit, appending a count of the whole lines that were dropped. |
| `DiscordPayloadLimit` | The lengths Discord refuses a payload for, named once rather than typed at each call site. |
| `embedTitle` | An embed title. |
| `embedDescription` | An embed description. |
| `embedFieldName` | One embed field's name. |
| `embedFieldValue` | One embed field's value. |
| `embedFooter` | An embed footer. |
| `embedAuthorName` | An embed author's name. |
| `embedTotal` | Every field of every embed on one message, added together. A message can pass each of the limits above and still be refused on this one. |
| `messageContent` | Plain message content. |
| `componentLabel` | The label on a button or a select option. |
| `LiquidityConfiguration` | Builds a `LiquidityPoolCatalog` from numbered variables. |
| `providerRoleKey` | The variable naming the badge for providing to any pool. |
| `LiquidityPool` | A pool the gated token is paired into, and what providing to it earns. |
| `name` | What a member sees. The id when the operator named nothing. |
| `lpAssetId` | The asset id of the pool's own LP token. |
| `pairedAssetId` | The asset the gated token is paired with. |
| `decimals` | Decimal places on the LP token. On `TokenProfile`, decimal places on the gated token, which every whole-token threshold in the module is converted through. |
| `tokenAssetId` | The asset id this pool treats as the gated token, copied in at load from the operator's one answer rather than read from a shared constant. |
| `LiquidityPosition` | What one member has in one pool, as somebody else worked it out. This layer does no pool arithmetic. |
| `poolId` | Which pool. |
| `lpBaseUnits` | How much of the pool's LP token the member holds. |
| `tokenBaseUnits` | How much of the gated token that position represents, in the token's smallest unit. |
| `isProviding` | True when the member holds any of this pool's LP token. |
| `LiquidityPoolCatalog` | Every pool a server counts, and the one badge providing to any of them earns. |
| `providerRoleId` | The badge for providing to any pool at all, or nil for none. |
| `pool` | The pool with this id, or the pool whose LP token this is. Nil for neither. |
| `MemberHoldings` | Everything the rules know about one member, and how much of it was actually read. |
| `memberId` | Who this is. A Discord user id at the boundary, a string here. |
| `isVerified` | Whether the member has any verified account at all. Not a reading: a linked account is this bot's own record. The one field of `MemberHoldings` with no default, because both defaults lie. |
| `directBalance` | The gated token held directly, summed across accounts, in base units, or unknown. |
| `liquidityPositions` | Every liquidity position, across accounts and pools. One reading for the lot, because a partial list is exactly the failure that demotes a provider. |
| `count` | How many pieces of this collection the member holds. A collection nobody asked about comes back unknown. |
| `combinedBalance` | The gated token held directly plus the gated token inside every position. Unknown unless both halves were read. |
| `liquidityBalance` | The gated token inside every position, or unknown. |
| `isProvidingLiquidity` | True when the member holds any of any pool's LP token. |
| `position` | The member's position in one pool, or unknown when the positions were not read. A pool a read list does not mention is a zero position. |
| `NumberedEnvironment` | How every list in this module is written down, and the rules that make a typo visible. |
| `maxEntries` | Highest number any list is scanned to. Not a product limit anybody should reach. |
| `refuseOverflow` | Refuses an unbroken list that carries on past the last number scanned, rather than dropping the rest of it. It probes the one number the list would have carried on with, which is all a lookup can be asked; above a gap, at any number, the gap rule governs instead. |
| `nonEmpty` | A variable's value with the whitespace taken off, or nil when it is unset or blank. Blank counts as unset. Newlines are trimmed as well as spaces, because almost every value arrives from a file and a file's last line ends in one. |
| `withoutDigitSeparators` | A number with its underscores removed, ready to parse. The single place that rule lives, so `100_000` means the same thing in every layer that reads a number. |
| `requiredWholeNumber` | A variable that has to be a whole number and has to be set. Underscores are allowed as digit separators. |
| `required` | A variable that has to be set to something. |
| `slug` | A slug fit for an id, from a display name an operator typed. Nil for a name with nothing usable in it. |
| `isLinkableURL` | True when Discord will accept this as a link or a thumbnail: http or https, with a host, and short enough to send. |
| `color` | Six hexadecimal digits as a colour, with or without `#` or `0x`. |
| `Reading` | A fact this layer was either told, or was not told. |
| `isKnown` | True when the value was read. |
| `require` | The value, or a refusal naming what could not be read. Deliberately throwing rather than optional. |
| `map` | The same reading with its value transformed. Unknown stays unknown. |
| `UnreadableError` | Something a decision needed was never read. |
| `subject` | What could not be read, in words an operator recognises. |
| `known` | Somebody read this and it is the value given. |
| `unknown` | Nobody could read this. It is not zero, and it is not empty. |
| `GatingUnknown` | Something the rules needed and were not given. Names a fact rather than a role, because one unread fact usually holds several roles. |
| `sentence` | One plain sentence an operator can act on. |
| `MemberDisposition` | What a sweep did to one member. Two cases rather than a `Bool`, because the reasons live beside it. |
| `RoleDecision` | Which roles a member should hold, which they should not, and what was not read. A value: it grants nothing and takes nothing away. |
| `standing` | Where the member stands on the ladder, including "nobody read it". `TierLadder.standing(for:)` is what works it out. |
| `managed` | Every role this decision is entitled to add or remove. |
| `target` | Exactly the roles the member should hold once the decision is applied, including the ones this decision does not manage and must preserve. |
| `granted` | Roles to add. |
| `revoked` | Roles to take away. Always a subset of `managed`. |
| `held` | Configured roles this decision deliberately left alone, because something needed to decide them was not read. |
| `unknowns` | What was not read, in the order the rules wanted it, each named once. |
| `disposition` | Whether applying this would change anything. |
| `isComplete` | True when every fact the rules wanted was read. |
| `summary` | One line for a log or an operator's card: what was added, what was taken, how much was held, and why. |
| `balance` | The member's direct balance was not read. |
| `changed` | The member should end the sweep holding a different set of roles. |
| `unchanged` | The member already holds exactly what they should. |
| `RoleRules` | The decision itself: given what a member holds and what the operator configured, which roles should they have. |
| `decide` | Which roles this member should hold, and which they should not, from the configuration, the holdings and the roles they hold now. |
| `orphanSweepBaselineMinimum` | Smallest recorded baseline the drop check applies to. Below it a server is too small for a halving to mean anything. |
| `orphanSweepDropDivisor` | The drop check refuses when the count fell below this fraction of the last recorded one. |
| `OrphanSweep` | Whether it is safe to take managed roles away from members who have no verified account, and what to record if it is. |
| `mayRun` | True when the sweep may run. |
| `refusal` | Why the sweep was refused, or nil when it was not. |
| `orphanSweep` | Whether to sweep, and the baseline to record if so, from the count now and the count the last sweep that ran recorded. |
| `unlinked` | Holdings for somebody with no verified account: read, and empty. Only safe once the caller has proved the member really is unlinked. |
| `run` | The sweep may run, and this is the count to record as the new baseline once it does. Nothing else is. |
| `refuse` | The sweep must not run. Nothing is recorded, so the baseline it was compared against survives for the next one. |
| `Tier` | One rung of a server's holder ladder: what it is called and what it costs. A value, not a case in an enum. |
| `emoji` | Shown beside the name on a card. Empty is allowed and renders as nothing. |
| `minimumBaseUnits` | The smallest balance on this rung, in the token's smallest unit. |
| `display` | The name with the emoji in front, or just the name when there is none. |
| `TierStanding` | Where a member stands on the ladder, including the case where nobody knows. Three cases, and no `none` to compare against. |
| `tier` | The rung, or nil when the member is on none. `TierLadder.tier(for:)` is the highest rung a balance reaches. |
| `wasRead` | True when somebody managed to read the balance, whatever it said. |
| `TierLadder` | A server's holder ladder: the rungs, in order, and how a balance finds one. The only thing in the module that turns a balance into a rung. |
| `rungs` | The earning rungs, ascending. May be empty, which is a configuration and not an error. |
| `unrankedName` | What a member below the bottom rung is called on a card. A label, not a rung: no threshold and no role. |
| `unrankedEmoji` | The emoji beside `unrankedName`. |
| `rung` | The rung with this id, or nil. |
| `storedRung` | The rung a stored row named, or nil when it names none of them. Tried as the id, then the id ignoring case, then the display name ignoring case. Nil as well when more than one rung answers to it, and nil for the no-rung label, so the leniency carries its own guards rather than borrowing the loader's. |
| `on` | The balance was read, and it reaches this rung. |
| `unranked` | The balance was read, and it reaches no rung. |
| `unread` | The balance was not read. This is not the bottom of the ladder. |
| `LoadedTiers` | A ladder and the Discord role each rung grants. |
| `roleIds` | Discord role id per rung id. A rung the operator gave no role is simply absent. |
| `rungsWithoutRoles` | The rungs the operator gave no role, in ladder order. The one place a mistyped `TIER_n_ROLE_ID` is visible. |
| `TierConfiguration` | Builds a server's `TierLadder` from numbered variables. There is no default ladder. |
| `firstRungKey` | The variable that starts the ladder. |
| `unrankedNameKey` | The variable naming what a member on no rung is called. |
| `unrankedEmojiKey` | The variable naming the emoji beside it. |
| `TokenLink` | Somewhere a member can go to look at, buy or pool the token. A label and a URL, both the operator's. |
| `label` | What the link says, for example `Exchange` or `Explorer`. |
| `url` | Where it goes. |
| `markdown` | The link as Discord markdown. |
| `TokenProfile` | The one token a server's holder ladder is measured in. |
| `assetId` | The on-chain asset id. |
| `symbol` | The ticker, as it appears beside an amount. |
| `baseUnitsPerWholeUnit` | Smallest units in one whole token: ten to the power of `decimals`. |
| `logoURL` | A thumbnail for a card, or nil when the operator set none. |
| `cardColor` | The stripe down the side of a card, as `0xRRGGBB`, or nil for none. |
| `links` | Where a member can go to look at or trade the token. Empty when the operator picked nowhere. |
| `baseUnits` | Whole tokens as smallest units, saturating at the ceiling rather than wrapping. |
| `format` | Smallest units written out at this token's precision, no digit lost. |
| `formatWithSymbol` | Smallest units written out with the ticker after them. |
| `linksMarkdown` | Every link as one line of Discord markdown. |
| `assetIdKey` | The variable naming the asset. |
| `symbolKey` | The variable naming the ticker. |
| `displayNameKey` | The variable naming the longer name. |
| `decimalsKey` | The variable naming the precision. Required, with no default. |
| `logoKey` | The variable naming the card thumbnail. |
| `colorKey` | The variable naming the card colour. |

## Invariants

1. A fact nobody read decides nothing. Every role an unread fact would have
   decided is taken out of `RoleDecision.managed` and lands in
   `RoleDecision.held`, so it is preserved rather than stripped. This holds for
   a role two facts decide as well: the read fact cannot take away what the
   unread fact also grants.
2. A role outside `RoleDecision.managed` is never added and never removed.
   `RoleDecision.revoked` is always a subset of `managed`, and `managed` is
   always a subset of `GatingConfiguration.allRoleIds`, so a badge a moderator
   handed out by hand survives every sweep.
3. `RoleDecision.granted` is always a subset of `managed` too. Holding a role
   back from the managed set never smuggles a grant past it.
4. `.known(0)` and `.unknown` are different values with opposite consequences,
   and there is no accessor on `Reading` that hands back a value with a
   default. A caller either switches on the case or calls `require(_:)` and
   deals with the throw.
5. Nothing in the module reads the environment, a clock, a network, a database
   or a Discord type. Configuration arrives through a `(String) -> String?`
   lookup, holdings arrive as values, and a role is a plain string.
6. Every whole-token threshold is converted to base units through
   `TokenProfile.baseUnits(whole:)` and nowhere else, and `TierLadder` is the
   only thing that turns a balance into a rung. Nothing else in the module
   compares a balance against a threshold.
7. Every sum of balances saturates at `UInt64.max` rather than wrapping. A
   wrapped sum would put the largest holder in the server on no rung at all.
8. A numbered list is read from 1 upward and the first gap ends it. A gap is
   never skipped, so a typo drops entries visibly rather than renumbering the
   ones above it in silence. Reaching the scan limit with no gap is a refusal
   instead, because that list stopped for a reason that is nowhere in the
   operator's file. Above a gap the gap rule governs at every number, limit or
   no limit: an entry written above one is dropped, and a boot-time read-back
   of the loaded configuration is what makes it visible (ADOPT-9.a).
9. Absent configuration is either an explicit emptiness or a refusal naming the
   variable. Nothing falls back to a name, a threshold, an account, an asset or
   a link from another project.
10. Every `GatingConfigurationError` names a variable to fix in its
    `errorDescription`, and it names the variable the operator actually set
    rather than one they never wrote: a rung whose id came from its name is
    reported against `TIER_n_NAME`, not against the `TIER_n_ID` nobody typed.
11. Ladder rungs and collection count rungs stack: reaching one rung keeps
    every rung underneath it.
12. `RoleRules.orphanSweep` returns the baseline to record only on `.run`. A
    refusal carries no count, so a caller cannot lower the bar to the count it
    just observed.
13. No amount that somebody has to be able to check goes through `Double`,
    `NumberFormatter` or a locale. `GatingFormatting.amount(_:decimals:)` and
    `TokenProfile.format(_:)` keep every digit, at every precision, by moving
    the point through the digits rather than dividing;
    `GatingFormatting.compact(_:decimals:)` is the one lossy path, the one
    declaration in that type that goes near `Double`, and is labelled as such
    in its own documentation.
14. `MemberHoldings.collectionCounts` is private and reachable only through
    `count(ofCollection:)`, which answers `.unknown` for a collection nobody
    asked about. There is no subscript for a caller in a hurry to write `?? 0`
    against.
15. Nothing in `MemberHoldings` defaults in the direction of granting. The
    readings default to `.unknown`, which holds roles rather than taking them,
    and `MemberHoldings.isVerified`, which is not a reading, has no default at
    all: `true` would grant the verified badge on a sweep that read nothing
    and `false` would take it off everybody who has one.
16. `TierLadder.storedRung(_:)` answers only when exactly one rung answers to
    the row, and never answers with a rung for the no-rung label.
    `TierConfiguration.load` refuses the ladders that would make the leniency
    ambiguous, but `TierLadder` and `Tier` are public values a host can build
    by hand, so the leniency holds its own guards rather than resting on the
    loader's refusals.

## Behavioral Examples

### Scenario: A provider outage does not demote anybody

- **Given** a member holding enough for two rungs, whose direct balance could
  not be read this sweep
- **When** `RoleRules.decide` is called with `directBalance` as `.unknown`
- **Then** `revoked` is empty, both rungs are still in `target`, `standing` is
  `.unread` rather than `.unranked`, `unknowns` is `[.balance]`, and every tier
  role is reported in `held`

### Scenario: What is parked in a pool counts toward the rung

- **Given** a server with a bottom rung at 100 whole tokens, and a member
  holding 90 in their wallet and 20 in a pool
- **When** the decision is made
- **Then** `combinedBalance` is the 110 whole tokens in base units, the member
  is on the bottom rung, and the same member without the position is
  `.unranked`

### Scenario: A badge two facts decide survives one of them going unread

- **Given** an operator who pointed a second collection's badge at the first
  collection's role, and a sweep that counted the first collection and could
  not count the second
- **When** the decision is made
- **Then** the badge is in `held` and in `target`, `revoked` is empty, and the
  only reported unknown is the collection that could not be counted

### Scenario: A sweep against an emptied store refuses and records nothing

- **Given** a last recorded baseline of 400 verified members and a store that
  now reports 1
- **When** `RoleRules.orphanSweep` is asked
- **Then** it answers `.refuse` with a reason naming both counts, and carries
  no baseline, so the next sweep is still measured against 400

### Scenario: A ladder built in code does not get the benefit of a refusal nobody made

- **Given** a `TierLadder` a host built itself, holding two rungs both called
  `Gold` at different thresholds, which `TierConfiguration.load` would have
  refused
- **When** a stored row naming `Gold` is resolved with `storedRung`
- **Then** it answers with no rung, rather than with whichever of the two sorts
  lowest, and the two rungs are each still reachable by their own id

### Scenario: Two thresholds that only collide once converted say so

- **Given** two rungs written as two different whole numbers, both past what
  the token's six decimals can express, so both convert to the ceiling
- **When** the ladder is loaded
- **Then** it is refused with `.duplicateThreshold`, naming both variables,
  both numbers as they were written, and the one converted amount they met at,
  which is in neither variable

### Scenario: A mistyped rung number loses a rung rather than renumbering the ladder

- **Given** an operator who meant four rungs and typed the fourth as `TIER_5_`
- **When** the ladder is loaded
- **Then** it has three rungs, the fifth rung's role is in no ladder at all,
  and nothing has been silently promoted into rung four's place

## Error Cases

| Condition | Behavior |
|-----------|----------|
| `TIER_1_NAME` unset | `GatingConfigurationError.missing`, naming `TIER_1_NAME`. There is no default ladder |
| `TOKEN_ASSET_ID`, `TOKEN_SYMBOL` or `TOKEN_DECIMALS` unset | `.missing`, naming that variable. The token is read before the ladder, so a missing precision is caught before a threshold is converted |
| A collection with no `COLLECTION_n_CREATOR` | `.missing`. There is no default creator |
| A pool missing `LP_ASA`, `PAIRED_ASA` or `DECIMALS` | `.missing`. A pool that cannot be priced is refused rather than skipped in silence |
| A count rung with a `MIN` and no `ROLE_ID` | `.missing`. A count rung that grants nothing does nothing at all |
| A link with a label and no URL | `.missing`, naming the URL variable |
| A threshold, asset id, supply or decimal count that is not a whole number | `.notANumber`, quoting what was written |
| A rung or count rung at zero | `.zeroMinimum` |
| `COLLECTION_n_MAX_SUPPLY` of zero | `.zeroSupply` |
| An entry numbered past `NumberedEnvironment.maxEntries` in an unbroken list | `.tooManyEntries`, naming the first variable beyond the limit |
| A name with no letters or digits in it | `.unusableName`, from the variable the id would have come from |
| A logo or link URL that is not http or https with a host | `.unusableURL` |
| A card colour that is not six hexadecimal digits | `.unusableColor` |
| Token or LP decimals above 19 | `.unsupportedDecimals`. Ten to the twentieth does not fit in `UInt64`, and the conversion from whole tokens needs it to. Writing an amount out has no such ceiling |
| Two rungs, collections or pools resolving to one id | `.duplicateId`, naming where each id came from |
| Two rungs sharing a display name, or a rung named after the no-rung label | `.duplicateName` |
| Two count rungs at one threshold | `.duplicateMinimum`, naming both variables and the count they share. A count is compared exactly as written |
| Two ladder rungs at one threshold | `.duplicateThreshold`, naming both variables, both whole numbers written and the converted amount they met at. Thresholds are compared after conversion, so two numbers that both saturate collide there and neither typed number is the collision |
| Two pools naming one LP asset | `.duplicateAsset` |
| Asking an unread `Reading` for its value | `UnreadableError`, naming the subject that was passed in |
| An empty list of accounts handed to `CombinedBalance.across` | `.unknown`, never a total of nothing |
| A collection nobody asked about | `count(ofCollection:)` answers `.unknown`, so its roles are held |
| A pool a position names that the operator has since removed | That position grants no pool badge, and nothing is guessed at |
| Zero verified members, or fewer than half the recorded baseline | `OrphanSweep.refuse` with a reason, and no baseline recorded |
| `GatingFormatting.amount` at any precision an asset can have | The exact amount. There is no divisor to overflow and no ceiling to fall off; a precision of none is the smallest units themselves, and a precision below zero cannot be written |
| Text or a list longer than a Discord payload limit | Cut, with `...` or a count of the dropped lines, rather than a payload Discord rejects |

## Dependencies

- Foundation, and nothing else. The module has no package dependencies and is
  not a dependency of any other target.
- The host supplies the configuration lookup, supplies `MemberHoldings` from
  wherever it reads chain and store, and applies a `RoleDecision` at the
  Discord boundary. Nothing in this module does any of the three.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-18 | maintainers | Spec written for the shipped `Gating` library target. |
| 2026-09-18 | maintainers | Cross-module audit: `amount` exact at any precision, `storedRung` guarded against an ambiguous hand-built ladder, `isVerified` stated rather than defaulted, `duplicateThreshold` added so a saturating collision is reported at the amount it happened at, and the overflow promise scoped to an unbroken list. |
