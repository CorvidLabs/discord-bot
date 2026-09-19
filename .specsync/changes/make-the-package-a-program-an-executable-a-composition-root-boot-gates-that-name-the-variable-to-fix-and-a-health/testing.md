---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: testing
---

# Testing

Everything this change adds happens in the first two seconds of a process,
which is the part of a program nobody tests, because testing it usually means
starting it. So the plan rests on one property of the design: every gate,
every ordering, every line of the startup report and every health answer is a
**value** that a test builds and reads, and `BotMain` is the thin thing that
turns one of those values into an exit code. A behaviour that can only be
observed by running the binary and reading a terminal has not been designed
yet, and belongs back in `design.md` rather than in a manual checklist.

Beside each requirement is what its test must **fail** against. A test that
passes against both the right implementation and the wrong one proves nothing,
and every wrong implementation named below is one somebody would plausibly
write: an empty component list that reads as healthy, a report assembled from
the operator's file rather than from what was loaded, a second read of the
process environment, a capability printed from a `Bool`.

## What a test here may touch

`swift test` stays offline (BUILD-2), and REQ-runtime-030 is the requirement
that says so. Three clarifications a reader will otherwise ask about.

- **A loopback bind is not a network.** `HealthListenerTests` and
  `BindBeforeIdentifyTests` bind `127.0.0.1` on port zero, ask the kernel which
  port they got, and connect to that. Nothing leaves the loopback interface, so
  BUILD-2.a, which is about reaching a real chain, a real server or a real
  account, is intact. Those same tests assert the bound address **is** the
  loopback one, which is how the default in REQ-runtime-018 stays chosen rather
  than becoming whatever somebody edited later.
- **A temporary file is not a database anybody set up.** Tests that do not care
  about durability compose `SQLiteStore.inMemory()`
  (`Sources/StoreSQLite/SQLiteStore.swift:152`) or `InMemoryStore`. The two
  that care, the lease and the created-file report, make a directory under the
  test's own temporary directory and remove it whether the body passes or
  throws, in the shape `Tests/StoreSQLiteTests/SQLiteProbes.swift` already
  uses. No new fixture idiom.
- **The chain is a stub.** Every chain gate case runs against a stub
  `AccountDataSource`, which is the seam that exists so the failure paths are
  reachable at all (`Sources/Chain/AccountDataSource.swift`). No test in this
  target constructs a node client.

If a sandboxed runner refuses a loopback bind, the fallback is **not** to drop
the assertion. Only the two socket suites need a socket; the boot sequence,
the report and the settings suites need none. A socket suite that skips must
say so loudly, in the manner of `Tests/StoreTests/InMemoryConformanceTests.swift`,
which asserts that the set of behaviours it skipped is exactly the expected
set. A quiet skip is a green build that proves less than it claims.

## Where the tests live

