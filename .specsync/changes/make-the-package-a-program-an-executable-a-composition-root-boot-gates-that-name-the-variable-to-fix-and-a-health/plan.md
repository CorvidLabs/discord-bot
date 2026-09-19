---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: plan
---

# Plan

## What this change is

Six libraries exist and nothing runs them. `README.md` says so in its own
words: "no gateway, no slash commands, no executable target and nothing you
can deploy". This change adds the missing half of that sentence and no more:
one executable, one place that reads the process environment, an ordered boot
whose every refusal names the variable to fix, and a health listener bound
before anything could ever identify to a chat service.

It does not add Discord, verification, sweeps, schedules or signing. The point
is to build the frame those hang on, and to build it in the order that makes
each of them a small change later rather than a rewrite.

The acceptance criteria are in `change.md` and the normative statements are in
`requirements.md`. This document is the order the work is done in, the
decisions that order rests on, and what is deliberately left out. Where a
requirement already settles something, it is cited rather than re-argued.

## What `swift run` does the day this lands

This is the first question a reader will ask, so it is answered before
anything else.

**With nothing configured.** It refuses, prints the name of the first variable
to set with the sentence saying what that variable is for, and exits with the
configuration code. The sentence already exists and has never been printed:
every loader carries a `purpose` through
`GatingConfigurationError.missing(key:purpose:)`
(`Sources/Gating/GatingConfigurationError.swift:13`). On an empty environment
the first name is `TOKEN_ASSET_ID`, because `GatingConfiguration.load` reads
the token first (`Sources/Gating/GatingConfiguration.swift:102`).

**With a valid configuration.** It prints a startup report saying what it made
of the settings, opens the store and takes the exclusive lease, restores the
day's request count, binds the health listener, probes the node once, and then
stays up answering `GET /health` until it is signalled. That is not a
placeholder. It is the whole of the process that exists today, and it is
useful before any chat code lands: an operator can point it at their real node
and their real store and find out whether their settings are right, and a
deployment gate can be written against it now and still be correct on the day
the chat surface arrives.

**Two modes that need nothing at all.** `check` loads everything, prints the
same report and exits, touching no socket, no file and no network. `rehearse`
runs the operator's own rules over members and holdings it invents and prints
the decision for each. Those are the modes a contributor with a laptop and no
keys runs (BUILD-1, BUILD-1.b, BUILD-2.b), and `check` is also what an operator
runs against a new version before they take it (RUN-9).

What it cannot do, and says so on the first line of every start, is spend
anything. See D9.

## The shape it lands in

Two new source targets and one new test target.

| Target | Kind | Depends on | Holds |
|--------|------|-----------|-------|
| `Runtime` | library target, not a product | `Gating`, `Chain`, `Store` | `Settings` and the catalogue, the boot sequence, the startup report, the readiness state, the health listener, the seams |
| `BotMain` | executable target, product `bot` | `Runtime`, `StoreSQLite` | `main.swift` and nothing else |
| `RuntimeTests` | test target | `Runtime`, `Store`, `StoreSQLite` | every test named for the criterion it protects |

Three properties of that table are the whole argument for it.

**`Runtime` cannot see a chat client, and neither can anything below it.** The
seam a chat gateway will implement is declared in `Runtime` over Foundation
types, with a role and a member both named by `String`. The adapter that knows
what a snowflake is will be its own target depending on `Runtime`, and
`BotMain` will link it. `Runtime` therefore never names a chat SDK in the
manifest, SwiftPM refuses the cycle that would let `Store` acquire one back,
and `Store` keeps the guarantee `Package.swift` already claims for it, that an
import of a chat client there is a missing module rather than a review comment
(REQ-runtime-002).

**`Runtime` cannot open a database.** It takes `any BotStore`
(`Sources/Store/BotStore.swift:120`), so its tests run against
`SQLiteStore.inMemory()` or a temporary file and need nothing installed
(BUILD-2). The concrete durable store is chosen in `BotMain`.

**`BotMain` is too small to hide anything.** Argument handling, one environment
snapshot, the construction of the live seams, the signal handlers, the exit.
Everything that could be wrong is in `Runtime`, where a test can reach it
(REQ-runtime-001).

