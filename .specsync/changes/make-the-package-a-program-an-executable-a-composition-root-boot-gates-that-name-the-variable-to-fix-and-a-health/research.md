---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: research
---

# Research

## The headline finding: this is composition, not construction

Every collaborator the runtime needs is already a protocol, and every
protocol already has an offline implementation. That is not luck, it is what
the previous tranches were for, and it means the boot sequence can be tested
end to end with nothing installed.

| What the runtime needs | The seam that exists | The offline implementation |
|---|---|---|
| Read an account or an asset | `AccountDataSource`, `Sources/Chain/AccountDataSource.swift:130` | doubles in `Tests/ChainTests/ChainFixtures.swift` |
| Remember things between restarts | `BotStore`, `Sources/Store/BotStore.swift:120` | `InMemoryStore`, `Sources/Store/InMemoryStore.swift:23`, and `SQLiteStore.inMemory()`, `Sources/StoreSQLite/SQLiteStore.swift:152` |
| Keep the day's request count | `RequestBudgetStore`, `Sources/Chain/RequestBudgetStore.swift:44` | `InMemoryRequestBudgetStore`, same file line 57 |
| Prove which provider answered | `HTTPHeaderProbe`, `Sources/Chain/ProviderProofProbe.swift:11` | anything the test writes; `URLSessionHeaderProbe` at line 107 is the real one |
| Move value | `ReservePayer`, `Sources/Reserve/ReservePayer.swift:38` | nothing conforms to it anywhere in this repository |

The last row is the important one and it is covered under BUILD-3 below.

Two more pieces of the boot sequence are already written and have never been
called by anything:

- `RequestGovernor.restoreFromStore(now:)`,
  `Sources/Chain/RequestGovernor.swift:75`. This is RUN-8.b, that a restart
  does not hand the process a fresh day's budget for reading the chain. It is
  a boot step waiting for a boot.
- `RequestGovernor.flushPersistence()`, same file line 224. The matching
  shutdown step.

And `SQLiteStore.pendingMigrations(at:)`
(`Sources/StoreSQLite/SQLiteStore.swift:187`) reads what a file would need
without opening it for writing, which is the only thing in the repository that
can answer RUN-9, a new version telling an operator what has to change before
they take it.

## Where the process environment is read

Exactly one place in `Sources/` touches `ProcessInfo` today:
`ChainConfiguration.loadFromProcessEnvironment`,
`Sources/Chain/ChainConfiguration.swift:165-167`. Everything else takes the
environment as a parameter, and `Sources/Chain/ChainConfiguration.swift:120-122`
says why in as many words: so that every refusal below it is reachable from a
test.

The loaders come in two shapes and the difference matters when composing them.

- `Gating` takes a lookup function, `(String) -> String?`. See
  `TokenProfile.load(_:)` at `Sources/Gating/TokenProfile.swift:179`,
  `GatingConfiguration.load(_:)` at
  `Sources/Gating/GatingConfiguration.swift:102`, `AdminAllowlist.load(_:)` at
  `Sources/Gating/AdminAllowlist.swift:84`, `CollectionCatalog.load(_:)` at
  `Sources/Gating/CollectionConfiguration.swift:35`. Each also has a
  dictionary overload that wraps the lookup, described in the source as the
  shape tests use.
- `Chain` takes a dictionary, `[String: String]`. See
  `ChainConfiguration.load(token:environment:)` at
  `Sources/Chain/ChainConfiguration.swift:132`, and the same for `ChainLimits`
  and `ChainCacheLifetimes` at lines 304 and 412.

**What must be true:** the composition root reads the process environment once,
into one value, and both shapes are derived from that one value. Not two reads.
The reason is not tidiness. `Gating` and `Chain` already had a bug of exactly
this family, where one layer trimmed a trailing newline and the other did not,
so the same line in the same file was a valid value to one and a refusal to the
other; the fix is recorded at
`Sources/Chain/ChainConfiguration.swift:177-183` and the rule now lives in
`NumberedEnvironment.nonEmpty` (`Sources/Gating/NumberedEnvironment.swift:81`).
An operator has one environment, not one per module. A snapshot also means the
startup report describes the same bytes the boot used, which it could not
promise if two layers each called `getenv` at different moments.