All of it is one new test target, `Tests/RuntimeTests/`, depending on
`Runtime`, `Store` and `StoreSQLite`, the last because the fixtures compose
`SQLiteStore.inMemory()` and a temporary store directory. Each test is named for the criterion it protects, which is the
convention `AGENTS.md` already sets.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `RuntimeFixtures.swift` | Fixture | One valid settings dictionary and the smallest edit that breaks it in each documented way; a spy chat gateway; a stub `AccountDataSource`; a store in memory; a temporary store directory helper. Nothing here can reach anything. |
| `RuntimeCompositionTests.swift` | Source | The target graph: who depends on whom, who is a product, and which directories may name a chat client. |
| `SettingsSourceTests.swift` | Source | That `Runtime` cannot reach the machine's settings, and that the one snapshot lives in `BotMain`. |
| `SettingsTests.swift` | Unit | `Settings` as a value: the lookup the existing loaders take, the record of what was asked for, and the trimming rules it inherits. |
| `SettingsCatalogueTests.swift` | Unit | The catalogue against the module constants that own the names, the secret flags, the families, and the refusal of a key nobody described. |
| `SettingsAuditTests.swift` | Unit | Owned variables nothing read, near misses, and the refusal on a prefix reserved for a part this build does not have. |
| `BootSequenceTests.swift` | Unit | The eight gates: their order, what each refuses, with which code, and what is left behind when one refuses. |
| `StoreGateTests.swift` | Unit | `STORE_PATH` required and absolute, a store already held, a store this start created. |
| `ChainGateTests.swift` | Unit | Which node answers contradict the configuration and which are merely an outage. |
| `BindBeforeIdentifyTests.swift` | Integration | A real loopback bind, a spy gateway, and the recorded order of the two. |
| `HealthListenerTests.swift` | Integration | The one path, the two status codes, the body, the components, and answering while the boot is still running. The off parts are asserted in the startup report, not in the body. |
| `StartupReportTests.swift` | Unit | What the report says, in full, for a known configuration. |
| `StartupReportSecretTests.swift` | Unit | The sentinel sweep: no secret's value anywhere in the rendered report. |
| `SpendCapabilityTests.swift` | Unit | That no setting can reach the spending capability, and that the banner says what the composition was handed. |
| `CommandLineTests.swift` | Unit | The four verbs, the default, the usage failure, and the exit code for each outcome. |
| `RehearsalTests.swift` | Unit | That `rehearse` runs the operator's own ladder over invented members and touches nothing. |
| `LifecycleTests.swift` | Unit | Shutdown: the listener stopped, the store closed, the lease released, the second signal. |

## Requirement coverage

Each heading names the requirement and states what it asks, so a drift from
`requirements.md` shows up here rather than during `specsync change check`.

### The package and the graph

**REQ-runtime-001, one library target and one executable.**
`RuntimeCompositionTests.swift` reads `Package.swift` and asserts: `Runtime`
appears in no product's target list; the executable product names `BotMain` and
only `BotMain`; `BotMain`'s source directory holds one file. The last one is
worth asserting rather than trusting, because everything the graph promises
rests on `BotMain` being too small to hide anything.
*Fails against:* `Runtime` promoted to a library product, which would make the
composition root's shape a compatibility promise at the moment it is least
stable; and an executable target that grows logic nobody can test.

**REQ-runtime-002, the chat seam is Foundation types and no new dependency.**
`RuntimeCompositionTests.swift` asserts no chat package appears in
`Package.swift`, and that the seam's protocol names a role and a member as
`String`. `Package.resolved` is asserted unchanged in review rather than by a
test, and `docs/WHAT-IT-TALKS-TO.md` is where a reader checks it.
*Fails against:* a seam declared in terms of a client's own types, which would
drag the dependency in the first time anybody implemented it.

**REQ-runtime-003, `Runtime` never reads the process environment.**
`SettingsSourceTests.swift` walks the source directories beside its own
`#filePath`, in the manner of `Tests/StoreSQLiteTests/TargetShapeTests.swift:17`,
and asserts `ProcessInfo` appears zero times under `Sources/Runtime` and
exactly once under `Sources/BotMain`. It also asserts the string
`loadFromProcessEnvironment` appears nowhere in either. That one is not
hypothetical: the second door already exists at
`Sources/Chain/ChainConfiguration.swift:165` and stays public for other hosts.
*Fails against:* a composition root that falls back to the real environment
when the `Settings` it was handed lacks a key. That is the dangerous one,
because every test still passes on a developer machine with the variables
exported, and it fails only for the person who has none of them, who is exactly
the person BUILD-1 is written for.
*Known weakness, stated in `design.md` and repeated here:* this is a source
scan, not a type. Nothing stops a future edit writing `ProcessInfo` into
`Runtime` except this test, so the test must name the rule in its own failure
message rather than just failing on a path.

### Settings, read once and described once

