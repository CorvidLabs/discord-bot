---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: design
---

# Design

## The shape in one paragraph

One new library target, `Runtime`, holds everything that decides what happens
and in what order. One new executable target, `BotMain`, holds everything that
touches the machine: the environment, the arguments, the signals and the exit.
`Runtime` is handed its seams and can therefore be driven entirely from a test;
`BotMain` is the only place a live thing is constructed and is kept small
enough to read in one sitting. Between them sits a boot sequence of gates with
a fixed order, a settings catalogue that is the single description of every
variable the build reads, a startup report rendered from that catalogue, and a
health listener that binds before anything could identify to a chat service and
answers `starting` until the parts that must be up are up.

## Targets and the graph

```
BotMain (executable)  ->  Runtime, StoreSQLite
Runtime               ->  Gating, Chain, Store
Store                 ->  Reserve, Gating, Chain          (unchanged)
Chain                 ->  Gating, swift-algorand          (unchanged)
```

`Runtime` depends on `Gating`, `Chain` and `Store` and on nothing else. It
does not depend on `Games` or `Reserve`, because neither is reachable without a
surface to play on or a payer to pay with, and it does not depend on
`StoreSQLite`, because it takes `any BotStore` and the concrete durable store
is chosen in `BotMain`. `BotMain` therefore depends on `Runtime` and on
`StoreSQLite`, and on nothing else.

`Runtime` is a plain target, not a library product. A product is a promise
about an API, and the composition root is at its least stable moment: it grows
a parameter every time a surface lands. Keeping it a target means the
executable and the tests can reach it and nobody downstream can depend on its
shape. Promoting a target to a product later is a one line change and breaks
nobody; demoting one is a breaking change. The repository already has the
precedent in `StoreTestKit`, which is a target no product reaches
(`Package.swift`, the `StoreTestKit` comment).

### How "no target can see a chat client" survives an executable that must

Today the claim holds because nothing in the package imports one. Once there is
a program, four things keep it true, and three of them are the compiler's job
rather than a reviewer's.

1. **The seam lives in `Runtime`, expressed in Foundation types.** The chat
   gateway is a protocol with a role as a `String` and a member as a `String`,
   exactly as `Gating` already treats a role, so the boot sequence can say
   "connect" without any Discord type existing.
2. **The adapter, when it arrives, is its own target that depends on
   `Runtime`.** SwiftPM refuses a dependency cycle, so `Runtime` can never
   depend back on it, and `Store` is two edges further away still. This is the
   same argument the manifest already makes for `Store`: the adapter depends on
   this target, and SwiftPM refuses a cycle, so this one can never acquire it
   back.
3. **The package dependency is declared on the adapter target alone.** A target
   that does not list a package dependency cannot import its modules, so
   `import` of a chat client anywhere else is a missing module error rather
   than a review comment.
4. **The executable is the only place both are visible.** That is also what
   makes the answer to "what can this build reach" one readable function
   instead of a search.

This change adds none of the chat dependency. It adds the seam and the ordering
the seam needs, so the rule about identifying is testable before there is
anything to identify with.

## The one place that reads the process environment

`BotMain` calls `ProcessInfo.processInfo.environment` exactly once, at the top,
and turns the result into a `Settings` value. `Runtime` has no way to reach the
machine: every entry point takes `Settings` as a parameter with no default, and
nothing in the module constructs one from anywhere. A test builds one from a
dictionary literal.

A snapshot rather than a live lookup, for three reasons. Every layer then sees
the same values, so the startup report cannot describe settings a loader read
differently. A variable changed under a running process cannot half take
effect, which is the honest half of RUN-6. And reading the environment while
another thread writes it is a data race on Linux, which a single read at the
top avoids by construction.

`Settings` does one thing beyond answering the `(String) -> String?` lookup
that `TokenProfile.load`, `GatingConfiguration.load`,
`CollectionConfiguration.load`, `LiquidityConfiguration.load`,
`TierConfiguration.load` and `AdminAllowlist.load` already take: it records
every key it was asked for. That recording is what pays for two things that
would otherwise be impossible to check. A key read but not described in the
catalogue fails the boot, so an undescribed variable cannot ship. A key set,
carrying a prefix this build owns, and read by nobody is a probable typo, and
the report says so.

