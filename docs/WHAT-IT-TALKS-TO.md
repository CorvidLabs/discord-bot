# What it talks to

Everything this package reaches over a network, and every secret it asks for,
in one place, so the decision to install it can be made by reading rather than
by running it. That is criterion
[TRUST-1](../hi/trust.md), and this file is where it is answered.

Two things are worth knowing before the lists.

**This is derived from the code, not from memory.** Every claim below has a
command beside it that checks it, and the commands are meant to be run against
your own clone rather than believed.

**It describes this commit only.** The package is four offline libraries with
no bot around them yet, so the honest list is much shorter than the one this
document will have to carry when there is a Discord gateway and a database. A
short true list is worth more than a long plausible one.

## The short version

| Question | Answer, at this commit |
|----------|------------------------|
| How many hosts does it contact? | One, and you choose it. A second is reachable only by a host that passes it a URL, and no such host exists yet. |
| Which one? | Whatever you put in `CHAIN_NODE_URL`. There is no default and no fallback. |
| Is any hostname compiled in? | No. Not one, anywhere in `Sources/`. |
| Does it report anything to whoever wrote it? | No. No analytics, no telemetry, no crash reporting, no update check, no licence check. |
| Does it write to disk? | Nothing in `Sources/` opens a file: no database, no log, no cache of its own. Foundation's URL loading keeps an HTTP cache and a cookie store of its own, which belongs to `URLSession` rather than to this code. |
| Does it need a secret? | One, optionally: `CHAIN_API_TOKEN`, if your node provider issues tokens. |
| Does it talk to Discord? | No. There is no Discord code in the package yet. |
| Does it sign or send a transaction? | No. Every chain call is a read. Nothing here holds a key. |

## What is in the package

Four libraries. One of them contains code that opens a connection.

| Target | Dependencies | Contains a call that opens a connection? |
|--------|--------------|------------------------------------------|
| `Reserve` | Foundation | No |
| `Gating` | Foundation | No |
| `Games` | Foundation | No |
| `Chain` | Foundation, `Gating`, `swift-algorand` | Yes, and it is the only one |

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

Two honest qualifications:

- The URL and the headers are both parameters. This repository never chooses
  them, because nothing in this repository constructs one. It is a public type
  waiting for a host that does not exist yet.
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
# No analytics, telemetry, crash reporting or update check.
grep -rniE "analytic|telemetr|crashlytic|sentry|posthog|mixpanel|amplitude|datadog|segment\.io|phone.?home" Sources/

# No subprocesses, no sockets of its own.
grep -rnE "Process\(|NWConnection|Socket|CFSocket" Sources/

# No filesystem: it does not even write a log.
grep -rnE "FileManager|write\(to|Data\(contentsOf|FileHandle" Sources/
```

All three come back empty at this commit.

The package also has nothing that runs at startup, because it has no startup:
there is no executable target, so there is no moment at which it could fetch
anything before you called into it. That is half of TRUST-4.a for free, and it
stops being free the day an executable lands.

What the package does **not** yet have is the other half of TRUST-1.a: a way to
ask a running instance what it has actually been reaching. `ChainHealth`
carries proof of which provider served the last probe, which is the beginning
of one, but there is no surface that reports it, because there is nothing
running to report it to. Until there is, the checkable part of the claim is the
greps above and an egress rule on your own network.

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

There is nothing to run yet, so today that goes as far as `swift test`, which
passes with no network at all. It becomes the real check the day an executable
target lands, and it should be the first thing anybody does with one.

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