**REQ-runtime-004, `Settings` is a value.** `SettingsTests.swift` builds one
from a dictionary literal and drives every loader through it, which is only
possible if the seam is real. It also pins the two trimming rules the package
already has, because the report must agree with the loaders: a variable set to
the empty string reads as unset (`Sources/Gating/NumberedEnvironment.swift:81`),
and a value with the trailing newline a file gives it reads trimmed, which is
the bug the shared rule was written for.
*Fails against:* a `Settings` that normalises differently from
`NumberedEnvironment`, which would make the report describe a configuration
the loaders did not see.

**REQ-runtime-005, the catalogue describes every variable exactly once.**
`SettingsCatalogueTests.swift` asserts every key constant exported by `Gating`
and `Chain` appears in the catalogue: `TokenProfile.assetIdKey`,
`GatingConfiguration.verifiedRoleKey`, every member of `ChainEnvironment`, and
the rest. It asserts each entry's name is the constant rather than a string
literal, by comparing against the constants themselves. It asserts no name
appears twice, and that numbered families appear once as a family.
*Fails against:* a catalogue typed out by hand, which drifts the first time a
library target gains a variable, and takes the README and the disclosure
document with it. This is the test that lets both documents be read off a
`check` run instead of maintained by memory.

**REQ-runtime-006, a key read but not described fails the boot.**
`SettingsCatalogueTests.swift` drives a loader that asks for an undescribed key
and asserts the internal error and code 70.
*Fails against:* a catalogue that is merely documentation. The point of the
recording lookup is that the catalogue cannot be incomplete and silent at the
same time.
*The case somebody will forget:* a key asked for and **absent** must count as
asked for. Otherwise an optional variable nobody has set is undescribable, and
the check only bites on machines where the variable happens to be set.

**REQ-runtime-007, owned but unread is reported, reserved refuses.**
`SettingsAuditTests.swift`: `TOKEN_ASSETID` and `TIER_4_MIM` are both reported
as read by nothing, with the near miss named where there is one, and neither
refuses the boot. `TIER_5_NAME` above a gap at rung 4 is reported the same way,
which is the dropped rung told from the other end and the form an operator
recognises. A variable with no owned prefix is not reported at all, because a
checker that shouts about every unrelated variable in an environment file is
ignored within a week. A variable on a reserved prefix refuses, with code 78,
naming the variable and saying the part is not in this build.
*Fails against:* an unread check built from a static key list, which by
construction cannot see `TOKEN_ASSETID`; and a check that refuses on an
unrecognised name inside an owned prefix, which breaks a staged deploy in both
directions.
*How the two halves differ, which the test names should say:* the `Gating`
loaders take a lookup (`Sources/Gating/TokenProfile.swift:179`), so the
recording `Settings` sees every key they asked for. `ChainConfiguration.load`
takes a dictionary (`Sources/Chain/ChainConfiguration.swift:132`) and can be
observed by nothing, so its keys come from the constants `ChainEnvironment`
already exports. One mechanism cannot cover both, and making `Chain` take a
lookup would be a change to a merged contract this change has declared it is
not making.

### The boot sequence

**REQ-runtime-008, eight gates in a fixed order.**
`BootSequenceTests.swift` runs a whole boot against the fixtures and asserts
the recorded order of the gates, then asserts that no setting reorders them by
running the same boot under a settings dictionary with every optional variable
flipped. Each gate has its own case for its refusal and its code.
*Fails against:* a boot whose order is an accident of statement order in one
function, and one where an optional variable changes which gate runs first.
*The case somebody will forget:* a refusal must leave nothing behind. The test
asserts that after a gate 5 or 6 refusal there is no bound socket and no held
lease, not merely that later gates did not run. A process that exits holding a
socket is the next restart's failure.

