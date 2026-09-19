# What it talks to

Everything this package reaches over a network, and every secret it asks for,
in one place, so the decision to install it can be made by reading rather than
by running it. That is criterion
[TRUST-1](../hi/trust.md), and this file is where it is answered.

Two things are worth knowing before the lists.

**This is derived from the code, not from memory.** Every claim below has a
command beside it that checks it, and the commands are meant to be run against
your own clone rather than believed.

**It describes this commit only.** The package is seven libraries and one
program. The program starts, opens a store on your disk, reads one node and
listens on one socket of your own machine; it has no Discord gateway, no
verification flow and nothing that can move value. A short true list is worth
more than a long plausible one.

## The short version

| Question | Answer, at this commit |
|----------|------------------------|
| How many hosts does it contact? | One, and you choose it. A second is reachable only by a host that passes it a URL, and no such host exists yet. |
| Which one? | Whatever you put in `CHAIN_NODE_URL`. There is no default and no fallback. |
| Is any hostname compiled in? | No. Not one, anywhere in `Sources/`. |
| Does it report anything to whoever wrote it? | No. No analytics, no telemetry, no crash reporting, no update check, no licence check. |
| Does it write to disk? | Yes, in one place you choose: the store at `STORE_PATH`, and a lock file beside it. Nothing else: no log file, no cache of its own. Foundation's URL loading keeps an HTTP cache and a cookie store of its own, which belongs to `URLSession` rather than to this code. |
| Does it listen on a socket? | Yes, one: `GET /health`, on `HEALTH_ADDRESS` (the loopback address unless you say otherwise) and `HEALTH_PORT` (required, no default). One route, nothing else, and it accepts no input beyond the request line. |
| Does it need a secret? | One, optionally: `CHAIN_API_TOKEN`, if your node provider issues tokens. |
| Does it talk to Discord? | No. There is no Discord code in the package yet. |
| Does it sign or send a transaction? | No. Every chain call is a read. Nothing here holds a key. |

## What is in the package

Seven libraries and one executable. One library contains code that opens an
outbound connection, and one contains code that accepts an inbound one.