`Runtime` deliberately does **not** depend on `Games` or `Reserve`. Neither is
reachable without a surface to play on or a payer to pay with, and a dependency
added before it is used is one nobody can argue with later.

## The rule that is not negotiable

**The listener binds before anything identifies to a chat service.**

Binding is how a process discovers that another copy of itself is already
running. A second instance that identified first would take the live
instance's session away from it, because a gateway answers a duplicate
identify by invalidating the session it collided with, and then the second
instance would exit a moment later on the bind it was always going to fail.
Under a supervisor that restarts it, that is not a bad minute, it is a loop:
the healthy instance is knocked offline every time the doomed one boots, and
neither keeps a session. The repository already carries this reasoning, in
`Sources/StoreSQLite/InstanceLease.swift`, written about the store lease for
exactly the same hazard.

The consequence, and it is the part that gets forgotten: **a bound socket is
not health.** If the endpoint answered "fine" as soon as it was listening, a
deployment gate would promote a version that never came up, which is RUN-3
failing in the one place it exists to hold. So the answer states what this
instance has actually reached and says `starting`, naming what it is waiting
for, until every enabled part is up. `Chain` already has the type and already
says this in its own doc comment (`Sources/Chain/ChainHealth.swift:134-199`),
and nothing has ever called it.

## Decisions

Each of these could have gone another way. The other way is written beside it,
so somebody can disagree now rather than after the code exists.

**D1. One executable product, `bot`, from a thin target `BotMain`.** One
product so bare `swift run` is unambiguous, which is what the acceptance
criterion says a person types. *The other way:* two products, one that can sign
and one that cannot, making D9 a build-time choice. Rejected for now because
there is nothing to sign with, and a second product that differs from the first
by nothing is a lie about what the build does.

**D2. `Runtime` is a target, not a library product.** A product is a promise to
strangers, and a composition root is the least stable thing in the package. The
executable and the tests reach it as a target, exactly as `StoreTestKit` is
reached today. *The other way:* export it so somebody can embed the boot in
their own program. That is a real want, it can be granted later by adding one
line, and taking a product away cannot.

**D3. One place reads the process environment.** `Settings` is a value built
from a dictionary, answering the `(String) -> String?` lookup the `Gating`
loaders take (`Sources/Gating/TokenProfile.swift:179`) and the
`[String: String]` the `Chain` loaders take
(`Sources/Chain/ChainConfiguration.swift:132`), and recording every key it was
asked for. The snapshot is taken in `BotMain` and nowhere else, and `Runtime`
never calls `ChainConfiguration.loadFromProcessEnvironment(token:)`
(`Sources/Chain/ChainConfiguration.swift:165`), which is the other door onto the
machine. A test builds one from a literal dictionary. Both halves are enforced
by a source scan rather than by the compiler, and the spec says so plainly
rather than overclaiming (REQ-runtime-003, REQ-runtime-004).

**D4. The catalogue is the reason `Settings` records its reads.** Every
variable this build reads is described exactly once, with the name taken from
the module constant that owns it, a purpose, whether it is required and whether
it is a secret. Two things then become possible that are otherwise wishes: a
key read but not described fails the boot as an internal error, so an
undocumented variable cannot ship, and a variable that is set, carries a prefix
this build owns and was read by nobody is reported back, which is the typo
case ADOPT-9.a is about (REQ-runtime-005, REQ-runtime-006, REQ-runtime-007).
*The cost, stated:* the catalogue is a second place to edit when a module gains
a variable. That is the point, and the boot failure is what makes it happen.

**D5. Four verbs, no flags, no argument parsing dependency.** No argument runs;
`check` is the dry run; `rehearse` shows the operator their own rules over
invented members; `help` prints the four. `CommandLine.arguments` is enough,
and a parser dependency for four words would sit in `Package.resolved` forever
(REQ-runtime-025, REQ-runtime-026, REQ-runtime-027).

**D6. Three new variables, and not one of them is a boolean.** `STORE_PATH`
required and absolute, `HEALTH_PORT` required, and `HEALTH_ADDRESS` defaulting
to the loopback address. A fourth, a build revision the pipeline passes in, was
considered and cut: no acceptance criterion asks for it, `design.md` already
settles the version as a constant the release step edits, and a variable nobody
sets reads back as unknown in the one place an operator looks. `STORE_PATH` is
required rather than defaulted because a default path puts a community's records
somewhere nobody chose, and absolute because a supervisor that restarts from a
different working directory would otherwise hand the same command a different
and empty database, with a lease over a different file so neither copy knows
about the other. The listener defaults to loopback because a health endpoint
reachable from the internet on a first run is a decision nobody made. Port zero
is accepted so a test can bind without choosing a number, and the report prints
the port actually obtained (REQ-runtime-011, REQ-runtime-018).