**REQ-runtime-009, an empty environment names one variable.**
`BootSequenceTests.swift` and `CommandLineTests.swift`: the empty dictionary
exits 78, the message contains `TOKEN_ASSET_ID`, the loader's own purpose
sentence (`Sources/Gating/GatingConfigurationError.swift:80`) and the line
pointing at `check`. Then one case per required variable, each removed from the
otherwise valid fixture on its own, asserting the message names that variable
and no other.
*Fails against:* an exit code of zero, which is the failure a deploy gate
cannot see; a message that says the configuration is invalid without naming
anything; and an order that reports `CHAIN_NODE_URL` to somebody who has not
set the token either, because then fixing what you were told changes what you
are told next, and the operator learns the tool is guessing.

**REQ-runtime-010, identifying before binding does not compile.**
The compiler is the guard: `ListenerBound` has an initialiser internal to
`Runtime` and the chat seam's connect takes one. A compile failure cannot be a
test case, so `BindBeforeIdentifyTests.swift` is the failable half: it binds on
port zero, connects a spy gateway, and asserts the recorded order. It also
asserts that the spy was handed the same `ListenerBound` the bind produced, so
a value manufactured elsewhere would show up.
*Fails against:* an ordering held by a comment, which is exactly the
arrangement this change exists to end.
*The correction worth writing into the test names:* the bind is not the
duplicate guard. The port is configuration, so a second instance on a different
port binds happily. The lease is the duplicate guard, and REQ-runtime-011 is
where that is tested. The two are asserted separately so neither can be deleted
on the grounds that the other covers it.

**REQ-runtime-011, the store gate before the socket.**
`StoreGateTests.swift`: a relative `STORE_PATH` refuses with 78 naming the
variable, because a supervisor starting the process from another directory
would otherwise hand the same command a different, empty database. A store
already held refuses with 69 and a message saying the other copy keeps serving;
the lease itself is already covered by `aSecondStoreIsRefused` in the store's
conformance suite, so what is new here is the translation into something an
operator can act on (SEE-11). A store file this start created is reported as
created (`Sources/StoreSQLite/SQLiteStore.swift:91`).
`BootSequenceTests.swift` asserts the lease is taken before the bind.
*Fails against:* a runtime that binds first and discovers the duplicate second,
which is the ported bot's order and the wrong one once a port is configuration;
and a runtime that reports a store it invented as one it found, which makes a
lost volume indistinguishable from a first run.

**REQ-runtime-012, the day's request count is restored before the first
request.** `BootSequenceTests.swift`: a store carrying a count from earlier the
same UTC day produces a governor already holding it, and the restore happens at
gate 4, before the chain gate at 6. One governor, shared: the test asserts the
same instance reaches the reader and everything else that spends.
*Fails against:* a restart that hands the process a fresh allowance (RUN-8.b),
and two governors, which let the process spend twice the ceiling.
*The case somebody will forget:* a count written **yesterday** must not be
restored into today. `Chain` already tests that rule; the runtime test asserts
the runtime does not defeat it by restoring unconditionally.

**REQ-runtime-013, only a contradiction stops the boot.**
`ChainGateTests.swift`, one case per answer: `assetNotFound` refuses,
`assetDecimalsDisagree` refuses, an `api` refusal with 401 and one with 403
refuse, each naming the variable to correct. A `network` failure does not
refuse and leaves the chain component unreached; a 500 does the same.
*Fails against:* a boot that refuses on any chain error, which turns a
provider's bad five minutes during a restart into a bot that stays down until
somebody notices; and a boot that refuses on none, which lets a live server run
against a test network (ADOPT-12.a).
*The consequence that must also be asserted:* after a `network` failure the
health answer is `starting` with `chain` in `waiting`. That is the whole safety
of not refusing, and it is only safe if it is true.

**REQ-runtime-014, a chat variable on a build with no chat surface refuses.**
`SettingsAuditTests.swift`: the reserved prefix refuses with 78, naming the
variable and saying this build has no chat surface.
*Fails against:* a build that starts, answers healthy and never appears in the
server, which is the three hour outage the SEE family opens with.

### The health listener