| Target | Dependencies | Contains a call that opens a connection? |
|--------|--------------|------------------------------------------|
| `Reserve` | Foundation | No |
| `Gating` | Foundation | No |
| `Games` | Foundation | No |
| `Chain` | Foundation, `Gating`, `swift-algorand` | Yes, and it is the only one that makes one |
| `Store` | Foundation, `Reserve`, `Gating`, `Chain` | No |
| `StoreSQLite` | `Store`, `CSQLite` (the platform's own `libsqlite3`) | No. It opens a file, not a connection |
| `Runtime` | `Gating`, `Chain`, `Store` | It **accepts** one: the health listener binds a socket on your machine. It originates none |
| `BotMain` | `Runtime`, `StoreSQLite` | No. It is the arguments, the environment, the signals and the exit |

It is worth being careful about what that table proves. "It only imports
Foundation" is **not** a guarantee on its own: Foundation carries URL loading
with it on Apple platforms, so a target that imports nothing else could still
open a connection if somebody wrote the code. What is checkable is that
nobody has, and the grep under
[Outbound calls](#outbound-calls-the-complete-list) is what checks it.

```bash
# The dependency lists above, from the manifest rather than from this table.
grep -n "dependencies:" -A8 Package.swift
```

## Outbound calls, the complete list

Two call sites in this repository can put a packet on the wire, and both are
in `Sources/Chain`. One is aimed at the node URL you configured. The other is
aimed at whatever URL a caller hands it, and nothing in this repository hands
it one.

### 1. Reading an account or an asset

`Sources/Chain/NodeAccountDataSource.swift` holds an `AlgodClient` from
`swift-algorand` and calls two methods on it.

| What | Request | Sent with it |
|------|---------|--------------|
| What an account holds | `GET {CHAIN_NODE_URL}/v2/accounts/{address}` | `CHAIN_API_TOKEN`, when set, as the `X-Algo-API-Token` request header |
| An asset's details | `GET {CHAIN_NODE_URL}/v2/assets/{asset id}` | the same |

Both are reads. There is no `POST`, no transaction submission and no key
material anywhere in this repository, so there is nothing it could sign even
if it tried.

Being exact about that, because it is the kind of sentence somebody will rely
on: the client underneath **can** submit a transaction, and this repository
never calls the method that does. That is a claim about call sites, and it is
the strongest claim a reader of this repository is entitled to.

```bash
# The only two node methods reached from here.
grep -n "client\." Sources/Chain/NodeAccountDataSource.swift
```

Two brakes sit in front of these, which is worth saying in a document about
what a thing talks to: a per-second rate limiter
(`CHAIN_REQUESTS_PER_SECOND`) and a per-UTC-day request budget
(`CHAIN_DAILY_REQUEST_BUDGET`). The budget is a cap on how many requests a day
this may make at all, so the traffic this generates is bounded by a number you
set rather than by how busy your server gets.

### 2. The provider proof probe

`Sources/Chain/ProviderProofProbe.swift` contains `URLSessionHeaderProbe`,
which makes one plain `GET` to a URL its caller hands it and reads the response
headers off it. It exists so a health answer can carry evidence of which
provider actually served a request, rather than asserting it.

Three honest qualifications:

- **It is off unless you switch it on.** `Sources/BotMain/LiveSeams.swift` is
  the one place in the repository that constructs one, and it returns nil
  unless `CHAIN_PROOF_HEADERS` names at least one header. With that variable
  unset, no probe exists and no second request is ever made.
- **When it is on, it goes to the node you configured.** The URL is
  `{CHAIN_NODE_URL}/v2/status`, with your `CHAIN_API_TOKEN` as the
  `X-Algo-API-Token` header when you set one. No other host, and no fifth
  variable to point it anywhere else.
- It is the one place in the package that uses `URLSession.shared` rather than
  a session of its own.
- It is also the **only** network call anywhere on the health path, and it is
  outside the day's request budget on purpose: a check that spent the thing it
  is checking on is a check nobody can run at the moment it matters. Assembling
  a health answer waits on no request. The answer takes proof from what the
  probe already holds through `heldProof`, which never goes and gets some, and
  where nothing usable is held one probe is started **beside** the answer, so
  the next check has proof and this one still costs nothing. An instance whose
  operator named no proof headers opens no socket of any kind, and a provider
  that is down is probed once per cache lifetime rather than once per check.

It is refreshed **off** the health request path and never on it, so answering a
health check makes no request at all. It is also not on a timer: the runtime
probes once when it finishes starting, and after that only when a health
request has been answered since the last probe, which
`CHAIN_HEALTH_PROBE_CACHE_SECONDS` then reduces to at most one probe per that
many seconds. An instance nobody ever checks makes one probe for its whole
life.

Two commands, not one, and the reason is worth a sentence: grepping for
`URLSession` alone would miss the account reads entirely, because those go out
through the node client rather than through a session this repository holds.
A disclosure that checks only the obvious half is how a call gets missed.

```bash
# The only place this repository touches URLSession directly: the probe.
grep -rn "URLSession" Sources/

# The other way out: the one place a node client is built.
grep -rn "AlgodClient(" Sources/

# Every hardcoded host. Expect one hit, and it is a comment about URL schemes.
grep -rn "://" Sources/
```

## Nothing phones home

The claim costs nothing to make, so here is how to check it instead.

```bash
# No analytics, telemetry, crash reporting or update check. The alternatives
# are anchored to whole words, because an unanchored `sentry` matches inside
# `SettingsEntry` and a disclosure that cries wolf teaches you to stop reading
# it.
grep -rniE "analytic|telemetr|crashlytic|\bsentry\b|posthog|mixpanel|amplitude|datadog|segment\.io|phone.?home" Sources/

# No subprocesses. Anchored for the same reason: `Process\(` on its own
# matches `alreadyHeldByAnotherProcess(`, which is a store lease.
grep -rnE "\bProcess\(|NWConnection|CFSocket" Sources/

# Every socket call, so the one listener is countable rather than assumed.
grep -rn "socket(" Sources/

# Every file the package opens, and the paths it opens them at.
grep -rnE "FileManager|FileHandle|Data\(contentsOf" Sources/
```

The first two come back empty. The third finds one file,
`Sources/Runtime/HealthListener.swift`, which is the one listener; the client
that speaks to it over loopback is test code and lives under `Tests/`, which
these commands do not scan. The fourth finds the store's own file handling and
the report writing to standard output and standard error.

**There is a startup now**, and this is what it does before you have typed
anything else: it prints a report of what it made of your settings as it makes
it, opens the store at `STORE_PATH`, takes an exclusive lock on a file beside
it, binds `HEALTH_PORT` on `HEALTH_ADDRESS`, and makes **one** request to your
node to check that the asset exists and has the precision you configured.
`CHAIN_VERIFY_ASSET_DECIMALS=false` turns that one off.

A start makes at most one other outbound call, and only if you asked for it:
when `CHAIN_PROOF_HEADERS` names a header, the provider proof probe above makes
its first `GET {CHAIN_NODE_URL}/v2/status` as the runtime finishes starting.
With that variable unset, which is the default, the asset check is the only
outbound call a start makes at all. It fetches nothing else, checks for no
update and asks no licence server anything, which is TRUST-4.a.

The other half of TRUST-1.a is now answered too: `GET /health` on the address
above tells a running instance's operator what it has actually reached, and
copies the provider proof headers onto its answer when you have configured any.
The checkable part of the claim is still the greps above and an egress rule on
your own network.

## Secrets, and everything else it reads

The package reads its configuration from environment variables and from nowhere
else. There is no config file, no remote configuration and no default that
somebody other than you chose: a required variable that is missing is a refusal
that names the variable, never a value filled in on your behalf.

Exactly one of these is a secret.

### Secret

| Variable | Read by | What it is |
|----------|---------|------------|
| `CHAIN_API_TOKEN` | `Chain` | Your node provider's API token, when the provider needs one. Sent to the node in `CHAIN_NODE_URL` and to nowhere else. Unset is fine for a node that does not ask for one. |

### This process

| Variable | Required | What it is |
|----------|----------|------------|
| `STORE_PATH` | yes | Where this instance keeps what it remembers. **Absolute**, because a supervisor restarting the process from another directory would otherwise open a different and empty store. A lock file is created beside it. |
| `HEALTH_PORT` | yes | The port the health endpoint listens on. No default: several communities on one machine each need their own, and a shared default turns the second one's first start into a clash. Zero lets the operating system choose. |
| `HEALTH_ADDRESS` | no | The address the health endpoint binds. The loopback address unless you set it, because the answer carries a waiting list and can carry provider proof headers, and a default of every interface would publish both. |

None of these is a secret.

### The node and the two brakes

| Variable | Required | What it is |
|----------|----------|------------|
| `CHAIN_NODE_URL` | yes | The node to read from. Absolute `http` or `https`. The only host the package contacts. |
| `CHAIN_PROOF_HEADERS` | no | Response header names to copy onto a health answer as proof of which provider served it. Comma separated. |
| `CHAIN_REQUESTS_PER_SECOND` | no | What the rate limiter allows. |
| `CHAIN_DAILY_REQUEST_BUDGET` | no | Requests permitted per UTC day. Zero means no budget. |
| `CHAIN_BUDGET_PERSIST_EVERY` | no | How many requests pass between writes of the day's counter. |
| `CHAIN_BATCH_SIZE` | no | How many accounts are read in parallel. |
| `CHAIN_CALLER_SHARE_PERCENT` | no | The share of the day's requests any one member may draw, as a percentage. Defaults to 5, and does nothing unless a day budget is set. |
| `CHAIN_CALLER_BURST_REQUESTS` | no | The most one member may take before their allowance refills. Defaults to 10, and does nothing unless a day budget is set. |
| `CHAIN_POOL_CACHE_SECONDS` | no | How long a pool's reserves stay usable. |
| `CHAIN_WALLET_CACHE_SECONDS` | no | How long a completed account reading stays usable. |
| `CHAIN_WALLET_COOLDOWN_SECONDS` | no | How soon the same account may be read again on demand. |
| `CHAIN_HEALTH_PROBE_CACHE_SECONDS` | no | How long a health probe's answer is reused. |
| `CHAIN_VERIFY_ASSET_DECIMALS` | no | Whether to read the asset's decimals from the chain at boot and refuse to start when they disagree with `TOKEN_DECIMALS`. On by default. |

### Your token

| Variable | Required | What it is |
|----------|----------|------------|
| `TOKEN_ASSET_ID` | yes | The asset your holder ladder is measured in. |
| `TOKEN_SYMBOL` | yes | The ticker shown beside an amount. |
| `TOKEN_DECIMALS` | yes | Its precision. Every threshold is converted through it. |
| `TOKEN_NAME` | no | The longer name. |
| `TOKEN_LOGO_URL` | no | A thumbnail for a card. **Stored and never fetched by this package**; a future Discord surface would hand the URL to Discord, which is what fetches it. |
| `TOKEN_CARD_COLOR` | no | A card's colour. |
| `TOKEN_LINK_n_LABEL`, `TOKEN_LINK_n_URL` | no | Links shown to a member, numbered from 1. Stored and never fetched. |

### Roles, tiers, collections, pools, administrators

None of these reaches anything. They are read at load, checked, and turned into
values. They are listed here because TRUST-1 asks for everything the package
asks you for, not only the parts that touch a network.

| Variable | What it is |
|----------|------------|
| `VERIFIED_ROLE_ID` | The role for having verified an account. |
| `TIER_n_NAME`, `TIER_n_MIN`, `TIER_n_EMOJI`, `TIER_n_ID`, `TIER_n_ROLE_ID` | One rung of the holder ladder, numbered from 1. |
| `TIER_UNRANKED_NAME`, `TIER_UNRANKED_EMOJI` | What a member below the first rung is called. |
| `COLLECTION_n_ID`, `COLLECTION_n_CREATOR` | A collection, numbered from 1. The creator is required: it is how a piece of your collection is told apart from every other asset on chain. |
| `COLLECTION_n_NAME`, `COLLECTION_n_NAME_PREFIX`, `COLLECTION_n_UNIT_NAME`, `COLLECTION_n_MAX_SUPPLY`, `COLLECTION_n_ROLE_ID` | The rest of one collection. |
| `COLLECTION_n_COUNT_m_MIN`, `COLLECTION_n_COUNT_m_ROLE_ID` | A stacked rung for holding several pieces of collection `n`. |
| `LP_PROVIDER_ROLE_ID` | The badge for having any liquidity position. |
| `POOL_n_ID`, `POOL_n_LP_ASA`, `POOL_n_PAIRED_ASA`, `POOL_n_DECIMALS` | A liquidity pool, numbered from 1. All four required once the pool exists. |
| `POOL_n_NAME`, `POOL_n_ROLE_ID` | The rest of one pool. |
| `ADMIN_WALLET_n` | An account allowed to administer by signing, numbered from 1. The list starts empty and nobody is on it who was not put there by you. |

```bash
# Every all-caps literal in the source. This is a superset of the tables
# above, not a match for them: a few hits are not variables at all, such as an
# HTTP method and a set of suffix letters used in formatting. A superset you
# can read beats a list you have to trust.
grep -rnoE '"[A-Z][A-Z0-9_]{2,}"' Sources/ | sort -u
```

## What this document cannot tell you

This is the part worth reading twice, because a disclosure that admits its
limits is the only kind that can be trusted at all.

**A grep of this repository cannot see inside a dependency.** Everything above
is about call sites in `Sources/`. A dependency can open a connection this
repository never wrote, and no amount of reading these four targets would show
it.

The package has one direct dependency and two that arrive with it. These are
the versions in `Package.resolved`, which is committed, so your build uses
exactly these:

| Package | Version | Why it is here |
|---------|---------|----------------|
| `swift-algorand` | 0.4.0 | The node client, and the address and asset types. The only dependency `Chain` calls. |
| `swift-crypto` | 3.15.1 | Arrives with `swift-algorand`, which uses it for signing primitives. |
| `swift-asn1` | 1.7.3 | Arrives with `swift-crypto`. |

Three specific things a reader should know rather than assume:

1. **`swift-algorand` ships default endpoint constants** pointing at a public
   node provider's mainnet and testnet endpoints. This package never selects
   them: `NodeAccountDataSource` only ever builds a client with an explicit
   base URL, and that URL comes from `CHAIN_NODE_URL`, which is required and
   has no default. You can check both halves:

   ```bash
   # This repository never constructs a client without an explicit URL.
   grep -rn "AlgodClient(" Sources/

   # The defaults that exist in the dependency and are never reached from
   # here. Run `swift build` first: that is when the checkout appears.
   grep -rn "https://" .build/checkouts/swift-algorand/Sources/
   ```

2. **`swift-crypto` and `swift-asn1` are Apple's, and neither does networking**,
   but at this commit that is something you are being told rather than
   something this document has proved to you. Reading them is a real amount of
   work, and saying so is more useful than a checkmark.

3. **Foundation itself resolves DNS, honours proxy settings and reads the
   system trust store.** `URLSession` behaves the way the machine it runs on is
   configured to behave. Nothing here changes that, and nothing here can
   promise anything about it. It also keeps an HTTP cache and a cookie store
   by default: the node client builds its session from
   `URLSessionConfiguration.default` and turns off neither, so "this package
   writes no files" is true of the code in `Sources/` and not of the process
   as a whole.

**The way to actually be sure is not to read anything.** Run it with an egress
rule that permits your node's host and nothing else. If the list above is
complete, nothing breaks. That test does not require trusting this file, the
dependency, or the person who wrote either, which is the point.

`swift test` passes with no network at all, and there is now a binary to point
an egress rule at. Run `bot check` first, which loads your settings and touches
nothing, then `bot run` behind the rule. If the list above is complete, the only
thing that fails is nothing.

## When this changes

TRUST-1.b is that a new thing this reaches should be a change you can see
between two versions, rather than something that appears quietly in one.

So: a pull request that adds an outbound call, a new host, a new dependency or
a new secret changes this file in the same pull request, and the change is
named in [`CHANGELOG.md`](../CHANGELOG.md) under the release it ships in. A
dependency bump that widens what the graph can reach is the same kind of change
and gets the same treatment, which is part of why `Package.resolved` is
committed and the version range is narrow: a new transitive dependency cannot
arrive without a diff.