There is a second door onto the machine's settings in the package already:
`ChainConfiguration.loadFromProcessEnvironment(token:)` at
`Sources/Chain/ChainConfiguration.swift:165`. The root does not use it, and the
runtime contract forbids it. That prohibition is the weakest enforcement in
this design, since nothing stops a future edit writing `ProcessInfo` inside
`Runtime`, so it is backed by the one test in `SettingsSourceTests` that walks
the source directory beside its own `#filePath` and fails on a match. Worth
naming as the soft spot rather than pretending the graph covers it.

### The catalogue

One entry per variable, each carrying the name taken from the constant that
owns it rather than retyped: `TokenProfile.assetIdKey`,
`ChainEnvironment.nodeURL`, `GatingConfiguration.verifiedRoleKey`,
`LiquidityConfiguration.providerRoleKey`, `TierConfiguration.firstRungKey` and
the rest. Retyping a name is how a rename becomes a variable an operator sets
and nothing reads.

Each entry carries a purpose sentence, whether it is required, and whether its
value is a secret. Numbered families such as `TIER_n_*`, `POOL_n_*` and
`COLLECTION_n_*` are one entry describing the family, because thirty-two
entries per family would bury the report and the number thirty-two is an
implementation ceiling rather than a product statement
(`Sources/Gating/NumberedEnvironment.swift:28`).

Prefixes have three states, and the third is the interesting one.

| State | Meaning | What happens |
|-------|---------|--------------|
| Described | The build reads it | Loaded, reported |
| Reserved | A part this build does not have | **Refuses the boot**, naming the variable |
| Unowned | Somebody else's variable | Ignored, never reported |

Reserved is a refusal rather than a warning because an operator who sets a chat
token believes their members are about to see a bot. They are not. A process
that starts, answers healthy and never appears in the server is precisely the
three hour outage the SEE family opens with. The moment a surface lands, its
prefix moves from reserved to described and the refusal disappears on its own.

An unrecognised name inside an owned prefix, by contrast, is reported and not
refused. Refusing an unknown name breaks both directions of an upgrade: a
variable set in advance of a deploy, and a variable left behind by a rollback.
The report is read at every start anyway, and ADOPT-9.a asks for a dropped rung
to read as missing there rather than to stop the boot.

## The boot sequence

One ordered list, not reorderable by configuration. Each row says what it can
refuse and with which code.

| # | Gate | What it does | Refuses with |
|---|------|--------------|--------------|
| 1 | Banner | Prints whether this build can spend | never |
| 2 | Configuration | Token, gating, chain, runtime settings, all pure | 78, naming the variable |
| 3 | Store | Lease, open, migrate | 69, held or unusable |
| 4 | Budget restore | Today's request count back into the governor | 70 |
| 5 | Bind | The health listener | 69, address in use |
| 6 | Chain | The asset exists and its precision agrees | 78, only on a contradiction |
| 7 | Chat | Nothing to connect yet | 78, if a chat variable is set |
| 8 | Loops | Nothing to start yet | never |

**Why the banner is first, before the settings are even read.** BUILD-3.b says
a build that can sign says so every time it starts. A start that then refuses
is still a start, and it is the one a contributor sees most often while they
are getting their settings right.

**Why configuration before everything else.** It is the only gate that touches
nothing, so a wrong variable costs no lock, no socket and no request. The order
inside it is the order `GatingConfiguration.load` already uses
(`Sources/Gating/GatingConfiguration.swift:102`): the token first, because the
ladder's thresholds cannot be converted without its decimals and the pools
cannot be given an asset id without its asset id. That is why the first thing a
clean machine is told to set is `TOKEN_ASSET_ID`.