*This is where my own first answer was overruled and it is worth recording.* I
would have given `HEALTH_PORT` a conventional default on the grounds that a
port is not somebody else's value and a collision costs a minute.
`requirements.md` makes it required. Required wins: the port is the address a
deployment gate is pointed at, and an operator who never chose it is an
operator whose gate is watching a port they did not know about.

**D7. The boot has three parts: the gates that decide whether this process may
exist, the bind, then the gates that decide whether it is ready.** The order is
fixed in code and not reorderable by configuration (REQ-runtime-008): the
spending banner, the configuration gate, the store gate, the request budget
restore, the bind, the chain gate, the chat gate, the loops.

The lease is taken before the bind rather than after, which is the one place
this order is arguable. The lease is the guard that protects money and it is
the cheaper of the two, so a doomed process should die on it as early as
possible, and the repository already committed to lease-first in writing.
*The other way:* bind first, so every later refusal is visible to a deployment
gate as `starting` with a named reason rather than as a refused connection.
That is a real advantage and it was weighed. The deciding argument is that two
files giving opposite orders for the same hazard is worse than either order.

Everything after the bind is a question of readiness rather than of existence,
and readiness is exactly what the health body is for.

**D8. The order is a compile-time requirement, not a comment.** A completed
bind returns a `ListenerBound` whose initialiser is internal to `Runtime`, and
the chat seam's connect call requires one, so identifying first does not
compile (REQ-runtime-010). The honest limit, which belongs in the spec: this
proves a bound listener exists, not that the bind happened first in wall clock
time, and a test constructs one to drive the seam.

**D9. That the build cannot spend is a property of what was linked, and it is
the first line of every start, printed before the configuration is even read.**
No type in this package conforms to `ReservePayer`
(`Sources/Reserve/ReservePayer.swift:38`), `BotMain` passes none, so the process
has no way to move anything, and the banner says exactly that
(REQ-runtime-022, REQ-runtime-023).

The structural part is the part that matters: **this change introduces no
boolean setting at all**, and nothing named for a mode, a test, a dry run or a
quieter log. BUILD-3.a says no setting that only quietens output may be
mistaken for one that stops money moving, and the bot this was ported from had
to carry a written warning that one of its flags was not a money switch. A
warning that a flag is not what it sounds like is the failure, not the fix
(REQ-runtime-024).

The forward rule, written here so the next change does not bolt it on: a signer
arrives as its own target and its own product, named in the manifest, and the
banner then names the payer and the public account it signs for. Whether a
build can pay stays answerable by reading `Package.swift`.

**D10. The health answer is `Chain`'s, reused rather than rewritten.** The body
is `ChainHealthReport.jsonBody` (`Sources/Chain/ChainHealth.swift:186`), which is
hand built on purpose so a monitoring check can grep it. `GET /health` is the
only route, 200 when every enabled component is reached and 503 otherwise, so a
gate that reads nothing but the code is still right (REQ-runtime-015). The
endpoint answers from state already in memory and makes no request of its own,
because SEE-1.b says checking must not cost the thing being checked and must
keep answering once the day's budget is gone.

The one exception is the provider proof probe, wired in because it exists for
this and has never had a caller (`Sources/Chain/ProviderProofProbe.swift`). It
sits outside the request governor deliberately, it caches, and it does nothing
at all unless `CHAIN_PROOF_HEADERS` is set, because an empty header list returns
before it probes (`Sources/Chain/ProviderProofProbe.swift:74`). A default
installation therefore makes no extra request. *The other way:* leave it
unwired. Rejected because a setting that is read and then ignored is the quiet
nothing ADOPT-9 exists to stop, and because HOST-5.a wants the instance to state
what it has been talking to rather than a document claiming it.

