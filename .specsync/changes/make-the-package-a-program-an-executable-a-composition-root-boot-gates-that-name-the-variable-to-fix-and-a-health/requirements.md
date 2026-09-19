---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: requirements
---

# Requirements

Six libraries and no program. Everything below exists to turn that into one
binary that an operator can start, that refuses in a way they can act on, and
that a supervisor can ask whether it is really working. Nothing below adds a
Discord client, a wallet or a verification flow: this change is the frame those
three will be hung on, and the frame has to be honest about being empty.

**Two id namespaces, on purpose.** The requirements below are `RT-<n>`: they
belong to this workspace, they are how the plan, the tasks and the testing map
refer to each other, and they are archived with the change. The canonical
module contract uses `REQ-runtime-<n>`, in `deltas/runtime.md` and later in
`specs/runtime/`, and it has different numbers because it consolidates these
thirty two into twenty two guarantees. One numbering for both would have meant
every reference here pointing at a requirement that says something else, which
is how a reader ends up building the wrong thing while believing they followed
the document. The delta names which of these each guarantee carries.

Two rules run through all of it and are worth stating before the list.

**A refusal names the variable.** The package already works this way in every
loader (`Sources/Gating/NumberedEnvironment.swift:113` and the
`GatingConfigurationError.missing(key:purpose:)` it throws). The composition
root's job is to keep that property on the way out through a process exit
rather than losing it in a wrapped error.

**A bound socket is not health.** The listener binds before anything could
identify to a chat service, so binding is what tells a second copy that a first
one is already here. That makes the socket useless as a readiness signal, which
is why the endpoint has to say `starting` until the parts that must be up are
up.

## User Stories

- As an operator, I want a clean machine to tell me the first variable to set
  and what it is for, rather than starting and failing at the first sweep
  (ADOPT-2, RUN-9.a, RUN-9.b).
- As an operator, I want to read back what the bot made of my settings every
  time it starts, and never to find a secret of mine in that output
  (ADOPT-9, ADOPT-9.a, CATALOG-6.a).
- As an operator, I want one check that tells me whether it is really working,
  and I want a version that came up half way never to be promoted over the one
  that was working (SEE-1, SEE-1.a, RUN-3).
- As an operator, I want a second copy started by accident to be the one that
  stops, and the copy already serving my server to carry on serving it
  (RUN-7, RUN-7.a).
- As an operator, I want a restart to cost me nothing I have already spent,
  including the day's budget for reading the chain (RUN-8, RUN-8.b).
- As an operator, I want to know which parts are switched off and why, so that
  a community with a token and no collections is a whole setup rather than a
  broken one (ADOPT-10, ADOPT-10.a, BUILD-1.a).
- As a contributor with a laptop and no keys, I want the program to do
  something useful for me without a server, a funded wallet or a place to
  prove a wallet (BUILD-1, BUILD-1.b, BUILD-2.b).
- As a contributor, I want a build that cannot spend to say so at every start,
  and I want that to be a fact about the build rather than a flag somebody
  could flip by accident (BUILD-3, BUILD-3.a, BUILD-3.b).
- As somebody deciding whether to install this, I want the list of what it
  reaches and what it asks for to still be true after this change, including
  the socket it now opens on my machine (TRUST-1, TRUST-1.b).

## Acceptance Criteria

### The package and the graph

#### RT-001

The package SHALL gain one library target `Runtime`, holding the composition
root, the boot sequence, the settings catalogue, the startup report, the health
state and the health listener, and one executable target `BotMain` exported as
the executable product `bot`. `Runtime` SHALL depend on `Gating`, `Chain` and
`Store` only: not on `Games` or `Reserve`, which nothing in this change
reaches, and not on `StoreSQLite`, because it takes `any BotStore`. `BotMain`
SHALL depend on `Runtime` and on `StoreSQLite` and on nothing else, and
SHALL contain only argument handling, the process environment snapshot, the
construction of the live seams, signal handling and the exit.

- Covered by `Package.swift` and `RuntimeCompositionTests.swift` (ADOPT-4,
  BUILD-4).

#### RT-002