**Why the store before the socket.** The bot this was ported from binds its
ports first, on the grounds that binding is how a process discovers another
copy. That reasoning is right and the conclusion moves, because this package
has something better: `SQLiteStore.open` takes an exclusive lease on a sibling
of the store file before it opens the handle
(`Sources/StoreSQLite/SQLiteStore.swift:126`, and
`Sources/StoreSQLite/InstanceLease.swift:43`, whose own comment gives the same
reasoning about a duplicate identifying first). The lease asks the exact
question, which is whether another instance is using this data. A port clash is
a proxy for that question, and a wrong one in the case this product has to
support: one machine hosting several communities has several instances, each
with its own store and its own port, and a second instance pointed at the same
store on a different port would pass a port check and fail a lease. So the
lease goes first and the bind second, and both go long before anything could
identify.

`STORE_PATH` is required and must be absolute. A relative path is resolved
against the working directory, and a supervisor that starts the process from a
different directory after a reboot hands the same command a different, empty
database, which reads as a reserve that has never paid anybody. That is worth a
refusal at boot naming the variable. The store report also says whether this
start created the file (`Sources/StoreSQLite/SQLiteStore.swift:91`), because an
invented store and a found one are otherwise indistinguishable in the output.

**Why the budget restore sits between the store and the chain.** It needs the
store, and it must happen before the first request, or a restart hands the
process a fresh day's allowance. The governor is constructed once and shared,
because two counters let the process spend twice the ceiling
(`Sources/Chain/RequestGovernor.swift:57` and `:75`).

**Why the chain gate refuses on some answers and not others.** A node that says
the asset does not exist, or that its precision is different, has contradicted
the operator's configuration, and that is a mistake they can fix in a minute
once they are told. A node that does not answer at all has told us nothing
about the configuration. If an unreachable node stopped the boot, a provider
having a bad five minutes at the moment a supervisor restarts the process would
turn a blip into a bot that stays down until somebody notices, and the `503
starting` answer this design already has exists to carry exactly that state. A
401 or 403 is treated as a contradiction rather than an outage, because it is
the operator's token that is wrong and no amount of waiting fixes it. The error
type already separates these cases (`Sources/Chain/ChainError.swift:22` to
`:35`).

## Bind before identify, enforced by the types

The rule is the one that cannot be softened, and stating it in a comment is how
it gets lost. A second instance that identified before discovering it was a
duplicate takes the live instance's session away, because the gateway answers a
duplicate identify by invalidating the session, and then dies on the bind a
moment later. Under a supervisor that restarts it, the healthy bot is knocked
offline every time the doomed one boots, and neither keeps a session.

So the bind produces a value. `ListenerBound` carries the address and the port
actually obtained, and its initialiser is internal to `Runtime`. The chat
seam's connect call takes a `ListenerBound`. An adapter in another target can
hold one and cannot make one, so connecting before binding does not compile.
This is the same trick the repository already uses for the claim-before-pay
rule, where the write scope takes a synchronous body and a payment is `async`,
so the wrong order does not compile.

The cost is that a test of the chat seam has to bind a real loopback socket on
port zero. That is cheap, it reaches no real chain, server or account, and it
is worth more than a hole in the type for tests to climb through.

## The health listener

A hand written listener over the platform's sockets, answering one path.
`Runtime` already has the precedent for the platform conditionals it needs
(`Sources/StoreSQLite/InstanceLease.swift:3` to `:9`). Adding an async
networking package for one endpoint would be a new pin and a new thing a
reader of TRUST-1 has to weigh, which is a poor trade for a few hundred bytes
of response.

- `GET /health` and nothing else. Everything else is 404.
- 200 when every enabled component is reached, 503 otherwise. Same body both
  ways, so a check can be written once.
- The body is `ChainHealthReport.jsonBody`
  (`Sources/Chain/ChainHealth.swift:186`), reused rather than re-spelled. The
  type is already exactly right about this: a listener that is bound while the
  connection it exists to serve has not been made reports `starting`.
- Components are named for the pieces the operator chose: `store`, `chain`,
  and later `chat` and `verification`. Naming them is what lets an outage read
  as the provider's rather than as ours.
