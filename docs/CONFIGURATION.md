# Configuration

Every environment variable this package reads, what it means, and what goes
wrong when it is wrong. That last part is why this document exists: most of
these are easy to set and a few of them are easy to set plausibly, and the
plausible ones are the expensive ones.

It is organised by what you are deciding, not alphabetically, and in roughly
the order you will decide it: your token, your ladder, your collections, your
pools, the node you read through and its brakes, where things are kept, the
roles, and who may administer.

Everything in this document was read out of `Sources/`. Where the code and this
document disagree, the code is right and this is a bug.

## Before the tables

**There is an executable now**, `bot`. "Refused" below means the boot stops
with one sentence naming one variable, before it has bound a port or opened a
store. Every refusal is also reachable from a test, which is how they stay
true. The variables belonging to parts the executable does not link yet —
the chat surface among them — are read by their own targets and their tests,
not by a boot you can run today.

**Four loaders read all of this**, and the executable calls them in this
order:

1. `TokenProfile.load` reads the token, because nothing else can be converted
   without its precision.
2. `GatingConfiguration.load` reads the token and then the ladder, the
   collections, the pools, the verified role and the administrators.
3. `ChainConfiguration.load` takes the token it has already been handed and
   reads the node and the brakes. It deliberately has no variable for the
   asset, so the asset is written down once in your file and cannot be written
   down twice differently.
4. `SurfaceConfiguration.load` reads the chat surface: the token, the server,
   the two ports and the portal. `DisclosureSettings.load` reads the two
   sentences a member is shown before they sign, and is called only when a
   portal is configured.