`Runtime` SHALL declare the chat seam as its own protocols over Foundation
types, with a role and a member both named by `String`, and this change
SHALL add no chat client package dependency to the manifest. A chat adapter, when one
arrives, SHALL be a separate target depending on `Runtime`, so that the
manifest's own cycle rule forbids `Runtime` and therefore `Store` from
depending on it.

- Covered by `Package.swift` and `docs/WHAT-IT-TALKS-TO.md` (TRUST-1.b,
  BUILD-4).

#### RT-003

`Runtime` SHALL NOT read the process environment. The only reference to
`ProcessInfo.processInfo.environment` in `Sources/` SHALL be the single
snapshot taken in `BotMain`, and the composition root SHALL NOT call
`ChainConfiguration.loadFromProcessEnvironment(token:)`
(`Sources/Chain/ChainConfiguration.swift:165`), which is the other door onto
the machine's settings.

- Covered by `SettingsSourceTests.swift`, which walks the sibling directories
  of its own `#filePath` and fails on a match (BUILD-2.a).

### Settings, read once and described once

#### RT-004

`Settings` SHALL be a value built from a dictionary, SHALL answer the
`(String) -> String?` lookup every existing loader already takes, and
SHALL record every key it was asked for. A test SHALL build one from a literal
dictionary with no access to the machine.

- Covered by `SettingsTests.swift` (BUILD-2, BUILD-2.a).

#### RT-005

The catalogue SHALL describe every variable this build reads exactly once,
each entry carrying the variable name taken from the module constant that owns
it, a purpose sentence, whether it is required, and whether its value is a
secret. Numbered families SHALL be described as families rather than as
thirty-two entries each.

- Covered by `SettingsCatalogueTests.swift` (TRUST-1, ADOPT-9).

#### RT-006

Boot SHALL fail with an internal error when a loader asked `Settings` for a key
the catalogue does not describe, so that a variable added to a module without
being described cannot ship undocumented.

- Covered by `SettingsCatalogueTests.swift` (TRUST-1, ADOPT-9).

#### RT-007

A variable that is set, carries a prefix this build owns, and was read by
nothing SHALL be reported in the startup report, together with the catalogue
entry it is within one edit of when there is one, and SHALL NOT refuse the
boot. A variable carrying a prefix this build reserves for a part it does not
have SHALL refuse the boot, naming the variable and saying the part is not in
this build.

- Covered by `SettingsAuditTests.swift` (ADOPT-9.a, ADOPT-2, RUN-9.a,
  BUILD-4).

### The boot sequence

#### RT-008

The boot sequence SHALL run its gates in this order and SHALL NOT be
reorderable by configuration: the spending banner, the configuration gate, the
store gate, the request budget restore, the listener bind, the chain gate, the
chat gate, the loops. Each gate SHALL either pass, or stop the process with the
exit code in RT-029 and a message naming what to change.

- Covered by `BootSequenceTests.swift` (RUN-9.a, SEE-11).

#### RT-009

`bot` with an empty environment SHALL exit non-zero with the configuration code
and SHALL print the name of the first variable to set, the purpose sentence the
loader carries for it, and the one command that lists the rest. With the
package as it stands that first variable is `TOKEN_ASSET_ID`, because
`GatingConfiguration.load` reads the token before anything else
(`Sources/Gating/GatingConfiguration.swift:102`).

- Covered by `BootSequenceTests.swift` and `CommandLineTests.swift` (ADOPT-2,
  RUN-9.a, BUILD-1).

#### RT-010

Nothing SHALL be able to identify to a chat service before the listener has
bound. This SHALL be enforced by the types rather than by the order of two
statements: a successful bind SHALL return a `ListenerBound` value whose
initialiser is internal to `Runtime`, and the chat seam's connect call
SHALL require one, so that identifying first does not compile.

- Covered by `BindBeforeIdentifyTests.swift`, which binds on port zero and
  asserts the recorded order on a spy gateway (RUN-7, RUN-7.a, RUN-3).

#### RT-011

The store gate SHALL open the durable store before any socket is bound, so that
the exclusive lease (`Sources/StoreSQLite/InstanceLease.swift:43`) is what
discovers a second instance. `STORE_PATH` SHALL be required and SHALL be
refused when it is relative, because a supervisor that restarts the process
from a different working directory would otherwise hand the same command a
different and empty database. A store already held by another process
SHALL stop this one with the unavailable code and a message saying the other copy
keeps serving.