**How a test supplies a different one:** the composition root takes the
snapshot as a parameter with no default, and the executable is the only caller
that passes the process's own. A test passes a dictionary literal. That is the
same discipline `SQLiteStore.open(at:)` already follows and states:
"The path arrives as a parameter and this target reads no environment variable
of its own, which is what stops a test quietly finding an operator's live file
(BUILD-2.a)", `Sources/StoreSQLite/SQLiteStore.swift:112-115`.

## The rule that is not negotiable: bind before identify

### What the reference implementation does

Its `Bot.start()` binds its webhook listener and its admin listener, registers
its commands, and only then calls `gateway.connect()`. The comment above that
sequence is the longest comment in the file and says: binding a port is how
this process discovers that another copy is already running; a second copy that
identified to the gateway before finding that out would take the live copy's
session away, because the gateway answers a duplicate identify by invalidating
the session, and then it exits on the bind a moment later; under a supervisor
that restarts it, that is an unrecoverable reconnect storm in which the healthy
bot is knocked offline every time the doomed one boots, and neither copy keeps
a session.

The consequence it draws is the part worth copying: because the listener now
binds first, the health endpoint reports a starting status until the gateway
connects, rather than treating a bound socket as health.

### What is already in this repository

Half the rule, applied to a different resource. `InstanceLease`
(`Sources/StoreSQLite/InstanceLease.swift:29`) takes an exclusive `flock` on a
sibling of the store file, and its documentation at lines 20 to 24 makes the
same argument about the same failure: "an instance that had already announced
itself to a chat gateway before discovering it was the duplicate would take the
live instance's session away on the way out, and under a supervisor that
restarts it, that is a loop that knocks the healthy instance offline every time
the doomed one boots." `SQLiteStore.open` takes the lease before it opens the
connection, with a comment saying so
(`Sources/StoreSQLite/SQLiteStore.swift:123-127`).

So the general rule is broader than ports. **Every exclusive local claim this
process makes, the listeners and the store lease, is made before anything
identifies to a chat gateway.** A duplicate must be able to die without the
live instance noticing.

**Order between the two claims.** This research proposed binding the listeners
first and opening the store second, on the grounds that the bind is the only
claim observable from outside the machine, so a duplicate's refusal happens
where a deploy gate is looking and before migrations touch the operator's file.
**The change settled the other way**: the store lease is taken first and the
bind second (`plan.md` D7, REQ-runtime-008, and the gate table in
`design.md`). The deciding arguments were that the lease asks the real question
rather than a proxy for it, since a port is configuration and two instances on
one machine legitimately hold two ports over one store; that the lease is the
guard protecting money, so a doomed process should die on it as early as
possible; and that the repository has already committed to lease-first in
writing (`Sources/StoreSQLite/InstanceLease.swift:20-24`), and two files giving
opposite orders for the same hazard is worse than either order. The
counter-argument above is recorded because it is real: the cost of lease-first
is that a store refusal is a refused connection rather than a `starting`
answer.

**What this costs, and it is the point.** There is now a window in which the
listener answers and the bot is doing nothing. That window is exactly why the
health body cannot be `ok` on a bound socket.

## Health: what the body says, and what already exists to say it

`ChainHealthStatus` has two cases and no third:
`Sources/Chain/ChainHealth.swift:105-112`, `ok` and `starting`.
`ChainHealthReport` (line 147) holds a list of named components and whether
each has been reached, is `ok` only when every component has been reached
(line 172), lists what is outstanding as `waitingOn` (line 177), and renders
`{"status":"starting","waiting":["..."]}` by hand rather than through an
encoder because the shape of that string is what a monitoring check greps for
(line 186).

Its own documentation at lines 136 to 146 is the incident this change serves:
the process was up, the port answered, the check said ok, every one of those
was true and none of them was useful.

So the runtime writes no health model. It composes this one, declares the
components a given build actually has, and maps the status onto an HTTP code.
The reference answers 200 for ready and 503 otherwise, and matching that is
worth more than inventing a code.