`Reserve`, `Store`, `StoreSQLite`, `Games` and `Verify` read **no environment
variable at all**. For four of them that is a happenstance of what they do;
for `Verify` it is a security property, and it is asserted rather than
promised. A setting that changes how a signature is checked is one setting
away from a setting that skips it, so `Tests/VerifyTests/TargetShapeTests.swift`
reads that target's own sources and fails if anything in it ever reads one.
The operator's challenge label and which prover route is live are real
settings that this package does not yet have a place to read, and they arrive
with the host that serves the page. What that means for a reserve is in
[The reserve](#the-reserve-no-variables-yet); the database path is read by the
executable and is in [Storage](#storage).

### Rules that apply to every variable

- **Blank is unset.** `TIER_3_NAME=` is the same as leaving the line out. That
  matters more than it sounds: it is a way to comment a rung out, and it is
  also a way to end a numbered list by accident.
- **Surrounding whitespace and newlines come off** before anything is parsed,
  in every layer, so a trailing newline from a file is never the reason a
  number is not a number.
- **Underscores are allowed in any number.** `100_000` and `100000` are the
  same everywhere, including the daily request budget. One environment, one
  rule.
- **Whole tokens, unless a row says smallest units.** A threshold is the number
  you would say out loud. The conversion happens in exactly one place, using
  `TOKEN_DECIMALS`.
- **Booleans** accept `1`, `true`, `yes`, `on` and `0`, `false`, `no`, `off`,
  in any case. Anything else is refused rather than read as false.
- **Nothing falls back to a value somebody else chose.** A required variable
  that is missing is a refusal naming it. There is no default ladder, no
  default creator, no default asset and no default node.
- **Numbered lists end at the first gap.** See
  [Where a numbered list ends](#where-a-numbered-list-ends), which is the
  section to read before you edit a file that already works.

---

## The token

One fungible asset. It is what the ladder is measured in, what balances are
read for, and what every amount a member sees is denominated in.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `TOKEN_ASSET_ID` | yes | none | The on-chain id of your asset. | A wrong id reads as nobody holding anything, so the next sweep takes every tier role in the server away at once; leaving it out is refused by name as a missing variable, and setting it to `0` is refused separately, with the value quoted, because zero names the chain's own currency rather than an asset anybody opts into. The two are different refusals from different places, so the message you get tells you which mistake you made. |
| `TOKEN_SYMBOL` | yes | none | The ticker printed beside an amount. | Nothing miscalculates, and every card, reply and leaderboard in your server says the wrong word for your token. |
| `TOKEN_DECIMALS` | yes | none | How many decimal places your asset has. Every whole-token threshold in the package is converted through this and nothing else. At most 19. | One place out and every balance in the process is out by a factor of ten, in a direction that either promotes everybody or demotes everybody, and nothing looks broken. See [Decimals](#decimals-and-why-there-is-no-default). |
| `TOKEN_NAME` | no | the symbol | The longer name, for a card's title. | Cosmetic. |
| `TOKEN_LOGO_URL` | no | no thumbnail | A card thumbnail. Must be `http` or `https` with a host, at most 2048 characters. | A URL that is not linkable is refused at load; a linkable one that points at nothing renders as a blank space. This package never fetches it, so a slow host costs you nothing here. |
| `TOKEN_CARD_COLOR` | no | no colour | Six hexadecimal digits, with or without `#` or `0x`. | Anything that is not six hex digits is refused by name; a valid but wrong colour is cosmetic. |
| `TOKEN_LINK_n_LABEL` | no | no links | One link's text, numbered from 1. | A label with no `TOKEN_LINK_n_URL` beside it is refused, because a link to nowhere is worse than no link. |
| `TOKEN_LINK_n_URL` | with its label | none | Where that link goes. Same URL rule as the logo. | A link an operator mistyped sends every member who taps it somewhere else; nothing validates the destination beyond its shape. |

### Decimals, and why there is no default

`TOKEN_DECIMALS` has no default, and it is the one place in this document where
you will be tempted to guess. Six is the most common precision on this chain, it
is what the bot this came from assumed, and it is wrong for plenty of assets.

Guessing costs more than the other guesses do, because every other number you
write is converted through it. A rung written as 1,000 whole tokens becomes a
threshold in smallest units exactly once, here. Set six for a zero-decimal
asset and each rung's real threshold is a million times what you meant, so no
member ever reaches the first rung and the whole ladder silently stops
existing. Set zero for a six-decimal asset and every member clears the top
rung on their first token.

So it is required, the package refuses to invent it, and there is a second
check you should leave on: `CHAIN_VERIFY_ASSET_DECIMALS` (on by default) reads
the asset's real precision from the chain and refuses to carry on when the two
numbers disagree, naming both. Read the number off your asset rather than
typing what you expect, and let that check catch you if you did not.

One caveat worth stating plainly: that check lives in `ChainReader` and a host
has to call it. There is no host yet, so today it is a method with a test and
not something that runs on its own.

---

## The tier ladder

The ladder is yours: your names, your thresholds, as many rungs as you want.
There is no default ladder, and leaving `TIER_1_NAME` unset is a refusal rather
than six rungs somebody else chose.

Three things about the shape before the table:

- **Rungs stack.** A member on the third rung is granted the first and second
  rungs' roles as well. Give each rung its own role unless you mean that.
- **Thresholds are whole tokens**, converted once through `TOKEN_DECIMALS`.
- **Thresholds are compared after conversion**, so two rungs that both saturate
  the ceiling collide and are refused, even though the two numbers you typed
  are different.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `TIER_n_NAME` | to define rung `n`; `TIER_1_NAME` always | none | The rung's display name, numbered from 1. | A mistyped number ends the ladder there and every rung above it is dropped in silence; two rungs sharing a name (ignoring case) are refused, because the name is what gets stored and counted; a name with no letters or digits in it is refused, because no id can be made from it. |
| `TIER_n_MIN` | with each name | none | The smallest holding on that rung, in **whole tokens**. Underscores allowed. | Typing smallest units instead of whole tokens gives you a rung nobody in the world reaches, and it is not refused unless it collides with another rung; `0` is refused, because a rung everybody reaches is not a rung. |
| `TIER_n_EMOJI` | no | none | Shown beside the name. | Cosmetic. |
| `TIER_n_ID` | no | a slug of the name | The stable key. Set it so you can rename a rung later. | Two rungs resolving to one id are refused; changing an id after members have been recorded against it can orphan those rows, which is the reason to set it explicitly on day one rather than letting it follow the name. |
| `TIER_n_ROLE_ID` | no | the rung grants no role | The Discord role this rung grants. | A rung with no role is legal and occasionally deliberate, so a mistyped variable name here looks exactly like a choice: the rung is shown on cards, grants nothing, and nothing refuses. |
| `TIER_UNRANKED_NAME` | no | `None` | What a member below the first rung is called. | A value that matches a rung's name or id is refused, because a stored row naming it would resolve to that rung and somebody on no rung would be granted its role. |
| `TIER_UNRANKED_EMOJI` | no | none | Shown beside it. | Cosmetic. |

---

## The collections

A collection is a set of assets recognised by who minted them. Declare as many
as you have, numbered from 1, or none: gating on a balance alone is an ordinary
way to run a server and is not a refusal.

An asset is a piece of collection `n` when **all** of these hold: its supply is
at least 1 and at most `COLLECTION_n_MAX_SUPPLY`, its creator is exactly
`COLLECTION_n_CREATOR`, its name starts with `COLLECTION_n_NAME_PREFIX` if one
is set, and its unit name equals `COLLECTION_n_UNIT_NAME` if one is set. The
name and unit comparisons ignore case; the creator comparison does not. When
two collections would both match an asset, the one written first wins.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `COLLECTION_n_ID` | to define collection `n` | none | The stable key, slugged. Numbered from 1. | A mistyped number ends the catalogue there and drops every collection above it; two collections slugging to one id are refused; changing an id later orphans what was recorded under the old one. |
| `COLLECTION_n_CREATOR` | with each id | none | The account that minted the pieces. This is how a piece of yours is told apart from every other asset on chain. | **Never validated as an address.** One wrong character loads perfectly and matches nothing, so the collection exists, holds nobody, and every holder loses its role at the next sweep. |
| `COLLECTION_n_NAME` | no | the id | What a member sees. | Cosmetic. |
| `COLLECTION_n_NAME_PREFIX` | no | matches any name | Narrows matching to pieces whose name starts with this. | Too broad a prefix, or none where you needed one, grants the collection's role for holding something else that creator minted. |
| `COLLECTION_n_UNIT_NAME` | no | matches any unit name | Narrows matching to pieces with exactly this unit name. | As above; a unit name with a typo matches nothing at all. |
| `COLLECTION_n_MAX_SUPPLY` | no | `1` | The largest supply an asset may have and still count as a piece. | Left at `1` for a collection minted in editions, nothing matches and every holder quietly has no role; raised too far, the creator's own fungible token counts as a piece and whoever holds a million of it holds the collection. `0` is refused. |
| `COLLECTION_n_ROLE_ID` | no | holding one grants no badge | The role for holding at least one piece. | Unset is legal, so a mistyped variable name here is indistinguishable from meaning it. |
| `COLLECTION_n_COUNT_m_MIN` | no | no count rungs | Hold at least this many pieces to earn a stacked badge. Numbered from 1 within the collection. | `0` is refused; two count rungs at one number are refused; a mistyped rung number drops that rung and every rung above it. |
| `COLLECTION_n_COUNT_m_ROLE_ID` | with each `_MIN` | none | The role that rung grants. | Required, unlike a tier rung's, and its absence is refused: a count rung with no role does nothing at all, so an operator who wrote one meant to give it a role. |

---

## The liquidity pools

Optional. A pool lets the token a member holds inside it count toward their
ladder standing, and can grant a badge of its own. A server that pairs its
token nowhere sets none of this.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `POOL_n_ID` | to define pool `n` | none | The stable key, slugged. Numbered from 1. | A mistyped number drops that pool and every pool above it; two pools slugging to one id are refused. |
| `POOL_n_LP_ASA` | with each id | none | The asset id of the pool's own LP token, which is what a member holds to prove they provided to it. | A wrong id means nobody is ever seen as a provider in that pool; two pools naming one LP asset are refused. |
| `POOL_n_PAIRED_ASA` | with each id | none | The asset your token is paired with. Your own side comes from `TOKEN_ASSET_ID` and is never written twice. | Wrong, and the share of your token a position represents cannot be worked out correctly, so the ladder is decided on a wrong combined balance. |
| `POOL_n_DECIMALS` | with each id | none | Decimal places on the LP token. At most 19. | One place out distorts every computed share in that pool by a factor of ten, which moves members up or down the ladder for a reason nothing in the server explains. |
| `POOL_n_NAME` | no | the id | Display name. | Cosmetic. |
| `POOL_n_ROLE_ID` | no | that pool grants no badge | A badge for providing to this pool specifically. | Unset is legal, so a typo looks like a choice. |
| `LP_PROVIDER_ROLE_ID` | no | no badge | One badge for providing to any pool at all. | Unset means liquidity still counts toward the ladder and no badge is granted, which is a legitimate setup and therefore not refused. |

A pool that is half written is refused rather than skipped. All four of `ID`,
`LP_ASA`, `PAIRED_ASA` and `DECIMALS` are needed once the pool exists, because
a pool that cannot be priced counting for nothing while saying nothing is the
failure this refusal exists to prevent.

---

## The chain endpoint and its brakes

One node, chosen by you. There is no default endpoint anywhere in this package
and no fallback: if this is unset, the load refuses.

Two brakes sit in front of every request, and they measure different things. The
limiter bounds requests **per second**, which is what a provider's rate limit
cares about. The budget bounds requests **per UTC day**, which is what a free
or metered quota cares about. At the limiter's default rate a small daily quota
is reachable in minutes, and the provider's refusal arrives only once the quota
is already spent.

A **budget counts requests**. It is not a spending cap and this document will
not call it one.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `CHAIN_NODE_URL` | yes | none | The node to read from. Absolute `http` or `https`, with a host. | Pointed at a network your asset does not live on, it loads clean and every member reads as holding nothing; a value without a host, such as a bare scheme, is refused by name rather than booting and failing every read later. |
| `CHAIN_API_TOKEN` | no | none | Your provider's token, sent as a request header to that node and nowhere else. **A secret.** | Never checked at load. A wrong token means every read fails at runtime, and a quota refusal pauses the budget, so the symptom is a bot that stops updating roles rather than one that will not start. |
| `CHAIN_VERIFY_ASSET_DECIMALS` | no | `true` | Whether to read the asset's precision from the chain at boot and refuse when it disagrees with `TOKEN_DECIMALS`. | Turning it off removes the one automatic check on the most expensive number in your file, to save a single request. |
| `CHAIN_REQUESTS_PER_SECOND` | no | `10` | What the limiter allows. Must be 1 or more and finite. | Set above what your provider allows and it refuses you at its own rate limit; set at exactly the published rate and a few milliseconds of clock difference becomes a refusal. Leave headroom. |
| `CHAIN_DAILY_REQUEST_BUDGET` | no | `0`, meaning no budget | Requests permitted per UTC day, counting reads **and** signing, so the number is the whole process. | Left at `0` on a metered plan, a sweep can spend the day's quota before lunch and every read fails until midnight; set too low, the budget pauses work that was healthy. Warnings are raised the first time 50, 75 and 90 percent are reached in a day. |
| `CHAIN_BUDGET_PERSIST_EVERY` | no | `25` | Requests between writes of the day's counter, so a restart does not hand the process a fresh day. | Too high and a crash forgets that many requests, which is how a restart loop spends a quota twice; `0` is refused. |
| `CHAIN_BATCH_SIZE` | no | `50` | How many accounts are read in parallel per batch. | Too large a batch spends the day's budget in bursts and irritates a provider that is watching concurrency; `0` is refused. |
| `CHAIN_CALLER_SHARE_PERCENT` | no | `5` | The share of the day's budget any one member may draw, as a percentage. `0` turns shares off. | **It does nothing unless `CHAIN_DAILY_REQUEST_BUDGET` is set**, because there is no day's budget to take a part of. Set it small and a member with several wallets is refused mid-command; set it large and one person can still spend most of the day. Above `100` is refused by name rather than clamped. |
| `CHAIN_CALLER_BURST_REQUESTS` | no | `10` | The most one member may take before their allowance has to refill. | Too small and an ordinary command that reads three wallets is refused; larger than the day's share, it is clamped to the share rather than refused. `0` is refused. |
| `CHAIN_PROOF_HEADERS` | no | none | Comma-separated response header names copied onto a health answer as proof of which provider served the request. | A header your provider does not send contributes nothing rather than a fabricated value, so a wrong name here is a health answer that quietly proves less than you think. The first check after a start answers without a provider section and starts the probe that fills it, so read the second. |
| `CHAIN_POOL_CACHE_SECONDS` | no | `60` | How long a pool's reserves stay usable. | Long, and shares are computed from reserves that have moved; `0` means never cached, which spends the budget on every read. |
| `CHAIN_WALLET_CACHE_SECONDS` | no | `300` | How long a completed account reading stays usable. | As above, for balances: a long life shows members a tier they have already left. |
| `CHAIN_WALLET_COOLDOWN_SECONDS` | no | `60` | How soon the same account may be read again on demand. | `0` lets one member re-read their own wallet as fast as they can type, which is a direct line from a keyboard to your daily budget. |
| `CHAIN_HEALTH_PROBE_CACHE_SECONDS` | no | `30` | How long a health probe's answer is reused, a failed one included. | `0` turns a monitoring check every few seconds into traffic to your node, and it is a probe that failed that would be repeated hardest, at the moment the node can least take it. |

Every numeric variable here refuses a value it cannot use, naming the variable
and saying what was expected: negative seconds, a rate below one, a batch below
one, a value that is not a number at all.

---

## Storage

`Store` and `StoreSQLite` read **no environment variable**. The path arrives
as a parameter to `SQLiteStore.open(at:)`, deliberately, so that a test can
never quietly find an operator's live file. The executable is what reads the
variable and passes it in.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `STORE_PATH` | yes | none | Where the database file goes. | There is no default on purpose: a file this package chose is a file you do not know to back up. A path on a network filesystem is refused outright, because it cannot promise a write has reached storage and the whole no-double-pay discipline rests on that promise. A path in a container's writable layer loads perfectly and loses every member the first time the container is replaced. |

Two facts about the store that an operator will meet:

- **A network filesystem is refused.** It cannot promise a write has reached
  storage when it says it has, and the whole no-double-pay discipline rests on
  that promise. Point the store at a local volume.
- **A second process on one file is refused**, by an exclusive lock taken
  before anything else happens. That is what stops two instances each deciding
  the same week is unpaid.

---

## The roles

There is no single block of role variables, because a role belongs to the thing
that grants it. They are:

| Role | Where it is set |
|------|-----------------|
| A tier's role | `TIER_n_ROLE_ID` |
| A collection's badge | `COLLECTION_n_ROLE_ID` |
| A stacked count badge | `COLLECTION_n_COUNT_m_ROLE_ID` |
| A single pool's badge | `POOL_n_ROLE_ID` |
| Any liquidity at all | `LP_PROVIDER_ROLE_ID` |
| Having verified an account | `VERIFIED_ROLE_ID` |

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `VERIFIED_ROLE_ID` | no | no role | Granted to any member with a verified account, whatever they hold. | Unset means verification is invisible in the member list; this is the one role that is always decidable, because it depends on this bot's own record rather than on anything read from a chain. |

Two rules about roles that are worth knowing before you fill any of these in:

- **A role you did not configure is never touched.** The set of roles the bot
  may add or remove is exactly the set named in your file. A badge a moderator
  handed out by hand survives every sweep.
- **A role decided by a fact nobody could read is held, not removed.** If a
  balance or a collection count could not be read, the roles that fact would
  have decided drop out of the managed set for that member and are left alone.
  Silence is not evidence that somebody sold up.

And one that is worth knowing after: **no role id is ever validated.** Any
non-empty string is accepted, so a placeholder or a wrong digit loads perfectly.
See [Which mistakes refuse by name, and which do
not](#which-mistakes-refuse-by-name-and-which-do-not).

---

## The chat surface

Everything the bot needs to be a bot. A missing or placeholder value stops the
boot before a port is bound or Discord is spoken to.

**Two loaders read this table, and `swift run bot` uses the smaller one.**
`SurfaceConfiguration.load` reads every row below and belongs to
`DiscordSurface`, which binds its own two ports and runs its own boot. The
executable does not use it: it walks the composition root's eight gates, which
bind one listener and open one store, and the chat surface it builds reads
only its own four rows plus `BOT_NAME`, through `ChatSurfaceSettings.load`.

So under `swift run bot` today:

- `DISCORD_BOT_TOKEN` is the switch. Unset, and the process starts, serves its
  health endpoint and identifies to nothing, which is a whole answer rather
  than a broken one. Set, and `DISCORD_GUILD_ID` is required with it.
- `DISCORD_APPLICATION_ID` and `DISCORD_ADMIN_ROLE_ID` are read and optional.
- `HEALTH_PORT`, `HEALTH_ADDRESS` and `STORE_PATH` are the composition root's
  own, and `LISTEN_ADDRESS` is not read.
- `VERIFY_CALLBACK_PORT` and every other `VERIFY_` variable is **refused**,
  because the executable assembles no callback listener and no portal client.
  Setting one would start a bot that offers nothing to prove an account, so it
  is refused by name instead. That refusal is why only `/ping` and `/help` are
  registered today, and not `/verify` and `/unlink`.

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `DISCORD_BOT_TOKEN` | yes | none | Your bot's token. **A secret.** | A missing one is refused by name. A value still holding an example placeholder is refused separately, with the value quoted, because starting on one points your bot at nothing at all. The token is never printed back out; the application id is read out of it so the boot report can print an invite. |
| `DISCORD_GUILD_ID` | yes | none | The one server this process serves, as a decimal id copied from Discord with developer mode on. | A value that is not one to twenty digits is refused by name, and so is a placeholder: `0` is a legal shape and never a server, so the shape check alone would pass it. A valid id for the wrong server loads perfectly, registers the commands there, and refuses every interaction from the server you meant. |
| `DISCORD_APPLICATION_ID` | no | read out of the token | Your application id, used only to build the invite URL the boot report prints. | Unset is fine when the token is the ordinary shape. When it cannot be read, the report names this variable instead of printing a URL with a hole in it. |
| `DISCORD_ADMIN_ROLE_ID` | no | Administrator only | One extra role that may run an operator command. | An empty value grants nobody, deliberately: an unset variable reaches the check as an empty string, and matching on it would make every member with no roles an operator. No operator command ships at this commit; the rule is here so the first one cannot be added as always-on. |
| `HEALTH_PORT` | yes | none | The port the health check binds. | No default, because a port is your firewall's business. It is bound **before** this process identifies to Discord, which is how a second copy of the bot discovers the first: the second one refuses on the bind and the copy already serving your server keeps serving it. Set it to a port something else is using and the boot stops naming the port. |
| `VERIFY_CALLBACK_PORT` | yes | none | The port your portal's callback arrives on. | As above. Setting it to the same number as `HEALTH_PORT` is refused, because one process cannot bind a port twice. |
| `LISTEN_ADDRESS` | no | `127.0.0.1` | What both listeners bind. | Loopback by default, because the alternative default is every interface on a process that may one day hold a signing key. A portal on another machine needs this widened and needs the port reachable only from that machine. |
| `BOT_NAME` | no | `this bot` | What the bot calls itself at the top of a card. | Cosmetic, and the default deliberately names no project. |

### Verification

Set `VERIFY_PORTAL_URL` and verification exists. Leave it out and it does
not: `/verify` and `/unlink` are never registered, nothing in your server
offers to prove an account, and the boot says so in one line rather than
leaving you to notice (`ADOPT-10.b`).

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `VERIFY_PORTAL_URL` | no | verification off | Where the other half lives. Absolute `http` or `https`, with a host, no trailing slash. | A trailing slash is taken off for you. A URL with no host is refused by name. A URL pointing somewhere that is not a conforming portal fails the boot's health call, which is deliberate: a bot that starts anyway hands members a link into nothing. |
| `VERIFY_SHARED_SECRET` | with a portal | none | The one secret both halves hold. **A secret.** At least 32 random bytes. | One secret, not one per direction. Two variables is how an operator sets the outbound one, passes their own health gate, and fails every `/verify` with a `401` nobody sees. The boot makes a keyed probe: if your portal answers it and the secrets disagree, the boot stops. A portal that offers nothing to probe is reported as unprobed rather than as agreed. |
| `VERIFY_OPERATOR_NAME` | with a portal | none | Who runs this instance, shown to a member before they sign. | Required, with no default, because no sentence this package ships can say who runs your server. A member deciding whether to sign is deciding about you. |
| `VERIFY_VISIBILITY_NOTE` | with a portal | none | Which of what is kept other members can see, in your words. | Required for the same reason. Only you know whether your server shows a rung, an account, both or neither. |
| `VERIFY_OPERATOR_CONTACT` | no | none | How to reach you: a channel, an address, a handle. | Unset simply leaves it off the card. |

---

## The administrators

| Variable | Required | Default | What it is | What goes wrong if it is wrong |
|----------|----------|---------|------------|-------------------------------|
| `ADMIN_WALLET_n` | no | the list is empty | An account allowed to administer by signing, numbered from 1. Compared exactly, never folded for case. Duplicates and blanks are dropped, order is kept. | **Never validated as an address.** A typo locks that person out silently; an empty list is a legitimate and safe starting state, so nothing warns you that nobody can administer. |

Nobody is on this list who was not put there by you. There is no built-in
member, nothing this software adds for itself, and no entry that refuses to be
removed, including the last one.

---

## The reserve, no variables yet

`Reserve` reads no environment variable. A reserve is built in code, as a
`ReserveConfiguration`: the asset and its precision, the total in whole units,
the named streams with their shares and their fixed denominators, and the
schedules an operator may choose between. The shares must add up to exactly the
total or the configuration refuses to exist.

That is a deliberate position rather than an omission. The numbers that were
compile-time constants in the bot this came from are now parameters, and where
they will be written down for an operator (variables, an admin command, or a
file) is a decision that belongs with the host that does not exist yet. What is
already true: the denominators are fixed in advance and never the eligible
count, and an unclaimed slot stays unclaimed rather than enlarging anybody
else's payment.

---

## Where a numbered list ends

Every list in this package is numbered from 1 and **ends at the first gap**.
This is the rule most likely to surprise somebody editing a file that already
works, so it is worth being exact about.

Lists that behave this way: `TIER_n_`, `COLLECTION_n_`,
`COLLECTION_n_COUNT_m_`, `POOL_n_`, `TOKEN_LINK_n_` and `ADMIN_WALLET_n`.

**What starts an entry.** One variable per list decides whether entry `n`
exists at all: `TIER_n_NAME`, `COLLECTION_n_ID`, `COLLECTION_n_COUNT_m_MIN`,
`POOL_n_ID`, `TOKEN_LINK_n_LABEL`, `ADMIN_WALLET_n`. If that one is unset or
blank, the list stops there, whatever else is set above it.

**What you get if you skip a number.** Suppose you meant four rungs and typed
the fourth as `TIER_5_NAME`. You get a three-rung ladder. Rung five is not
promoted into rung four's place, it is dropped, along with its threshold and
its role. Your `TIER_5_ROLE_ID` is in no ladder at all, so that role is not in
the managed set, so the bot will neither grant it nor take it away.

**Why dropping rather than renumbering.** The alternative, skipping the gap and
carrying on, would silently turn your rungs five and six into rungs four and
five. Everybody at the fourth threshold would be granted the fifth rung's role
and nothing anywhere would say so. A dropped rung shows up in the server within
a minute; a renumbered ladder can run for months.

**What this means when you edit a file that works.** Commenting out
`TIER_2_NAME` does not remove rung two, it removes rungs two and upward.
Inserting a new pool as `POOL_3_` when you already have four means the old
three and four are now gone. Renumber the whole list when you add to or remove
from the middle of it, and read back what loaded rather than assuming.

**The one case that is refused instead.** Lists are scanned to 32 entries, which
is a stop on a malformed file rather than a product limit. If your list runs
unbroken from 1 to 32 and something is also set at 33, that is refused, naming
the 33rd variable. It is refused there and only there because the loader is
handed a lookup rather than a list it can enumerate: it can ask about one more
name, not about everything else you wrote. So a list that runs 1 to 32 and then
34 has a gap at 33, and the gap rule governs from there.

---

## Which mistakes refuse by name, and which do not

Most misconfiguration stops the load with a message naming the variable to fix.
That is the whole design: you find out you have set it up wrong before your
members do.

### Refused, by name

| What you did | What you get |
|--------------|--------------|
| Left out a required variable | A refusal naming it and saying what it is for. This includes a **misspelled key**: `TOKN_DECIMALS` reads as `TOKEN_DECIMALS` being unset, and the refusal names `TOKEN_DECIMALS`. |
| Wrote something that is not a whole number where one is needed | A refusal quoting what you wrote. |
| Wrote a threshold, a count rung or a supply ceiling of `0` | A refusal saying why zero is not a value. |
| Wrote more than 19 decimals | A refusal: ten to that power does not fit in 64 bits. |
| Gave two rungs, collections or pools the same id, name, threshold or LP asset | A refusal naming both variables. |
| Named a rung after the no-rung label | A refusal. |
| Wrote a URL that is not `http` or `https` with a host, or a colour that is not six hex digits | A refusal naming the variable. |
| Wrote a rate below 1, a batch below 1, a persist interval of 0, or negative seconds | A refusal saying what was expected. |
| Wrote a boolean that is not one of the accepted words | A refusal, rather than a silent false. |
| Set an asset id of `0` | A refusal, because an unset variable arrives as zero and zero names the chain's own currency. |
| Left `TIER_1_NAME` unset | A refusal. There is no default ladder and never will be. |

### Not refused, and these are the ones that hurt

Everything here loads cleanly. Nothing names a variable, because from the
inside each one is indistinguishable from a choice somebody meant to make.

1. **A gap in a numbered list.** Entries above it are dropped in silence. This
   is the single most likely mistake in a hand-edited file. See the previous
   section.
2. **Any address.** `COLLECTION_n_CREATOR` and `ADMIN_WALLET_n` are strings
   compared exactly, and nothing in these loaders knows what a valid address
   looks like. One wrong character gives you a collection that matches nothing
   or an administrator who cannot administer, with no message at any point.
   Case matters.
3. **Any role id.** Any non-empty string is accepted. A placeholder you forgot
   to replace, a role id copied from another server, a digit wrong, or a role
   that sits above the bot's own role in Discord: all four load, and the first
   sign of trouble is a member who was never promoted.
4. **A role variable you mistyped.** A tier with no role, a collection with no
   badge and a pool with no badge are all legitimate setups, so an unset role
   cannot be told apart from a deliberate one. The ladder's loader keeps a list
   of rungs with no role for a boot report to print; there is no boot report
   yet.
5. **The wrong network.** A node URL for a test network loads perfectly, and
   every member reads as holding nothing. `CHAIN_VERIFY_ASSET_DECIMALS` catches
   the case where the asset is missing or has different precision there, and it
   cannot catch an asset that exists on both with the same precision, and today
   nothing calls it.
6. **A threshold written in smallest units.** `TIER_1_MIN` is whole tokens. Six
   extra zeros is not refused, it is a rung nobody reaches. Too many zeros
   saturate rather than wrapping, which is deliberate: an unreachable rung is
   visible and fixable, a wrapped one is a rung everybody reaches.
7. **A match rule that is too broad.** No `NAME_PREFIX` and no `UNIT_NAME`
   means every asset that creator minted within the supply ceiling counts. When
   two collections both match, the earlier one wins and the later one appears
   to do nothing.
8. **`COLLECTION_n_MAX_SUPPLY` left at 1** for a collection minted in editions.
   Nothing matches, and every holder loses the role at the next sweep.
9. **A wrong `CHAIN_API_TOKEN`.** Not checked at load. Reads fail at runtime and
   a quota refusal pauses the budget.
10. **`CHAIN_DAILY_REQUEST_BUDGET` left at `0`.** That is no budget rather than
    a small one, which is the right default for somebody who has not chosen,
    and the wrong setting for almost everybody on a metered plan.

If you take one habit from this document, take this one: after a change, read
back what actually loaded rather than the file you wrote.

---

## A worked example

A small community: one token, one collection, three tiers, no pools, no
payouts. Every value is obviously fake, and the file is complete enough to load
through the real loaders. It was loaded that way while this section was
written, and every figure below came from that run. Nothing re-runs it yet:
see "Checking it yourself" below, which says plainly what does not exist.

The role ids and addresses below are deliberately words rather than the long
numbers and 58-character addresses they should be. Nothing validates either, so
a placeholder left in loads perfectly, and one that reads `REPLACE_WITH` is at
least visible when you look.

Keep comments on their own lines. Not every loader of a `.env` file strips a
comment that trails a value, and a threshold that reads `1000 # bronze` is not
a number.

```dotenv
# ---------------------------------------------------------------------------
# The token. Read the decimals off your asset; do not guess.
# ---------------------------------------------------------------------------
TOKEN_ASSET_ID=7001
TOKEN_SYMBOL=EXMPL
TOKEN_NAME=Example Token
TOKEN_DECIMALS=6
TOKEN_LOGO_URL=https://example.com/exmpl/logo.png
TOKEN_CARD_COLOR=#3355ff
TOKEN_LINK_1_LABEL=Explorer
TOKEN_LINK_1_URL=https://example.com/asset/7001

# ---------------------------------------------------------------------------
# The ladder. Thresholds are whole tokens. Rungs stack.
# ---------------------------------------------------------------------------
TIER_1_NAME=Bronze
TIER_1_ID=bronze
TIER_1_MIN=1_000
TIER_1_ROLE_ID=REPLACE_WITH_ROLE_ID_BRONZE
TIER_2_NAME=Silver
TIER_2_ID=silver
TIER_2_MIN=10_000
TIER_2_ROLE_ID=REPLACE_WITH_ROLE_ID_SILVER
TIER_3_NAME=Gold
TIER_3_ID=gold
TIER_3_MIN=100_000
TIER_3_ROLE_ID=REPLACE_WITH_ROLE_ID_GOLD
TIER_UNRANKED_NAME=Guest

# ---------------------------------------------------------------------------
# One collection: a badge for holding a pass, another for holding five.
# ---------------------------------------------------------------------------
COLLECTION_1_ID=passes
COLLECTION_1_NAME=Example Passes
COLLECTION_1_CREATOR=REPLACE_WITH_CREATOR_ADDRESS
COLLECTION_1_UNIT_NAME=pass
COLLECTION_1_ROLE_ID=REPLACE_WITH_ROLE_ID_PASS
COLLECTION_1_COUNT_1_MIN=5
COLLECTION_1_COUNT_1_ROLE_ID=REPLACE_WITH_ROLE_ID_PASS_FIVE

# ---------------------------------------------------------------------------
# Having verified at all, and who may administer by signing.
# ---------------------------------------------------------------------------
VERIFIED_ROLE_ID=REPLACE_WITH_ROLE_ID_VERIFIED
ADMIN_WALLET_1=REPLACE_WITH_ADMIN_ADDRESS

# ---------------------------------------------------------------------------
# The node and the three brakes. Set the budget below what your plan allows;
# the share does nothing without it.
# ---------------------------------------------------------------------------
CHAIN_NODE_URL=https://node.example.com
CHAIN_REQUESTS_PER_SECOND=5
CHAIN_DAILY_REQUEST_BUDGET=20_000
CHAIN_BATCH_SIZE=25
CHAIN_CALLER_SHARE_PERCENT=5
CHAIN_CALLER_BURST_REQUESTS=10
```

### What that file produces

Loaded through `GatingConfiguration.load` and `ChainConfiguration.load`:

- A token of asset 7001 called `EXMPL`, six decimals, so one whole token is
  1,000,000 smallest units, with one link and a card colour.
- Three rungs, `bronze`, `silver` and `gold`, at 1,000,000,000, 10,000,000,000
  and 100,000,000,000 smallest units. A member below the first is a `Guest`.
- One collection, `passes`, matching pieces of supply 1 from one creator with
  the unit name `pass`, granting a badge for one and a second badge for five.
- No pools, and therefore no provider badge, which is why the ladder is decided
  from the direct balance alone rather than waiting for a pooled half that
  nobody will ever read.
- Six roles the bot may ever touch: three rungs, two collection badges and the
  verified role. Everything else in the server is somebody else's.
- One administrator, and a node read at 5 requests per second with 20,000
  requests a day, 25 accounts to a batch. The counter is written every 25
  requests and the asset's decimals are checked against the chain, both by
  default.
- One member may draw 1,000 of those 20,000 requests across the day, and no
  more than 10 of them at once before their allowance has to refill. The
  sweep, and anything else the instance does for itself, is not held to that
  share.

### Checking it yourself

Not yet, and that is a gap worth naming rather than leaving for you to find.

The example above was loaded through the real loaders while this document was
written, and every figure in the list came from that run rather than from
somebody reading the code and writing down what they expected. But nothing
re-runs it. A worked example in a document is a promise somebody will copy,
and the only kind of promise worth making is one that breaks the build when it
stops being true.

The suite that closes this reads the block out of this file rather than
holding its own copy, loads it, checks each figure, and takes each required
variable out in turn to check the refusal names it. It is a defined piece of
work rather than an intention: see the change workspace under `.specsync/`.
Until it exists, treat the numbers in this section as true on the day they
were written.