- Covered by `BootSequenceTests.swift` and `StoreGateTests.swift` (RUN-7.a,
  SEE-8, ADOPT-2).

#### RT-012

The day's request count SHALL be restored from the store into the shared
`RequestGovernor` (`Sources/Chain/RequestGovernor.swift:75`) before the first
chain request of the process, and one governor SHALL be shared by everything
that reads or signs.

- Covered by `BootSequenceTests.swift` (RUN-8.b, RUN-10.a, SEE-9).

#### RT-013

The chain gate SHALL call `ChainReader.verifyAssetDecimals()`
(`Sources/Chain/ChainReader.swift:58`) when it is enabled, and SHALL refuse the
boot only on an answer that contradicts the configuration: `assetNotFound`,
`assetDecimalsDisagree`, or an `api` refusal with status 401 or 403, each
naming the variable to correct. A `network` failure, or any other `api`
refusal, SHALL leave the chain component unreached and SHALL NOT stop the boot.
An unreached chain component SHALL be retried through the same request
governor, backing off from five seconds to a ceiling of fifteen minutes, so
that a node down overnight cannot spend the day's budget on retries and a node
that comes back moves the health answer from `starting` to `ok` without a
restart.

- Covered by `ChainGateTests.swift` with a stub data source (ADOPT-12.a,
  ADOPT-2, SEE-10.a, RUN-3).

#### RT-014

A build with no chat surface SHALL refuse to start when a variable belonging to
one is set, naming the variable and stating that this build has no chat
surface, rather than starting, answering healthy and never appearing in the
server.

The reserved set SHALL be stated in the code as a list of prefixes, not left
to whoever implements this. It is `DISCORD_` and `VERIFY_`, and the variable
that will actually be hit is `DISCORD_BOT_TOKEN`, which is the first thing a
new operator of a package called `discord-bot` will set. Naming it matters
because there is no chat module yet whose constants could be enumerated, so
without this sentence one implementer reserves the whole `DISCORD_` prefix,
another reserves one variable, and a third adds the portal keys: three
different boots from one environment file.

This also makes a rollback from a later chat-capable build a boot refusal
until the operator edits their environment, which is a real cost and is
accepted here rather than discovered: a variable that silently does nothing is
how somebody concludes the bot is ignoring their token.

- Covered by `SettingsAuditTests.swift` (RUN-9.a, BUILD-4, SEE-1.a).

### The health listener

#### RT-015

The listener SHALL answer `GET /health` and nothing else, SHALL return 200 with
the report body when every enabled component has been reached and 503 with the
same body otherwise, and SHALL use `ChainHealthReport.jsonBody`
(`Sources/Chain/ChainHealth.swift:186`) rather than a second spelling of the
same shape. A bound socket with no component reached SHALL read as
`{"status":"starting","waiting":[...]}`.

An instance that has been reached but whose chain reads are throttled or
paused SHALL answer **200**, because it is ready: it is serving, and a spent
budget is a fact in the body for monitoring to alert on, not a reason to take
the instance out of rotation. Not reached outranks throttled, so an instance
that is both SHALL answer 503. This mapping is stated here because the sibling
change (RT-032) settles the status at two values and adds the budget
as a body field, which leaves the HTTP code for the throttled case belonging
to nobody unless this sentence exists.

- Covered by `HealthListenerTests.swift` (SEE-1, SEE-1.a, RUN-3).

A body assertion SHALL pin what `ChainHealthReport` renders rather than a
literal frozen here, because the sibling change in RT-032 appends a
budget section to the same body.

#### RT-016

The component list SHALL hold one entry per part the operator switched on, and
a part that is off SHALL contribute no component and SHALL instead be listed as
off in the startup report. It SHALL NOT be listed in the `/health` body:
`ChainHealthReport.jsonBody` emits status, waiting and provider and nothing
else, and a fourth key would be a change to `Chain`'s contract, which this
change does not make. An instance with nothing to wait for SHALL read as `ok`.