**Which components to declare.** Only the ones this build can actually reach.
`ChainHealthReport`'s initializer documentation says an empty list is `ok`, "so
a host that has nothing to wait for does not have to invent something"
(lines 160-163). Declaring a component for a thing the binary cannot possibly
reach would make `starting` permanent, which trains an operator to ignore it,
which is the same disease as a check that always says ok. Today the honest
components are the store being open and the node having been read once. The
chat gateway becomes a third the day a chat client is in the graph, and the
body's shape does not change when it does.

**SEE-1.b constrains the handler.** Checking must not spend the day's budget
for reading the chain, and must still answer once that budget is gone. So the
handler reads a cached snapshot and issues no request of its own.
`ProviderProofProbe` already caches for `CHAIN_HEALTH_PROBE_CACHE_SECONDS`
(`Sources/Chain/ChainEnvironment.swift:69`,
`Sources/Chain/ProviderProofProbe.swift:48`), and `RequestGovernor.snapshot`
(`Sources/Chain/RequestGovernor.swift:198`) is a pure read.

**Where it binds.** Loopback by default, because the body names what the
instance is waiting on and that is information an operator chooses to expose
rather than exposes by default. The counter-argument is real and should be
recorded: a container platform often probes from outside the container, so a
container deployment needs a different bind address, and the variable that sets
it has to exist from the first day rather than being discovered by somebody
whose health check never passes.

## What `swift run` should do, in both shapes

The acceptance criterion asks for two behaviours and both have to be useful
rather than a placeholder.

**With no configuration at all.** Exit non-zero, having printed the first
variable to set and what it is for. This is free: the loaders already produce
exactly that sentence. `NumberedEnvironment.requiredWholeNumber` takes a
`purpose` string and throws `GatingConfigurationError.missing(key:purpose:)`
(`Sources/Gating/NumberedEnvironment.swift:108-120`), and the call site for the
asset id passes "It is the on-chain id of the asset your holder ladder is
measured in" (`Sources/Gating/TokenProfile.swift:180-184`). The work is
ordering the loaders so that the first refusal a newcomer meets is the most
useful one, and rendering the error to standard error in a form a person can
act on.

**With a valid configuration.** It loads everything, prints the startup report,
binds, opens the store, restores the day's request count, reads the asset's
decimals off the node and checks them against what was configured, and reports
`ok`. Every one of those steps exists in the libraries already. It is a real
program on the day it lands: an operator can point it at their node with their
asset and find out, in one command, whether their settings are coherent, which
is the whole of ADOPT-2 and ADOPT-9 and most of ADOPT-12.b. It cannot yet do
anything in a Discord server, and the report should say so rather than implying
otherwise.

**The order as settled, and why each step is where it is.** This list follows
`design.md`'s gate table and REQ-runtime-008; steps 4 and 5 are the pair the
section above records a change of mind about.

1. Read the environment once.
2. Load every configuration. Pure, no I/O, so the first refusal costs nothing
   and names a variable.
3. Print the startup report, opened by the spending banner. Before anything
   that can fail slowly, so an operator who hits a later gate still sees what
   the bot made of the settings (ADOPT-9.a), and so BUILD-3.b's sentence about
   whether this build can sign is near the top of every start.
4. Open the store: volume check, lease, migrations
   (`Sources/StoreSQLite/SQLiteStore.swift:115-131`). First claim, because the
   lease is the duplicate guard and a port is configuration.
5. Bind the listener. Second claim, and long before anything could identify.
6. Restore the day's request budget from the store
   (`RequestGovernor.restoreFromStore`). Before the first chain read, or the
   restart has already spent a request against a fresh count.
7. The one boot gate that touches the network: verify the asset's decimals
   against the chain, which `CHAIN_VERIFY_ASSET_DECIMALS` already declares and
   defaults on (`Sources/Chain/ChainEnvironment.swift:21-24`,
   `Sources/Chain/ChainConfiguration.swift:48-50`). This is ADOPT-12.a. It is
   after the bind so a slow node cannot delay the bind, and it counts against
   the request budget like everything else. Where the change being defined
   alongside this one makes a caller required on `ChainReader`, this read names
   the instance's own work rather than a member (REQ-runtime-032).
8. Identify to the chat gateway. Last, always.
9. Start the loops.