**REQ-runtime-015, one path, two codes, one body.**
`HealthListenerTests.swift`: `GET /health` answers; every other path and every
other method answers 404. 200 when every enabled component is reached, 503
otherwise, with the same body both ways. The body is compared against what
`ChainHealthReport.jsonBody` renders for the same components rather than
against a literal frozen here, because the body belongs to `Chain` and the
sibling change in REQ-runtime-032 appends a budget section to it; what this
suite pins is that the runtime spells nothing itself. A socket bound with
nothing reached reads `status` `starting` with the unreached components in
`waiting`.
*Fails against:* a listener that answers 200 as soon as it is bound, which is
the original incident and the reason this requirement exists; and a second
spelling of the body, which would drift from the type that already gets this
right.

**REQ-runtime-016, one component per part that is on.**
`HealthListenerTests.swift`: a configuration with the chain gate switched off
produces no `chain` component and reads `ok` once the store is reached, with
the chain in the startup report's off list and absent from the body. A
configuration with everything on holds at `starting` until both are reached.
*Fails against:* an off part reported as an unreached component, which holds
the instance at `starting` forever and makes a community with a token and no
collections look broken (ADOPT-10.a).
*The case nobody would find on their own:* an empty component list reads as
`ok` (`Sources/Chain/ChainHealth.swift:164`), so a runtime that forgets to
declare components reports perfect health forever and no other assertion
notices. The test asserts the component list is non-empty for every
configuration the fixtures can produce, and that the one legitimate empty case
is reachable only with every part off.

**REQ-runtime-017, answering costs no chain request.**
`HealthListenerTests.swift`: a governor with the day's budget exhausted still
answers, and the governor's count is unchanged by the request. Any provider
proof comes from the cached probe (`Sources/Chain/ProviderProofProbe.swift:26`).
*Fails against:* a listener that probes the node per request, which spends the
budget on whoever is monitoring and stops answering at the moment somebody is
actually looking (SEE-1.b).
*This is the endpoint half of SEE-1.b*, and the sibling change's own testing
document asks for it by name: that change proves an answer can be assembled for
nothing, this one proves the endpoint serves it for nothing, and without both
the criterion is proved by neither (REQ-runtime-032).

**REQ-runtime-018, the port is required, the address is loopback, the bound
port is what is reported.** `HealthListenerTests.swift`: port zero binds and
the report prints the port the kernel gave; the bound address is the loopback
one when `HEALTH_ADDRESS` is unset; an unset `HEALTH_PORT` refuses with 78; a
port already bound refuses with 69 naming the variable and the number.
*Fails against:* a report printing the configured port, which makes port zero
useless to a container and to this very test; and a default of every
interface, which publishes the waiting list and any provider proof to whoever
can reach the machine.
*The case somebody would forget:* a runner whose loopback is IPv6 only. The
test asserts the family it actually got rather than assuming IPv4, or the
Linux job fails for a reason that has nothing to do with the change.

### The startup report

**REQ-runtime-019, a report at every start, unsuppressible.**
`StartupReportTests.swift` compares the whole rendered report for a known
configuration against an expected text. Not a spot check of three lines: the
report is the operator-facing artefact of this change, and a snapshot is the
only way a change to it appears in a diff a reviewer reads. A second case
renders the report for a boot that then refuses, and asserts it is still
written. A third asserts no settings dictionary suppresses it.
*Fails against:* a report emitted through a logger, where a level or a
destination can remove it, which would quietly take BUILD-3.b with it.

**REQ-runtime-020, no secret's value, ever.**
`StartupReportSecretTests.swift` sets a unique sentinel as the value of every
catalogue entry marked secret, renders the report, and fails if any sentinel
appears anywhere in it. Written over the catalogue rather than over today's one
secret, `CHAIN_API_TOKEN`, so a secret added later is swept without anybody
remembering to extend the test. A second case puts sentinels in the node URL's
userinfo, path and query and asserts none of them survives into the report,
which is scheme, host and port only.
*Fails against:* a masked prefix, a length or a hash, each of which is enough
to confirm a guess and none of which the operator needed; and a report that
prints a URL whole, which is how a credential that nobody labelled a secret
gets published.
*The rule to state in one sentence for whoever writes the renderer:* the report
must be safe to paste into a public issue. That is the property the sentinel
sweep measures, and it holds for the next field too, which a list of fields to
redact does not.