- **A part that is off contributes no component.** `ChainHealthComponent`
  carries only a name and whether it was reached
  (`Sources/Chain/ChainHealth.swift:115`), and an off part reported as
  unreached would hold the instance at `starting` forever. Off parts are listed
  in the startup report and **not** in the `/health` body, because
  `ChainHealthReport.jsonBody` emits status, waiting and provider and nothing
  else (`Sources/Chain/ChainHealth.swift:186`), and adding a fourth key would be
  a change to a merged module's contract, which this change has declared it is
  not making. A community with a token and no collections therefore reads as a
  whole setup in the report, and as `ok` at the endpoint. An empty component
  list is `ok`, which the type already documents.
- **Answering costs no chain request.** The listener reads state the rest of
  the process has already recorded, plus whatever the cached provider probe has
  (`Sources/Chain/ProviderProofProbe.swift:26`), which deliberately does not go
  through the governor. So a health check still answers when the day's budget
  is spent, which is the moment somebody is actually looking at it.

`HEALTH_PORT` is required, with no default. A default port is the wrong
kindness here: the normal hosted shape is several communities on one machine,
and a shared default turns the second instance's first start into a port clash
that looks like a duplicate instance. `HEALTH_ADDRESS` defaults to loopback,
because the answer can carry provider proof headers and the waiting list, and a
default of every interface publishes both.

### The boundary with the follow-ups change

A second change is being defined at the same time,
`satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted`,
and it owns the `Chain` half of SEE-1.b. The split is written here as well as
there, because the failure when two changes are defined in parallel is that each
assumes the other owns the middle and neither builds it.

| That change ships, in `Chain` | This change ships, in `Runtime` |
|---|---|
| A pure assembly of a `ChainHealthReport` from values the host already holds, touching no reader and no data source | The listener, the one route, the 200 against 503 mapping, and the bind that precedes any identify |
| A non-probing read of the last provider proof, so assembling an answer awaits nothing that could reach the network | The component list, which only the composition root knows, and who marks each one reached |
| The budget and pause facts on the report, and the hand-built JSON body | The probe instance, its URL and when it is refreshed, always off the request path |
| The tests that assembling an answer reserves nothing | The test that the endpoint answers with the day's budget spent (REQ-runtime-017) |

Two consequences for this change, and both are cheap only if they are known
now. This change adds **no health vocabulary of its own**: the status, the
`waiting` list and the body are Chain's, so a body assertion here pins what
Chain renders rather than freezing a literal that the sibling change will
append a budget section to. And the status stays the two cases the type has
today, `ok` and `starting`; a spent budget or a live pause is a fact in the body
and never a failing check, or a deploy gate would roll a working version back
over a provider quota (RUN-3).

The other edge between the two is not about health at all. That change makes
every public read on `ChainReader` name the caller it is for, with no default,
so the chain gate's one call to `verifyAssetDecimals` becomes a call that names
the instance's own work rather than a member. Whichever change lands second
carries that one-line edit, and it is named in both definitions so neither is
surprised by it.

## The startup report, and the secret rule

The report is written at every start, cannot be suppressed by any setting, and
is rendered from the catalogue rather than by each subsystem printing what it
feels like. Rendering from the catalogue is what makes the secret rule
structural: the renderer has no access to a value except through an entry, and
an entry marked secret has no path that yields its value.

What it prints:

1. The spending banner.
2. The version.
3. Every catalogue entry, grouped, marked set or unset.
4. **What it made of them.** Every rung with its name, its threshold in whole
   tokens and in smallest units; every collection; every pool; the admin
   allowlist in full; the network the node points at. This is the section that
   makes a typo visible: a dropped rung is a shorter ladder here, minutes
   before a sweep acts on it.
5. Which parts are on, which are off, and why each off one is off.
6. The address and port bound.
7. The store: migrations applied, and whether this start created the file.
8. The settings audit: owned variables nothing read, and near misses.

What it never prints:

- **The value of a secret.** Set or unset, and nothing else. Not a length, not
  a prefix, not a hash: a hash of a low entropy secret is a crackable secret,
  and a length is enough to confirm a guess.
- **A fact derived from a secret**, unless the catalogue entry names that fact
  and the fact is public by construction. The case this exists for is a signing
  key, whose public address an operator must be able to read to check they
  funded the right account. That is the whole of the CATALOG-6.a and ADOPT-9.a
  pair: the operator reads back what the bot made of their settings, and never
  the settings themselves.