Steps 4, 7 and 8 are the components the health body names, so the body says
which of them is outstanding while it is outstanding.

## The graph, and making the compiler hold it

`Store` depends on `Reserve`, `Gating` and `Chain` and on no chat client, and
`Package.swift:118-123` states the argument: `import DiscordBM` there is a
missing module rather than a review comment, the adapter that will know about
snowflakes depends on `Store`, and SwiftPM refuses a cycle, so `Store` can
never acquire it back.

An executable must see both, so it is the first thing that can undo this.

**What must be true:** the composition root, the boot gates, the startup report
and the health listener live in a `Runtime` library target that depends on no
chat client. As settled, that target depends on `Gating`, `Chain` and `Store`
only: it takes `any BotStore` rather than linking `StoreSQLite`, and it links
neither `Games` nor `Reserve` while nothing plays or pays. The executable
target depends on `Runtime` and on `StoreSQLite` today, and on a chat adapter
when one exists, and holds nothing but argument handling, signal handling and
the wiring of the real collaborators. Then:

- `Runtime` cannot import a chat client, because it does not declare one, which
  is the same enforcement `Store` already has.
- A test target can depend on `Runtime` and exercise the whole sequence.
- `Runtime` still has to sequence the chat connection, so it declares a seam,
  a protocol with a connect operation, in the same spirit as `ReservePayer`
  (`Sources/Reserve/ReservePayer.swift:38`), whose documentation gives the
  general reason: "when payment lives inside a concrete type that holds a key
  and talks to a network, none of the failure paths can be exercised by a test
  at all, and they are the paths that matter" (lines 35-37).

That last point is what turns the non-negotiable rule into something a test can
prove. The code that sequences the boot cannot see a concrete gateway at all;
it holds a protocol and calls it last. A double records the moment it was asked
to connect, and the test asserts the listener was already bound and the store
lease already held. The rule stops being a comment that a future contributor
may reorder.

## Secrets

**The claim that this is the first code in the repository to read a secret is
not quite right, and the difference matters.** `CHAIN_API_TOKEN` is already
read, at `Sources/Chain/ChainConfiguration.swift:147`, and
`docs/WHAT-IT-TALKS-TO.md:160-166` already declares it as the package's one
secret. What is new is that this is the first code that has to *print* anything
about a secret, because it is the first code with a startup.

Two criteria apply at once and they pull in opposite directions. CATALOG-6.a:
looking at the settings never shows a secret. ADOPT-9.a: an operator can read
back what the bot made of their settings, so a rung or a collection their typo
dropped reads as missing before a sweep acts on it.

**What the report prints for a secret:** the variable's name, and whether it is
set or not set. Nothing else.

**What it must never print:** the value, a prefix or suffix of the value, its
length, a hash or fingerprint of it, and any derived identifier. A stable hash
confirms a guess, and the leading characters of a bot token are the application
identifier in some encodings, so "just the first four" is not a redaction. The
operator's real question is "did it read the one I meant", and the honest cheap
answer to that is the outcome: the node answered, or the gateway identified, or
it did not. That is a fact in the report already.

Somebody will disagree, and the case is worth recording: an operator rotating a
key wants to know which of two keys is loaded, and "set" does not tell them.
The decision goes against them, because the cost of being wrong the other way
is a live credential in a log file on its way to a log aggregator, and because
the outcome line answers the question a moment later anyway.

**Two more rules that fall out of reading the existing error types.**

A signing account's *address* is not a secret and should be printed, because an
operator has to be able to check which account will pay. The key that derives
it never appears.

A malformed secret must be refused by name only. This is a real hazard in the
current code rather than a hypothetical: `ChainConfigurationError.invalidValue`
carries `variable`, `value` and `expected`
(`Sources/Chain/ChainConfiguration.swift:137-142` for a call site), and
`GatingConfigurationError.notANumber(key:value:)` carries the value too
(`Sources/Gating/NumberedEnvironment.swift:117`). Echoing the value is exactly
right for a threshold, where seeing what you typed is the whole help, and
exactly wrong for a token. Nothing routes a secret through those today, because
`CHAIN_API_TOKEN` is read with a non-throwing accessor. Any new secret must not
be the first one to, so it needs its own refusal that names the variable and
says what was expected without quoting what was found.