**REQ-runtime-021, what it made of the settings, not that they loaded.**
`StartupReportTests.swift`: every rung with its name and its threshold in whole
tokens **and** in the token's smallest unit; every collection; every pool; the
admin allowlist in full; the network the node points at. A ladder with a gap at
rung 4 reports three rungs.
*Fails against:* a report built by walking the operator's variables rather than
the loaded values, which by construction cannot show a dropped rung; and one
that prints only the typed threshold, which cannot catch the decimals being
wrong, the failure that demotes an entire server at once
(`Sources/Gating/TokenProfile.swift:41`).
*The case somebody would forget:* a token with zero decimals. Both figures read
the same and nothing may assume six.

### Spending

**REQ-runtime-022, the capability is a parameter, never a reading.**
`SpendCapabilityTests.swift` sets every catalogue variable to a truthy value,
then to a falsy one, and asserts the capability is exactly what the caller
passed, both times. A second case passes the same environment names an operator
migrating from another bot would still have set, such as a wallet mnemonic and
an enable flag, and asserts the same.
*Fails against:* a capability fed by an environment variable, however carefully
named.

**REQ-runtime-023, the banner is the first line of every start.**
`SpendCapabilityTests.swift` and `StartupReportTests.swift`: the banner precedes
the configuration gate, appears on a start that then refuses, and says this
build has no way to move anything. `RuntimeCompositionTests.swift` asserts no
type in the package conforms to `ReservePayer`, which is what makes the banner
a fact about the graph rather than a default.
*Fails against:* a banner printed after the configuration, which the person
with a broken configuration never sees, and who is the person running it most
often; and a banner omitted when there is nothing to say, where BUILD-3.b asks
for it every time rather than learned from a transaction.

**REQ-runtime-024, no variable whose effect is to stop money moving.**
`SettingsCatalogueTests.swift` asserts the catalogue contains no entry named
`TEST_MODE`, `DRY_RUN` or `SAFE_MODE`, and `SettingsSourceTests.swift` asserts
none of those strings appears in `Sources/Runtime` or `Sources/BotMain` at all.
*Fails against:* the next contributor adding `DRY_RUN` in good faith, which is
the whole of BUILD-3.a. The bot this was ported from carries a note in its own
documentation saying its test mode is not a money switch, and that note is
load-bearing only until somebody new does not read it.

### What the program does

**REQ-runtime-025, four verbs and a default.**
`CommandLineTests.swift`: no arguments is `run`; `check`, `rehearse` and `help`
each reach their own path; an unrecognised argument exits 64 and prints the
four. Asserted on the value the executable maps to an exit rather than on a
process, so it stays a unit test.

**REQ-runtime-026, `check` prints the boot's report and touches nothing.**
`CommandLineTests.swift`: the text `check` prints and the text `run` prints for
the same settings are identical, compared directly. The journal after `check`
has no bind, no store open and no probe. With nothing set, `check` prints the
whole catalogue with every entry marked unset, plus the first refusal, and
exits 78, while `run` on the same settings names one variable.
*Fails against:* two formatters, which drift, and then the thing an operator
checks before a deploy is not the thing that runs; and a `check` that opens the
store in order to report on it.
*The asymmetry is deliberate and should be named in the test:* a boot tells you
the next thing to fix, because fixing it may change what comes next; a
catalogue tells you everything, because you asked for it.
*What `check` must also say:* which gates it did not run. A clean `check` that
looks like proof the node is reachable is worse than no command
(`plan.md` records the same gap).