- Covered by `HealthListenerTests.swift` (BUILD-1.a, ADOPT-10, ADOPT-10.a,
  SEE-10).

#### RT-017

Answering a health request SHALL cost no chain request, and SHALL still answer
when the day's budget is spent or the governor is paused. Any provider proof in
the answer SHALL come from the cached probe
(`Sources/Chain/ProviderProofProbe.swift:26`), which deliberately does not go
through the governor, and SHALL be read without probing: `proof(now:)` refreshes
when its cache is stale, so answering through it would put a network call on the
request path. The non-probing read is the one piece RT-032 names the
sibling change as shipping; until it exists this requirement is met by
refreshing the probe off the request path and answering from what is held.

The refresh SHALL happen on the runtime's own schedule, never inside the
handler.

- Covered by `HealthListenerTests.swift` with a governor whose budget is
  exhausted (SEE-1.b, SEE-10.a).

#### RT-018

`HEALTH_PORT` SHALL be required, `HEALTH_ADDRESS` SHALL default to the loopback
address, the bind SHALL report the port actually obtained, and the startup
report SHALL print it. Port zero SHALL be accepted, so a test can bind without
choosing a number.

- Covered by `HealthListenerTests.swift` (HOST-6, ADOPT-2).

### The startup report

#### RT-019

A startup report SHALL be written at every start, including one that then
refuses, and SHALL NOT be suppressible by any setting. It SHALL contain: the
spending banner, the version, what the build made of the settings, which parts
are on and which are off with a reason each, the address and port bound, the
store migrations applied and whether the store file was created by this start,
and the settings audit from RT-007.

- Covered by `StartupReportTests.swift` (ADOPT-9, BUILD-3.b, SEE-12, SEE-8).

#### RT-020

The report SHALL never contain the value of an entry the catalogue marks as a
secret. A secret SHALL be reported as set or unset and nothing else: no length,
no prefix, no hash. A fact derived from a secret SHALL appear only where the
catalogue entry names that derived fact and the fact is public by construction,
such as the address belonging to a signing key. Every value that is a URL
SHALL be reported as scheme, host and port only, because a provider URL can carry a
credential in its path and the report is meant to be safe to paste into an
issue.

- Covered by `StartupReportSecretTests.swift`, which sets a unique sentinel for
  every secret entry in the catalogue and asserts no sentinel appears anywhere
  in the rendered report (CATALOG-6.a, ADOPT-9.a, TRUST-1).

#### RT-021

The report SHALL state what was made of the settings and not only that they
loaded: every rung of the ladder with its name and its threshold in whole
tokens and in smallest units, every collection, every pool, the size and
contents of the admin allowlist, and the network the node URL points at. A rung
a typo dropped SHALL be visible there as a shorter ladder before any sweep acts
on it.

- Covered by `StartupReportTests.swift` (ADOPT-9, ADOPT-9.a, ADOPT-12.b,
  CATALOG-7).

### Spending

#### RT-022

Whether a build can spend SHALL be a parameter of the composition and never a
reading of the settings. No code path SHALL exist from `Settings` to the
spending capability, and a test SHALL set every catalogue variable to each of a
truthy and a falsy value and assert the capability is exactly what the caller
passed.

- Covered by `SpendCapabilityTests.swift` (BUILD-3, BUILD-3.a, HOST-7,
  SPEND-6.c).

#### RT-023

The spending banner SHALL be the first line of every start, before the
configuration is even read, and SHALL say either that this build has no way to
move anything, naming that no payer is compiled in, or that it can sign, naming
the payer and the public account it signs for. At this commit the package
contains no `ReservePayer` implementation, so every build SHALL print the first
form, and that SHALL be a consequence of the graph rather than of a default.

- Covered by `SpendCapabilityTests.swift` and `StartupReportTests.swift`
  (BUILD-3.b, SPEND-6.c, HOST-7.a).

#### RT-024

The catalogue SHALL contain no variable whose effect is to stop money moving,
and this change SHALL introduce no `TEST_MODE`, `DRY_RUN` or `SAFE_MODE`. A
variable that only changes how much is printed or where it is printed SHALL be
described in the report under a heading saying in words that it stops nothing
moving.