- **The path or query of any URL.** Reported as scheme, host and port. Some
  node providers put the credential in the path, and the report is meant to be
  safe to paste into an issue. The host is still what answers ADOPT-12.b, since
  the host is what says which network this is.

The check that holds all of this together is one test rather than one
assertion per field: set a unique sentinel as the value of every secret entry
in the catalogue, render the report, and fail if any sentinel appears anywhere
in it. A secret added later without a thought is caught by the same test.

Today the package asks for exactly one secret, `CHAIN_API_TOKEN`
(`Sources/Chain/ChainEnvironment.swift:32`).

## Spending, structurally

BUILD-3 asks for a build that cannot spend to be unmistakably different from
one that can, and BUILD-3.a forbids any setting that merely quietens output
from being mistakable for one that stops money moving.

The answer is that **spending capability is a parameter, never a reading**. The
composition takes a `SpendCapability`, which is either the case that cannot
spend or the case that can and which carries a `ReservePayer`
(`Sources/Reserve/ReservePayer.swift:38`) and the public account it signs for.
There is no code path from `Settings` to that value: no variable is consulted,
and the test for it sets every catalogue variable to a truthy and to a falsy
value and asserts the capability is exactly what the caller passed.

At this commit the package contains no implementation of `ReservePayer` at all,
and nothing anywhere holds a key, which `docs/WHAT-IT-TALKS-TO.md` already
states. So every build prints the cannot-spend banner, and that is a fact about
the package graph: making a build that can spend means adding a target that
implements the protocol, which is an edge in the manifest and a line in the
disclosure document, both of which somebody reads.

Two consequences worth stating plainly.

**No `TEST_MODE`.** The bot this was ported from carries a note in its own
documentation saying that its test mode is not a money switch. BUILD-3.a is
that if a project has to carry such a note, the software has already failed to
say so itself, and the note is load-bearing only until somebody new does not
read it. So the variable does not exist here. If a verbosity variable arrives
later it is marked in the catalogue as changing output only, and the report
prints it under a heading that says so in words.

**The banner is not a log line.** It is written by the report writer, not by a
logger, so no level, filter or destination can remove it.

## What `swift run` does

Four commands. `run` is the default, so `swift run` with no arguments is `swift
run bot run`.

**On a clean machine with nothing set**, `bot run` prints the banner, reaches
the configuration gate, and exits 78 with the name of the first variable to
set, the purpose sentence the loader already carries for it, and one line
pointing at `bot check`. That is the useful clean machine answer: not "failed
to load configuration", which is what the ported bot prints, but the variable,
what it is for, and where the rest of the list is.

**`bot check`** loads the settings, prints the same report the boot would, and
touches nothing: no socket, no store, no network. With nothing set it prints
the entire catalogue with every entry marked unset, plus the first refusal, and
exits 78. That is the list an operator works down before a first deploy, and
the thing they point a new version at before taking it (RUN-9).

It reports the first refusal rather than every one, because the loaders throw
on the first bad value and changing that would be a change to four merged
contracts. The catalogue listing is what stops that being unhelpful: the
refusal says what is wrong, the catalogue says what is still missing.

**`bot rehearse`** loads the same configuration and then runs the role rules
over members, accounts and holdings it invents, printing the decision for each.
No socket, no store, no network. It invents members and holdings only, never
configuration, so a contributor watches their own ladder work rather than one
somebody else chose, which is both what BUILD-1.b actually asks for and the
only reading compatible with ADOPT-6.a.

**With a valid configuration**, `bot run` walks the eight gates, binds, answers
`503 {"status":"starting","waiting":["chain"]}` from the moment the socket is
up, flips to 200 when the chain gate has confirmed the asset, and then waits.
It is honest about what it is: a program with a store, a chain reader, a health
endpoint and no chat surface, and the report says so in the off list.

## Exit codes