**REQ-runtime-027, `rehearse` runs the operator's own rules.**
`RehearsalTests.swift`: the decisions printed are produced by `RoleRules` over
invented members, accounts and holdings, against the ladder in the settings the
test supplied. No socket, no store, no network. A case asserts that nothing in
the invented data is configuration: change the fixture's ladder and the
rehearsal output changes with it.
*Fails against:* a rehearsal with a demonstration ladder baked in, which would
show a contributor somebody else's tiers and break ADOPT-6.a in the one command
written to be run before anything is configured properly.

### Lifecycle

**REQ-runtime-028, shutdown releases what it holds.**
`LifecycleTests.swift` drives the shutdown function directly: the listener
stops, the store closes, the lease is released, the exit is zero, and a second
signal exits immediately. Driven directly rather than by raising a real signal,
because installing a signal handler in a test process affects every other test
in the run; that a real `SIGTERM` arrives at this function is a manual check.
*Fails against:* a shutdown that exits before the lease is given back, which
makes the next restart fail on a store nothing is using.
*The case somebody would forget:* a health request in flight during shutdown.
It is answered or the connection is closed, and neither hangs the exit.

**REQ-runtime-029, distinct exit codes.**
`CommandLineTests.swift` and `BootSequenceTests.swift`: the whole mapping, one
case per outcome, 0, 64, 69, 70 and 78, against the conventional `sysexits`
meanings.
*Fails against:* one non-zero code for everything, which is what the ported bot
does and which makes a wrong token and a full disk the same signal to whatever
is watching. 69 is the one an operator can put in a supervisor's do-not-restart
list, and that is the difference between a duplicate instance dying once and a
restart loop.

### The obligations that come with it

**REQ-runtime-030, every criterion above is exercised offline.** Asserted by
the whole target, and by `RuntimeFixtures.swift` being the only place a
dependency is constructed: `SQLiteStore.inMemory()` or a temporary directory,
a stub `AccountDataSource`, a spy gateway, and a loopback bind on port zero.
`SettingsSourceTests.swift` asserts no test in the target names a real host.
*Fails against:* a suite that passes only on a machine with the variables
exported or a node reachable, which is BUILD-2.b: a first contribution must not
begin with somebody being trusted with a secret.

**REQ-runtime-032, the boundary with the follow-ups change.** Not a test of
this target's own behaviour but of what it does not contain:
`RuntimeCompositionTests.swift` asserts no health status, waiting list or JSON
body is spelled anywhere under `Sources/Runtime`, so a drift into Chain's
vocabulary shows up here rather than as two spellings in production.
*Fails against:* a runtime that hand-builds its own body because the shape it
wanted was one key away.

**REQ-runtime-031, the gate and the disclosure.**
`specsync check --strict` covers the spec and the registered source
directories. The `docs/WHAT-IT-TALKS-TO.md` change is review, not test, and
`docs.md` lists exactly what it has to say. One assertion is worth adding
anyway: `RuntimeCompositionTests.swift` checks that `.specsync/config.toml`
names both new source directories, so the gate cannot be satisfied by leaving a
directory out of it.

## Cases somebody would forget

Collected in one place because several of them belong to no single
requirement.