- Covered by `SettingsCatalogueTests.swift` (BUILD-3.a).

### What the program does

#### RT-025

The executable SHALL take `run` as its default with no arguments, and
SHALL also take `check`, `rehearse` and `help`. An unrecognised argument SHALL exit
with the usage code and print the four.

- Covered by `CommandLineTests.swift` (ADOPT-4, BUILD-1).

#### RT-026

`check` SHALL run the configuration gate and print the same startup report the
boot would, and SHALL open no socket, no store file and no network connection.
With nothing set it SHALL print the whole catalogue with each entry marked set
or unset, together with the first refusal, and exit with the configuration
code.

- Covered by `CommandLineTests.swift` (RUN-9, RUN-9.b, ADOPT-9, BUILD-1).

#### RT-027

`rehearse` SHALL load the operator's own configuration, run the role rules over
members, accounts and holdings it invents, and print the decision for each, and
SHALL open no socket, no store file and no network connection. It SHALL invent
members and holdings only, never configuration, so that what a contributor
watches is their own ladder rather than somebody else's.

- Covered by `RehearsalTests.swift` (BUILD-1.b, BUILD-1, ADOPT-6.a).

### Lifecycle

#### RT-028

On `SIGINT` or `SIGTERM` the process SHALL stop the listener, close the store,
which releases the lease, and exit zero. A second signal SHALL exit
immediately.

- Covered by `LifecycleTests.swift` (RUN-7.a, SEE-8).

#### RT-029

Exit codes SHALL be distinct and documented: 0 for a clean stop, 64 for a usage
error, 69 for something already here or unusable, being a held store, an
address in use or a volume that cannot promise a write, 70 for an internal
error, and 78 for a configuration that is wrong. A single code for every
failure SHALL NOT be used, because a supervisor cannot tell a wrong token from
a full disk from one number.

- Covered by `CommandLineTests.swift` and `BootSequenceTests.swift` (RUN-3,
  RUN-7, SEE-11).

### The obligations that come with it

#### RT-030

Every criterion above SHALL be exercised by a test that needs no Discord, no
chain, no wallet and no database anybody installed. The store in those tests
SHALL be `SQLiteStore.inMemory()` or a file the test made under its own
temporary directory, the chain SHALL be a stub `AccountDataSource`, the chat
SHALL be a spy, and the only socket SHALL be a loopback bind on port zero,
which reaches no real chain, server or account.

- Covered by the whole of `Tests/RuntimeTests/` (BUILD-2, BUILD-2.a,
  BUILD-2.b).

#### RT-031

`docs/WHAT-IT-TALKS-TO.md` SHALL be updated in the same pull request to say
that the package now listens on a socket, which address and port it listens on
by default, what the answer contains, and that the answer can carry provider
proof headers. `.specsync/config.toml` SHALL list `Sources/Runtime` and
`Sources/BotMain`, and `specs/runtime/` SHALL exist, or the gate fails rather
than passing an undescribed target.

- Covered by `specsync check --strict` and by review of
  `docs/WHAT-IT-TALKS-TO.md` (TRUST-1, TRUST-1.b).

#### RT-032

This change SHALL add no health vocabulary of its own. The status, the waiting
list and the JSON body belong to `Chain`, and the change being defined
alongside this one,
`satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted`,
owns the `Chain` half of SEE-1.b: the pure assembly of a report from values, the
non-probing read of the last provider proof, and the budget and pause facts in
the body. This change SHALL consume those and SHALL ship the listener, the one
route, the HTTP mapping, the component list, the probe instance and its
refresh, and the test that the endpoint answers with the day's budget spent. A
spent budget or a live pause SHALL be a fact in the body and SHALL NOT make the
endpoint fail, so that a deploy gate cannot roll back a working version over a
provider quota. Where that change makes every public read on `ChainReader` name
its caller with no default, the chain gate in RT-013 SHALL name the
instance's own work rather than a member, and whichever of the two changes
lands second SHALL carry that edit.

- Covered by `HealthListenerTests.swift` and by review of both definitions
  (SEE-1.b, SEE-1.a, RUN-3, RUN-11).