| Code | Meaning | Examples |
|------|---------|----------|
| 0 | Stopped cleanly | a signal |
| 64 | Usage | an argument nobody recognises |
| 69 | Something is already here, or cannot be used | the store is held by another process, the address is in use, the volume cannot promise a write |
| 70 | Internal | a key read that the catalogue does not describe |
| 78 | The configuration is wrong | a missing variable, a bad value, an asset the node has never heard of |

The values are the conventional `sysexits` ones so that a supervisor and a
deploy script do not have to learn a private table. One code for everything,
which is what the ported bot does, makes a wrong token and a full disk the same
signal to whatever is watching. 69 in particular is the one an operator can put
in a supervisor's do-not-restart list, which is the difference between a
duplicate instance dying once and a restart loop.

## Decisions somebody might disagree with

- **The lease before the bind**, where the ported bot binds first. The lease
  asks the real question and works when two instances share a machine and not a
  port. The counter-argument is that the ported bot's ordering is battle
  tested and this one is not, and that a store on a volume where locking is
  unreliable would fall back on nothing. The second half is answered by the
  volume refusal already in `DurableVolume`.
- **An unreachable node does not stop the boot.** The other way, which the
  ported bot takes for its verification portal, turns every provider blip
  during a restart into an outage. The cost of this choice is that a
  misconfigured node URL that resolves to nothing leaves a process running and
  permanently `starting`, rather than exiting. The health answer is what makes
  that safe, and it is only safe if the deploy gate reads it.
- **A chat variable set on a build with no chat surface refuses.** A loud
  warning would also be defensible and would let somebody stage their
  environment file ahead of the release. Refusing wins because the failure it
  prevents is silent and the failure it causes is not.
- **`HEALTH_PORT` and `STORE_PATH` are required with no defaults.** Two more
  lines in the README's first run. The alternative defaults are the two that
  bite hardest later: a shared port that collides on the second community, and
  a relative path that quietly becomes a second empty database.
- **URLs are reported as host only.** Slightly annoying when an operator wants
  to confirm the path they typed. Worth it, because the report is designed to
  be pasted into an issue and some providers put the credential in the path.
- **`Runtime` is a target and not a product.** Somebody wanting to embed an
  instance in their own process cannot, and has to run the binary. That is the
  right trade while the shape is changing weekly, and it is the reversible
  direction.
- **`rehearse` ships in this change** rather than waiting. Without it a
  contributor with no credentials has nothing to look at but `swift test`, and
  the acceptance criterion asks for both the empty machine and the configured
  one to be useful. It is the most separable thing here if a reviewer wants the
  change smaller.
- **A hand written listener instead of an async networking package.** More code
  here, no new pin, and one fewer thing for a reader deciding whether to
  install this to weigh.

## What this change does not do

- No chat client, no gateway connection, no slash command, no embed. The seam
  and the ordering exist; nothing implements them.
- No wallet verification, and no boot gate for a verification service. When one
  arrives it is a component that can be unreached without the bot being down,
  because losing the part that proves a wallet should lose verification and
  nothing else (SEE-7). That is a deliberate divergence from the ported bot,
  which refuses to start when its portal is unreachable.
- No payer, so nothing can move value, and no variable exists that would change
  that.
- No sweep loop and no scheduler. The gate list has a place for them and it is
  empty.
- No invite link and no permission list (ADOPT-11). Both need a chat client to
  be meaningful.
- No version stamped from the commit. The version is a constant in `Runtime`
  edited when a release is cut, which is honest and cheap; a build plugin that
  stamps the commit is a later change.

## Unsettled

- **Whether the near-miss suggestion should use edit distance at all.** It is
  the kind of cleverness that produces a confident wrong suggestion. The
  fallback is to list the owned variables nothing read and let the operator
  match them by eye, which is most of the value for none of the risk.
- **Whether `check` should try to report every refusal rather than the first.**
  Doing it properly means the loaders collecting errors instead of throwing,
  which is a change to four merged contracts and belongs in its own change with
  its own argument.
- **Where the report goes when the process is not a terminal.** Standard output
  is the assumption here. A container that captures only standard error would
  lose it, which would break BUILD-3.b in the environment that matters most.
  Worth settling before the first deploy, and it may be as simple as writing
  the banner to both.