## BUILD-3: making "cannot spend" structural

`hi/build.md:28-30` is the criterion. The intent text above it, lines 16 to 18,
is blunter than the criterion and should be read as the specification: a
contributor is the person most likely to have this pointed at something real by
accident, because they are the one running it in ten shapes in an afternoon,
half of them with settings copied from a file they did not read.

**The reference implementation is the worked example of getting this wrong.**
It has a mode flag that skips Discord role changes and nothing else. Its own
documents carry the warning in three separate places that the flag is not a
money switch, and an audit finding in a fourth records that two commands ignore
the flag anyway. BUILD-3's intent text predicts this exactly: if a project has
to carry a note warning that a particular flag is not a money switch, the
software has already failed to say so itself, and the note is only load-bearing
until somebody new does not read it.

**Today's position is unusually strong and should be used.** Nothing in this
repository can sign. `ReservePayer` is a protocol with no conformance anywhere,
and `docs/WHAT-IT-TALKS-TO.md:30` states it: every chain call is a read,
nothing here holds a key. So the honest sentence at startup is not a
configuration reading, it is a fact about what was linked.

**What must be true:**

- The capability to spend is a **component that is linked**, never a variable
  that is read. The composition root takes an optional payer; the executable
  passes nothing because nothing in its graph conforms to the protocol.
- The report's sentence is derived from what was composed, so it cannot
  disagree with the binary. If no payer was composed, the report says this
  build cannot sign, every start, without being asked.
- Two different states exist and the report must tell them apart in words an
  operator can distinguish. A build with no paying component cannot sign
  whatever anybody sets. A paying build with no key configured runs and simply
  cannot pay, which is SPEND-6.c and is a legitimate steady state for a
  community that only wants roles. Collapsing those two into one sentence is
  the same mistake as the mode flag, one step up.
- No variable may be named in a way that suggests it stops money moving. There
  is no `PAYOUT_MODE` and no dry run flag.

**The mechanism for the split is deliberately left to the change that adds
signing**, because signing does not exist yet and choosing the mechanism now
would be choosing it blind. What this change owes that future change is the
seam and the sentence, so signing arrives as "add a target and pass a payer"
rather than "add a flag". The evidence gathered below narrows the options, and
recording it here saves that change from rediscovering it.

## Evidence gathered by running things

Two facts about SwiftPM were measured rather than assumed, on Swift 6.3.3, in a
throwaway package. They constrain the shape of the manifest.

**A second executable breaks bare `swift run`, product or not.** With two
executable products, `swift run` exits with `error: multiple executable
products available: one, two` and runs nothing. Declaring only one of them as a
product does not help: with one executable *product* and one additional
executable *target*, the same error appears, naming both. `swift run two` works
in that case, but the bare command does not.

This matters directly. The acceptance criterion says `swift run` on a clean
machine names the first variable to set. If the package ships two executables,
the first command a newcomer types answers with a package manager error instead
of the software's own message, and BUILD-4 and ADOPT-4 both suffer. So a
paying/non-paying split done as two executables costs the first sentence a
newcomer reads.

**Package traits parse at tools version 6.1.** A manifest declaring
`traits: [.trait(name:description:)]` and a `.define(_:.when(traits:))` build
setting resolved and built. That was on a 6.3.3 toolchain; CI's Linux lane
pins `swift:6.1-noble` (`.github/workflows/tests.yml`), so the floor has to be
confirmed there before anybody relies on it. A trait keeps one executable and
decides what code exists rather than what code does, which is a genuine
difference from a mode flag, but it also keeps one binary name, which weakens
"unmistakably different" in BUILD-3.

## Which of the reference's boot gates a general product needs

The reference lists seven conditions that stop its start. The verdict on each,
generalised.

