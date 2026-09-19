# What it talks to

Everything this package reaches over a network, and every secret it asks for,
in one place, so the decision to install it can be made by reading rather than
by running it. That is criterion
[TRUST-1](../hi/trust.md), and this file is where it is answered.

Two things are worth knowing before the lists.

**This is derived from the code, not from memory.** Every claim below has a
command beside it that checks it, and the commands are meant to be run against
your own clone rather than believed.

**It describes this commit only, and it describes two things.** The
**program** you can run today opens a store on your disk, reads one Algorand
node and listens on one socket of your own machine. The **package** also
contains a Discord adapter, built and tested, that would open a gateway, call
a chat API and call a verification portal you run — and the `bot` executable
does not link it, so none of that happens when you start the program. Where
the two differ below, the difference is said rather than smoothed over: a
short true list is worth more than a long plausible one.

## The short version

| Question | Answer, at this commit |
|----------|------------------------|
| How many hosts does it contact? | Three kinds. Discord, which is fixed. Your chain node, which you choose. Your verification portal, which you run and which is optional. |
| Which ones exactly? | `discord.com` and `gateway.discord.gg`, reached by the chat library; whatever you put in `CHAIN_NODE_URL`; whatever you put in `VERIFY_PORTAL_URL`. |
| Is any hostname compiled in? | One, in one place: the `discord.com` invite URL the boot report prints. It is printed, never fetched. The chat library holds Discord's own API and gateway hosts, which is what a chat library is. |
| Does it report anything to whoever wrote it? | No. No analytics, no telemetry, no crash reporting, no update check, no licence check. |
| Does it write to disk? | Yes, in one place you choose: the store at `STORE_PATH`, and a lock file beside it. There is no default, because a database somewhere this package chose is a database you do not know to back up. Nothing else: no log file, no cache of its own. Foundation's URL loading keeps an HTTP cache and a cookie store of its own, which belongs to `URLSession` rather than to this code. |
| Does it listen on a socket? | The program: one, `GET /health`, on `HEALTH_ADDRESS` (the loopback address unless you say otherwise) and `HEALTH_PORT` (required, no default). One route, and it accepts no input beyond the request line. The package holds a second listener, the portal callback in `SurfaceDiscord`, which nothing in this build starts. |
| Does it need a secret? | The program: one, optionally, `CHAIN_API_TOKEN`, if your node provider issues tokens. The unwired surface would ask for two more, `DISCORD_BOT_TOKEN` and `VERIFY_SHARED_SECRET`. |
| Does it talk to Discord? | Not when you run it. `SurfaceDiscord` is the only target that can, the manifest is what makes that true, and no executable links it. |
| Does proving a wallet contact anything? | No. `Verify` checks the signature in this process and opens no connection. A page has to serve the member's wallet somewhere, and this package does not serve one. |
| Will that stay true? | One host is already decided and not yet reached: a naming service, so a member can type a name instead of an address when they run the verification command. It is optional, it is contacted only when somebody types a name, nothing at startup depends on it, and `Verify` is not the target that will call it. Nothing in this commit reaches it. |
| Does it sign or send a transaction? | No. Every chain call is a read. Nothing here holds a chain key. |

## What is in the package

Thirteen targets. Three of them contain code that opens or accepts a
connection, one writes a file, and the executable links four.