| Scenario | Expected behaviour |
|----------|--------------------|
| A required variable set to the empty string | Refused as missing, because blank counts as unset everywhere else in the package |
| A value carrying the trailing newline a file gives it | Accepted, and reported trimmed, in both layers |
| A threshold written `100_000` | Accepted, because digit separators are allowed wherever this package reads a number |
| An optional variable nobody set | Counts as read, so the catalogue check bites on a clean machine too |
| `HEALTH_PORT` of zero | Bound to an ephemeral port, and the **bound** port is what the report prints |
| `HEALTH_PORT` already in use | 69, naming the variable and the number, with nothing left bound and nothing having identified |
| A health request during the store open | Answered, with `starting`. A listener accepted on the boot's own task is bound, silent, and indistinguishable from a hung machine |
| `HEAD /health` | Status and headers, no body, since a container check may use it |
| A request with no headers, or truncated | Closed without a crash, after a bounded number of bytes |
| Two health requests at once | Both answered; the report is a value, not a shared buffer |
| A loopback that is IPv6 only | Bound, and the test asserts the family it got |
| A store path on a network volume | Refused with 69 naming the filesystem, before anything binds |
| A store file that does not exist | Created, migrated, and reported as created |
| A store count from yesterday | Not restored into today's budget |
| A node that answers 500 | Boot continues, chain component unreached, health `starting` |
| A node that answers 401 | Refused with 78, because no amount of waiting fixes a wrong token |
| No tiers, no collections and no pools | Boots, and the report says so in those words (ADOPT-6.b) |
| A ladder whose rungs grant no roles | Boots, and each rung is shown granting nothing rather than omitted |
| A token with zero decimals | Whole and smallest figures agree, and nothing assumes six |
| An unbroken numbered list of 33 entries | Refused naming the 33rd variable, not silently truncated |
| `swift run` with no arguments | `run`, because that is what a container's default command does |
| `swift run` with an unknown verb | 64, usage, no boot attempted |
| A second signal during shutdown | Immediate exit |

## Rules no test in this change can hold

Said plainly, because a plan claiming full coverage of a boot sequence is not
believable.

- **The `ListenerBound` rule.** A compile failure is not a test case. The type
  is what stops it being written; `BindBeforeIdentifyTests` is what can fail.
- **The real chat handshake.** There is no client, so the ordering is exercised
  against a spy. When the adapter lands, the first test in its own suite is
  that its connect is the thing taking a `ListenerBound`, and that is a
  requirement on that change.
- **Two processes.** The suite runs in one. A second bind of the same port and
  a lease refusal are both reachable in-process; the genuine duplicate-instance
  case stays something an operator can reproduce and a test cannot.
- **A real signal.** See REQ-runtime-028.
- **The deploy gate.** Whether an orchestrator holds on 503 and promotes on 200
  is a property of a deployment file this repository does not have yet. It is
  the assumption the decision not to refuse on an unreachable node rests on, so
  it should be stated wherever that file is eventually written.
- **`check` and the durable volume.** `DurableVolume` is internal to
  `StoreSQLite`, so `check` can only confirm `STORE_PATH` is set, absolute and
  writable. A network filesystem is refused at `run` and not at `check`, which
  is the one place the dry run is weaker than the real thing.

## Manual checks

- [ ] `swift run bot` in a clean shell: the banner, one variable named, exit
      78, and a pointer to `check`.
- [ ] `swift run bot check` in the same shell: the whole catalogue, nothing
      bound, nothing reached, exit 78.
- [ ] `swift run bot rehearse` with a half-written configuration: your own
      ladder, decided over invented members.
- [ ] `swift run bot` with a valid configuration: the report, then the health
      endpoint going from 503 `starting` to 200.
- [ ] The same with the node URL pointed at a host that does not answer: the
      process stays up, the body names the chain, and the report says the gate
      did not pass (SEE-10).
- [ ] `SIGTERM` it and confirm the port is immediately bindable and the store
      lease released.
- [ ] Start a second copy against the same store on a different port: the
      second exits 69, the first never notices (RUN-7.a).
- [ ] Run it with an egress rule permitting only the node's host. This is the
      check `docs/WHAT-IT-TALKS-TO.md` calls the real one and that has never
      been possible before, because there was nothing to run.
- [ ] Paste the startup report into a draft issue and read it as a stranger.
      Anything in it you would not want public is a finding.

## What this plan deliberately does not cover

No payout, because there is no payer; no table, because nothing can play; no
sweep and no schedule, because the gate list has a place for them and it is
empty. The reserve is not composed at all, and that is the right absence: a
configured reserve that cannot pay is a setting that looks like it took, which
RUN-6 is against. When a payer arrives, the tests that matter are the ones in
`specs/reserve/testing.md` plus one here asserting the banner changed.