| Reference gate | Verdict here | Why |
|---|---|---|
| Verification portal URL is set | Later, and conditional | This product has no verification component yet. The general rule is that a component an operator turned on must have the settings it needs, which belongs to the change that adds one. |
| Webhook shared secret is set | Later, same shape | As above. |
| Verification portal answers a health ping | **No** | It makes this bot's start depend on a third party being up, so their outage becomes an outage plus a restart loop. SEE-7 wants a verification outage to cost verification and nothing else. It becomes a named component in the health report instead, so it still does not fail silently. This is a deliberate disagreement with the reference. |
| Webhook port can be bound | **Yes, and first** | This is the non-negotiable rule. Generalised: every listener this build runs binds before anything identifies. |
| Asset id, chat token and server id are present | **Yes** | The loaders already do it and already name the variable. `TOKEN_ASSET_ID` and `TOKEN_DECIMALS` are required with no default (`Sources/Gating/TokenProfile.swift:180-195`), and `Sources/Gating/TokenProfile.swift:41-46` explains what a wrong `decimals` does to every rung of the ladder. |
| Spending caps and budgets parse, and a zero cap is refused | **Yes in shape** | Not the reference's specific variables. `ChainLimits` already refuses a rate below one, a batch below one and a persist interval below one (`Sources/Chain/ChainConfiguration.swift:315-349`). Whatever spending caps arrive get the same treatment. |
| Admin port can be bound | **Yes** | Same rule as the webhook port. |

Two gates the reference does not have, that this product does, because the
storage layer was written after it:

- The store's volume is one that can promise a write reached storage.
  `DurableVolume.require` refuses a network filesystem
  (`Sources/StoreSQLite/DurableVolume.swift:21-34`), called from
  `SQLiteStore.open` before the lease.
- The store's exclusive lease. `InstanceLease`,
  `Sources/StoreSQLite/InstanceLease.swift:29`.

And one the reference has no equivalent of, which is the cheapest large win
here: reading the asset's decimals off the node at boot and refusing when they
disagree with `TOKEN_DECIMALS`. The variable and the flag already exist
(`Sources/Chain/ChainEnvironment.swift:21-24`) and nothing runs them. That is
ADOPT-12.a, an asset that does not exist on the network you pointed it at
stopping the boot rather than reading as held by nobody.

## What could not be settled

**The paying/non-paying mechanism.** Two executables cost the bare `swift run`
message, measured above. A package trait keeps one executable and one binary
name, and needs confirming on the 6.1 floor. A third option nobody has costed
is a separate package. This change does not need to pick, but the change that
adds signing does, and it should not pick without re-reading BUILD-3.a.

**Whether the runtime should be allowed a chain read at boot at all.** Step 7
above spends one or two requests before the bot is serving anybody, which is
fine on a paid node and is a real fraction of a small free tier if a supervisor
is restarting the process. `CHAIN_VERIFY_ASSET_DECIMALS` defaults on, which is
the right default for correctness and arguably the wrong one for a restart
loop. RUN-8.a is about not redoing work a restart already finished, and this
gate redoes itself every time. Somebody should decide whether the answer is
cached with the day's counter or simply accepted.

**The health listener's default bind address.** Settled as loopback, with
`HEALTH_ADDRESS` present from the first day for the container case
(REQ-runtime-018). The judgement recorded above stands: this repository has
usually decided such questions in favour of the person on a laptop, and a
default of every interface would publish the waiting list and any provider
proof.

**Whether the executable should have a second mode that checks the
configuration and exits.** Settled as yes, and as two modes rather than one:
`check` and `rehearse` (REQ-runtime-025, REQ-runtime-026, REQ-runtime-027).
The reasoning recorded here is the argument that won, that the report is most
useful to somebody iterating on an env file and that making them start and
stop a bot to read it is friction. `plan.md` records `rehearse` as the most
separable thing in the change if a reviewer wants it smaller.

**Where the startup report goes.** Standard output is the obvious answer and
the report is the one thing an operator most wants after the fact, which argues
for it also being retrievable from a running instance. SEE-12 wants to know
which version is running; CATALOG-6 wants to see what the server is running
without opening a shell on it. Both point at the report being a value the
runtime holds rather than only a thing it printed once, and nobody has decided
that.

**How many requests the boot is allowed to make before the budget is
restored.** Step 6 is ordered before step 7 for this reason, but if the store
open fails and a future version decides to continue with an in-memory store,
the ordering guarantee quietly disappears. Whether a failed store open is fatal
has not been decided; RUN-3 and SPEND-2.a both suggest it must be.