**D11. What the boot probe does with each kind of failure is a decision, not an
accident.** One call to `ChainReader.verifyAssetDecimals()`
(`Sources/Chain/ChainReader.swift:58`), one request, and `Chain` keeps its own
rule about mismatches.

- The node answered and contradicted the configuration
  (`assetDecimalsDisagree`, `assetNotFound`, or an `api` refusal of 401 or 403
  that `ChainError.isProviderQuotaRefusal` does not claim first,
  `Sources/Chain/ChainError.swift:100`): refuse, naming the variable to correct
  and never printing the node token.
- The node did not answer, or answered with anything else: stay up, leave the
  `chain` component unreached, retry. A node down at three in the morning must
  not stop a restart from coming back, and the health body naming `chain` is
  how the operator is told which piece is down (REQ-runtime-013, SEE-10).

Retries go through the governor like any other read and back off from five
seconds to a ceiling of fifteen minutes, so a node down overnight cannot spend
the day's budget on retries. When `CHAIN_VERIFY_ASSET_DECIMALS` is off the call
returns without reading (`Sources/Chain/ChainReader.swift:59`), no `chain`
component is declared, and the report says the node was not probed at start and
why. A health answer must never claim a reach it did not make.

**D12. The report prints a reading, never an echo.** CATALOG-6.a says looking at
the settings never shows a secret and ADOPT-9.a says a rung a typo dropped reads
as missing. Both hold at once because what is printed is what the bot made of
the value: a secret is `set` or `unset` and nothing else, no length, no prefix,
no hash; a URL is scheme, host and port; a ladder is its rungs with their
thresholds and the variable the list stopped at. There is no generic dump
anywhere: no `Mirror`, no `Encodable` configuration, no `description` of a whole
configuration value, so adding a line is a deliberate act (REQ-runtime-019,
REQ-runtime-020, REQ-runtime-021).

The guard is the strongest cheap one available: plant a unique sentinel in every
catalogue entry marked secret, including one inside a node URL's query, render
the report and every refusal, and assert no sentinel appears. `Chain` reads the
node token through a path that never parses and never echoes it
(`Sources/Chain/ChainConfiguration.swift:147`), but `notANumber(key:value:)` and
`unusableURL(key:value:)` do carry values, so the rule for the spec is: a secret
is never read through a loader that puts values in its errors.

**D13. Exit codes are distinct, and this is the decision I changed my mind
about.** 0 for a clean stop, 64 for a usage error, 69 for something already here
or unusable, 70 for an internal error, 78 for a configuration that is wrong
(REQ-runtime-029). My first answer was a single non-zero code, on the grounds
that every refusal already names its variable and a code table is a second
vocabulary to keep in step. The argument that wins is the supervisor's: a
machine restarting the process cannot read the sentence, and a wrong token, a
full disk and a held store want three different responses from it.

**D14. The listener is written here, over the platform's own sockets, and adds
no dependency.** One route, one method, one fixed response, no keep-alive, a
bounded read of the request line and nothing else honoured. The repository
already accepts hand-written C interop where the surface is tiny and the value
is high, which is `StoreSQLite`'s whole argument, and an HTTP framework is a
large surface for one route. Two rules go in the spec because they are the ones
that bite: the read is bounded, so a client that never sends a newline cannot
hold the loop, and `SO_REUSEPORT` is never set, because it silently permits the
second bind this bind exists to refuse.

**D15. One contract, `specs/runtime/`, written before the code, covering both
new directories.** `specs/store/store.spec.md` already covers three source
directories in one spec, so this is the shape the repository uses. Both
directories join `source_dirs` in `.specsync/config.toml`, because a source
directory that is not listed passes the gate unread, which AGENTS.md names as
the thing to avoid.

## Order of work

Each phase ends with something that runs and something that is tested. The
order puts the half most likely to be cut under time pressure, the refusal
path, first rather than last.

1. **Scope and contract.** Settle the workspace scope question in `tasks.md`,
   write `specs/runtime/runtime.spec.md` and its companions, and add the two
   source directories to `.specsync/config.toml`.
2. **Manifest and empty targets.** `Runtime`, `BotMain`, the `bot` product,
   `RuntimeTests`, strict concurrency on all of them, with the manifest
   comments saying why `Runtime` links no chat SDK and no database.
3. **Settings and the catalogue.** The value, the recorded reads, the
   catalogue, the internal error for an undescribed key, the audit of variables
   that were set and read by nobody.