| Target | Dependencies | Opens or accepts a connection? |
|--------|--------------|--------------------------------|
| `Reserve` | Foundation | No |
| `Gating` | Foundation | No |
| `Games` | Foundation | No |
| `Chain` | Foundation, `Gating`, `swift-algorand` | Yes, outbound to your node, and it is the only one the program reaches |
| `Store` | Foundation, `Reserve`, `Gating`, `Chain` | No |
| `StoreTestKit` | `Store` | No |
| `StoreSQLite` | `Store`, `CSQLite` (the platform's own `libsqlite3`) | No. It opens a file, not a connection |
| `Runtime` | `Gating`, `Chain`, `Store` | It **accepts** one: the health listener binds a socket on your machine. It originates none |
| `Verify` | Foundation, `swift-algorand`, `swift-crypto` | No. It is one import away from a node client, which is the position `Chain` is also in, and `Tests/VerifyTests/TargetShapeTests.swift` reads its sources and proves no client is constructed, no request type is named and nothing is logged. |
| `Surface` | Foundation, `Store`, `Gating`, `Chain` | No. It declares no chat client and opens nothing. |
| `SurfaceDiscord` | `Surface`, `Store`, `Gating`, `Chain`, `DiscordBM` | Yes: the gateway, the chat API, your portal, and a listening socket. **Nothing links this target**, so none of that runs. |
| `BotMain` (the `bot` executable) | `Runtime`, `StoreSQLite` | No. It is the arguments, the environment, the signals and the exit |

Two things in that table are worth checking for yourself, because the rest of
this document leans on them. The first is the split between `Surface` and
`SurfaceDiscord`: the rules and the handlers are in a target that does not
list the chat library at all. The second is what the executable actually
links, which is the reason every Discord row above is written in the
conditional.

```bash
# The chat library is named once in the manifest, on one target.
grep -n "DiscordBM" Package.swift

# And imported under one directory.
grep -rn "^import DiscordBM" Sources/

# What the executable links. Neither surface target is in it.
grep -n 'name: "BotMain"' -A2 Package.swift
```

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

Four kinds of call can put a packet on the wire.

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

### 2. Discord

`Sources/SurfaceDiscord` holds the chat library and is the only target that
does. This repository never writes a Discord hostname: the library holds
Discord's own API host and its gateway host, and every call below goes
through it.

| What | When | Sent with it |
|------|------|--------------|
| Replace this server's slash commands | Once, at boot, after the ports are bound and before the gateway is identified | `DISCORD_BOT_TOKEN` |
| A websocket to the gateway | Once, at boot, and re-established by the library when it drops | `DISCORD_BOT_TOKEN` |
| Answer, defer, follow up or edit an interaction | Whenever a member runs a command or presses a button | `DISCORD_BOT_TOKEN` |
| Read one member's roles, and set them | On a verification callback and on `/unlink` | `DISCORD_BOT_TOKEN` |

The gateway the executable opens asks for one intent, `guilds`. Nothing is
asked for that nothing reads: `guildMembers` is privileged, and an
application that has not been granted it in the developer portal has its
websocket closed while the slash-command registration succeeds, so the boot
passes and the bot then answers nothing. It comes back with the leave event
that needs it. Deliberately **not** `guildMessages` and not message content
either: reading every message in a server is a permission this bot has no use
for.

```bash
# Every chat API method this repository calls.
grep -rnE "client\.[a-zA-Z]+\(" Sources/SurfaceDiscord/

# The intents asked for, by both of the boots in the tree.
grep -rn "intents:" Sources/SurfaceDiscord/
```

### 3. Your verification portal

`Sources/SurfaceDiscord/HTTPVerificationClient.swift` makes four calls, all
to `VERIFY_PORTAL_URL` and to nowhere else. The contract is
[`VERIFICATION.md`](VERIFICATION.md).

| What | Request | Sent with it |
|------|---------|--------------|
| Is it up | `GET {VERIFY_PORTAL_URL}/health` | nothing |
| Do we agree on the secret | `GET {VERIFY_PORTAL_URL}/api/v1/verification/health` | `VERIFY_SHARED_SECRET` as `X-API-Key` |
| Has this member an account | `GET {VERIFY_PORTAL_URL}/api/v1/verification/{id}?guildId=…` | the same |
| Make a link | `POST {VERIFY_PORTAL_URL}/api/v1/verification` | the same |
| Unlink | `DELETE {VERIFY_PORTAL_URL}/api/v1/verification/{id}?guildId=…` | the same |

With no `VERIFY_PORTAL_URL` set, none of these exists: verification is
switched off, `/verify` and `/unlink` are not registered, and nothing in your
server offers to prove an account.

```bash
# Every path this repository appends to your portal's base URL.
grep -n 'path: "' Sources/SurfaceDiscord/HTTPVerificationClient.swift
```

### 4. The provider proof probe

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
# Everywhere this repository touches URLSession directly: the probe, and the
# portal client.
grep -rn "URLSession" Sources/

# The other way out: the one place a node client is built.
grep -rn "AlgodClient(" Sources/

# Every hardcoded host. The only one is discord.com, in the invite URL the
# boot report prints and never fetches.
grep -rn "https://" Sources/ | grep -v "docs.discord\|developers.discord\|example.test"
```

## What it listens on

New at this commit, and the part an egress rule will not protect you from:
**this process accepts connections**. Two ports, both named by you, both with
no default, and both bound to `LISTEN_ADDRESS`, which defaults to `127.0.0.1`.

| Port | Route | Authenticated | What it does |
|------|-------|---------------|--------------|
| `HEALTH_PORT` | `GET /health` | no | Answers `503 {"status":"starting"}` until the gateway is ready, then a JSON object naming Discord, the store and the verification half. It reads nothing and spends no chain request. |
| `VERIFY_CALLBACK_PORT` | `GET /health` | no | The same answer. |
| `VERIFY_CALLBACK_PORT` | `POST /webhook/verification` | yes, `X-API-Key` compared in constant time | The one call your portal makes. Rate limited to ten requests per minute per source address. |

Everything else on either port is `404` and is not rate limited, so a scanner
cannot use up the budget a real callback needs.

Two properties worth knowing, because they constrain what can be sent:

- **The listener performs a single read of at most 8,192 bytes and never
  reads that socket again.** It does not consult `Content-Length`. No chunked
  transfer encoding, no `Expect: 100-continue`, no connection reuse.
- **The callback is validated before it is answered `200`.** A shared secret
  proves who sent a request, not that the request makes sense, so a foreign
  server id, a malformed member id or a malformed account is a `400` and
  nothing is written.

```bash
# The only sockets this repository creates or accepts on.
grep -rnE "socket\(|bind\(|listen\(|accept\(" Sources/

# The route table and the order its checks run in, with no socket in sight.
grep -n "case " Sources/Surface/Verify/CallbackRoute.swift
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
grep -rnE "\bProcess\(|NSTask|NWConnection|CFSocket" Sources/

# Every socket call, so the listeners are countable rather than assumed.
grep -rn "socket(" Sources/

# Every file the package opens, and the paths it opens them at.
grep -rnE "FileManager|FileHandle|Data\(contentsOf" Sources/
```

The first comes back empty. The second finds **two** files:
`Sources/Runtime/HealthListener.swift`, which the program binds, and
`Sources/SurfaceDiscord/SocketHTTPListener.swift`, which nothing links and so
nothing starts. The client that speaks to the health listener over loopback
is test code under `Tests/`, which these commands do not scan. The third
finds the store's own file handling and the report writing to standard output
and standard error.

One claim that used to be on this list and is no longer true, said plainly
rather than quietly dropped: **it writes a file**, one SQLite database at
`STORE_PATH`, through `Sources/StoreSQLite`. There is no default path.

**There is a startup now**, and this is what it does before you have typed
anything else: it prints a report of what it made of your settings as it
makes it, opens the store at `STORE_PATH`, takes an exclusive lock on a file
beside it, binds `HEALTH_PORT` on `HEALTH_ADDRESS`, and makes **one** request
to your node to check that the asset exists and has the precision you
configured. `CHAIN_VERIFY_ASSET_DECIMALS=false` turns that one off. It
contacts nothing else, and it does not reach Discord or a portal, because it
links neither target that could.

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

### Secrets

| Variable | Read by | What it is |
|----------|---------|------------|
| `DISCORD_BOT_TOKEN` | `Surface`, used by `SurfaceDiscord` | Your bot's token. Sent to Discord and to nowhere else. Required; a placeholder value refuses the boot. It is never printed: the boot report prints an invite URL built from the application id, which the token carries in plain base64 and which is not itself a secret. |
| `VERIFY_SHARED_SECRET` | `Surface`, used by `SurfaceDiscord` | The one secret both halves of verification hold. Sent to your portal as `X-API-Key`, and expected back from it on the callback. One secret, not one per direction: two is how an operator sets half of it and every `/verify` fails with a `401` nobody sees. |
| `CHAIN_API_TOKEN` | `Chain` | Your node provider's API token, when the provider needs one. Sent to the node in `CHAIN_NODE_URL` and to nowhere else. Unset is fine for a node that does not ask for one. |

### This process

| Variable | Required | What it is |
|----------|----------|------------|
| `STORE_PATH` | yes | Where this instance keeps what it remembers. **Absolute**, because a supervisor restarting the process from another directory would otherwise open a different and empty store. A lock file is created beside it. |
| `HEALTH_PORT` | yes | The port the health endpoint listens on. No default: several communities on one machine each need their own, and a shared default turns the second one's first start into a clash. Zero lets the operating system choose. |
| `HEALTH_ADDRESS` | no | The address the health endpoint binds. The loopback address unless you set it, because the answer carries a waiting list and can carry provider proof headers, and a default of every interface would publish both. |

None of these is a secret.

### The chat surface, which nothing reads yet

`Surface` reads these and the executable does not link `Surface`, so no boot
you can run today asks for any of them. They are listed because the code that
reads them is in the repository and you can grep it.

| Variable | Required | What it is |
|----------|----------|------------|
| `DISCORD_GUILD_ID` | yes | The one server this process serves. An interaction from any other is refused. |
| `DISCORD_APPLICATION_ID` | no | Your application id, for the invite URL. Read out of the token when it can be; when it cannot, the report names this variable rather than printing half a URL. |
| `DISCORD_ADMIN_ROLE_ID` | no | One extra role that may run an operator command. Unset means Administrator only, and an empty value grants nobody. |
| `VERIFY_CALLBACK_PORT` | yes | The port your portal's callback arrives on. No default. |
| `LISTEN_ADDRESS` | no | What the surface's listener binds. Defaults to `127.0.0.1`. |
| `VERIFY_PORTAL_URL` | no | Where the other half of verification lives. Unset switches verification off entirely. |
| `VERIFY_OPERATOR_NAME` | with a portal | Who runs this instance, shown to a member before they sign. |
| `VERIFY_VISIBILITY_NOTE` | with a portal | What other members will see, in your words. |
| `VERIFY_OPERATOR_CONTACT` | no | How to reach you. |
| `BOT_NAME` | no | What the bot calls itself on a card. Unset becomes a word that names no project. |

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

The package has **three** direct dependencies and 25 that arrive with
them, 28 pins in all. These are the versions in `Package.resolved`, which is
committed, so your build uses exactly these. The list is read out of that file
rather than estimated, and the command below regenerates it.

| Package | Version | Why it is here |
|---------|---------|----------------|
| `async-http-client` | 1.36.1 | With `DiscordBM`. What it makes its HTTP calls through. |
| `compress-nio` | 1.4.2 | With `DiscordBM`. Gateway compression. |
| `discordbm` | 1.16.2 | **Direct.** The chat client: the gateway, the HTTP API and the payload types. Reached only from `SurfaceDiscord`, which nothing links. |
| `multipart-kit` | 4.7.1 | With `DiscordBM`. File uploads on a message. |
| `swift-algorand` | 0.4.0 | **Direct.** The node client, and the address and asset types. The only dependency `Chain` calls. |
| `swift-algorithms` | 1.2.1 | With `DiscordBM`. |
| `swift-asn1` | 1.7.3 | With `swift-crypto`. |
| `swift-async-algorithms` | 1.1.5 | With `DiscordBM`. |
| `swift-atomics` | 1.3.1 | With NIO. |
| `swift-certificates` | 1.20.0 | With `async-http-client`. TLS certificate handling. |
| `swift-collections` | 1.6.0 | With several. |
| `swift-crypto` | 3.15.1 | **Direct.** `Verify` checks an Ed25519 signature against a public key on its own; the only signature check `swift-algorand` offers is a method on a type that holds a private key, which is precisely what that target must never hold. Also arrives with `swift-algorand` and with the TLS stack. |
| `swift-distributed-tracing` | 1.5.0 | With `async-http-client`. |
| `swift-http-structured-headers` | 1.7.0 | With the HTTP stack. |
| `swift-http-types` | 1.8.0 | With the HTTP stack. |
| `swift-log` | 1.15.1 | With `DiscordBM`. Its logging goes wherever your process sends `swift-log`. |
| `swift-nio` | 2.103.0 | With `async-http-client`. The event loop underneath everything above. |
| `swift-nio-extras` | 1.35.1 | With NIO. |
| `swift-nio-http2` | 1.46.0 | With `async-http-client`. |
| `swift-nio-ssl` | 2.37.5 | With `async-http-client`. TLS. |
| `swift-nio-transport-services` | 1.28.0 | With NIO, on Apple platforms. |
| `swift-numerics` | 1.1.1 | With `swift-algorithms`. |
| `swift-service-context` | 1.3.0 | With `swift-distributed-tracing`. |
| `swift-service-lifecycle` | 2.12.0 | With `DiscordBM`. |
| `swift-syntax` | 604.0.0 | With `DiscordBM`, for a macro used at build time. It is not in the running process. |
| `swift-system` | 1.8.1 | With NIO. |
| `swift-websocket` | 1.6.1 | With `DiscordBM`. The gateway connection. |
| `zstd` | 1.5.7 | With `compress-nio`. |

That is 25 more entries than this package had before the chat surface
landed, and saying the number is the point: `TRUST-4` is that you can see what
else comes with it, and a graph this size arriving without a diff would be
exactly the thing the narrow version range exists to prevent. Most of it is
reached only from `SurfaceDiscord`, which no executable links today — it is
compiled and tested, not run.

```bash
# The list above, from the lock file rather than from this table.
python3 -c "import json;[print(p['identity'], p['state'].get('version')) for p in sorted(json.load(open('Package.resolved'))['pins'], key=lambda x: x['identity'])]"
```

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

`swift test` passes with no network at all, and there is a binary to point an
egress rule at. Run `bot check` first, which loads your settings and touches
nothing, then `bot run` behind the rule. Today that rule only has to permit
your node: the program reaches nothing else. When the surface is wired in it
will need Discord and your portal too, and that is the moment to widen it —
not before.

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