4. **The refusal path.** The loaders composed in the order the existing code
   requires, the first refusal naming its variable, the four verbs, the exit
   codes. The first acceptance criterion is met and tested at the end of this
   phase.
5. **The startup report.** The spending banner, the version constant, the
   reading of every setting, the list-ended-at lines, the redaction rules and
   the sentinel test.
6. **Readiness and the listener.** The component model over
   `ChainHealthReport`, the socket listener, 200 against 503, the bind refusal,
   the port already in use.
7. **The boot sequence.** The eight gates in order, `ListenerBound`, the chat
   seam with no conformance and its ordering test, signals and clean shutdown.
8. **The live seams in `BotMain`.** The SQLite store, the governor restore, the
   node data source, the chain gate and its failure classification, the
   backoff. Then `rehearse`, which needs the configuration and the rules and
   nothing else.
9. **Documentation and CI.** The README state section, `docs/WHAT-IT-TALKS-TO.md`
   (there is a startup now, a second outbound call site and a process that
   writes files), the exit code table, `CHANGELOG.md`, the AGENTS.md table, and
   a CI smoke run of the binary with no configuration and with a fixture one.

## Deliberately out of scope

What is left out matters as much as what is in, and each of these was
considered rather than forgotten.

- **Any chat client.** No gateway, no commands, no embeds. The seam is declared
  and has no conformance. Adding the SDK here would put the largest dependency
  in the package into the same change as the boot order that exists to protect
  it.
- **Wallet verification.** Nothing signs a challenge and nothing records one.
- **Signing and paying.** No `ReservePayer` conformance, no key read, no
  mnemonic variable. See D9.
- **Sweeps, schedules and the reserve runner.** Nothing loops except the chain
  gate's retry. A sweep needs roles, which needs a chat client.
- **A `.env` file.** The environment is the environment. A file introduces a
  second source of truth and a precedence question, and CATALOG-10 already
  anticipates that argument for the admin page rather than for a dotfile.
- **TLS on the listener, and authentication on it.** Loopback by default, and
  an operator who exposes it puts the same proxy in front that they already run
  for everything else.
- **Metrics, a logging framework and a log file.** Plain lines on stdout and
  stderr. Apart from the store it is told to open, the process writes no files,
  and that sentence is worth keeping true for one more release.
- **A build plugin that stamps the real revision.** The report carries a
  version constant and says it is what the source claimed rather than implying
  more, so SEE-12 is half answered and says so. A plugin is a new moving part
  in the manifest and can come with the release process.
- **Any change to a merged module's contract.** If `Runtime` needs a new public
  function from `Chain`, `Store` or `StoreSQLite`, that is a separate change
  with its own spec delta. Two are already anticipated below.

## What would make this plan wrong

Three disagreements between this plan and its sibling artifacts have been
settled, and the answers are recorded here rather than deleted.

- **The health body's off list.** Settled: the off parts are named in the
  startup report and not in the `/health` body, because
  `ChainHealthReport.jsonBody` emits status, waiting and provider and nothing
  else (`Sources/Chain/ChainHealth.swift:186`) and a fourth key would change a
  merged module's contract, which the no-spec-change rationale says this change
  does not do (REQ-runtime-016).
- **What `BotMain` may depend on.** Settled: `Runtime` and `StoreSQLite`. The
  durable store is a live seam and lives in `StoreSQLite`, and keeping the
  dependency there is what lets `Runtime` take `any BotStore` and link no
  database (REQ-runtime-001).
- **The requirement numbering.** Checked rather than assumed: `testing.md`
  numbers `REQ-runtime-011` as the store gate and `REQ-runtime-012` as the
  budget restore, exactly as `requirements.md` does, and every id from 001 to
  031 appears in both. There is no clash to reconcile.

What could still make this plan wrong is the boundary with the change being
defined alongside it, `satisfy-four-criteria-...-was-counted`. REQ-runtime-032
names the split. If that change ships a health value this plan has assumed is
Chain's today, or makes a caller required on `ChainReader` before this lands,
the second change to land carries the edit, and both definitions say so.

One more, smaller: if the hand-written listener turns out to need a second
route before the chat surface lands, the no-dependency argument in D14 should
be reopened rather than stretched.
