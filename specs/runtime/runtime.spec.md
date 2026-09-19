---
module: runtime
version: 1
status: active
files:
  - Sources/Runtime/BootFailure.swift
  - Sources/Runtime/BootGate.swift
  - Sources/Runtime/BootSequence.swift
  - Sources/Runtime/ChainGate.swift
  - Sources/Runtime/ChatGateway.swift
  - Sources/Runtime/ExitCode.swift
  - Sources/Runtime/HealthListener.swift
  - Sources/Runtime/HealthState.swift
  - Sources/Runtime/ListenerBound.swift
  - Sources/Runtime/Rehearsal.swift
  - Sources/Runtime/RunningInstance.swift
  - Sources/Runtime/Runtime.swift
  - Sources/Runtime/RuntimeCommand.swift
  - Sources/Runtime/RuntimeOutput.swift
  - Sources/Runtime/RuntimeSeams.swift
  - Sources/Runtime/RuntimeSettings.swift
  - Sources/Runtime/SecretRedaction.swift
  - Sources/Runtime/Settings.swift
  - Sources/Runtime/SettingsAudit.swift
  - Sources/Runtime/SettingsCatalogue.swift
  - Sources/Runtime/SpendCapability.swift
  - Sources/Runtime/StartupReport.swift
  - Sources/Runtime/StoreOpening.swift
  - Sources/Runtime/VariableNames.swift
  - Sources/BotMain/BotMain.swift
  - Sources/BotMain/ChatSurface.swift
  - Sources/BotMain/LiveSeams.swift

db_tables: []
depends_on: ["gating", "chain", "store"]
---

# Runtime

## Purpose

Turn six libraries into one binary an operator can start, that refuses in a way
they can act on, and that a supervisor can ask whether it is really working.

Two targets, one contract, because the split between them is the contract.

- `Runtime` decides what happens and in what order. It is handed its seams, so
  the whole boot can be driven from a test with a store in memory, a stub node,
  a spy chat gateway and a loopback bind on port zero.
- `BotMain` touches the machine and decides nothing: the arguments, the one
  snapshot of the process environment, the construction of the live seams, the
  signals and the exit. It is the only place both the composition root and a
  concrete store are visible, which is what makes "what can this build reach"
  one function rather than a search.

Two rules run through all of it.

**A refusal names the variable.** Every loader in the package already works
this way. The composition root's job is to keep that property on the way out
through a process exit rather than losing it in a wrapped error (ADOPT-2,
RUN-9.a).

**A bound socket is not health.** The listener binds before anything could
identify to a chat service, because binding is how a second copy finds out a
first one is here. That makes the socket useless as a readiness signal, which
is why the endpoint answers `starting` until the parts that must be up are up
(SEE-1.a).

### What is deliberately absent

- **No chat client, in this target.** The seam is a protocol over Foundation
  types with a role and a member both `String`, and the one conformance lives
  in the adapter, which depends on this target. SwiftPM refuses a cycle, so
  this target can never depend back and `Store` stays two edges further away
  still. Nothing here imports a chat library and nothing here names a
  snowflake, a server or a channel.
- **No wallet verification, and no boot gate for one.** When one arrives it is
  a component that can be unreached without the bot being down, because losing
  the part that proves a wallet should lose verification and nothing else
  (SEE-7). That is a deliberate divergence from the bot this was ported from,
  which refuses to start when its portal is unreachable.
- **No payer, so nothing can move value**, and no variable exists that would
  change that.
- **No sweep loop and no scheduler.** The gate list has a place for them and it
  is empty.
- **No version stamped from the commit.** The version is a constant edited when
  a release is cut, and the report says in words that it is what the source
  claimed rather than what was built.

## Public API

Every exported symbol of the `Runtime` target, in source order, one row per
name. Where several types share a name the row is merged and says which sense
belongs to which. `BotMain` exports nothing: every declaration in it is
`internal`, which is what an executable target should be.

| Export | Description |
|--------|-------------|
| `BootFailure` | Why the process is stopping, carrying the three things the person who has to fix it needs at once: the variable, a sentence and the code a supervisor reads. |
| `variable` | The variable to change, when one is to blame; nil for a refusal no single variable causes. |
| `summary` | What is wrong, in one sentence. |
| `remedy` | What to do about it, or nil when the summary already says. |
| `code` | What the process exits with: the ``ExitCode`` on a `BootFailure`. |
| `listingCommand` | The command a refusal names, because a refusal reports only the first thing wrong and the listing is what saves the operator a second round trip. |
| `init` | Memberwise. On `Settings` it takes the variables as a dictionary and there is no other; on `SettingsReader`, `SettingsEntry`, `ReportSection`, `StartupReport`, `HealthState`, `HealthAnswer`, `HealthListener`, `OpenedStore`, `RuntimeSeams`, `BootSequence`, `Runtime`, `RecordingOutput` and `StandardStreams` it is the plain one. `ListenerBound` has none that is public: only a completed bind makes one. |
| `lines` | The refusal as the lines that go to standard error, the lines under one report section, and the whole report ready for standard output. |
| `configuration` | A configuration refusal from one of the loaders, keeping the variable it named; also the ``ExitCode`` for a configuration that is wrong, and the ``BootGate`` that reads and checks everything while touching nothing. |
| `BootGate` | The gates, in the one order they run in, not reorderable by configuration. |
| `banner` | The gate that says whether this build can move anything, and the sentence it prints. |
| `store` | The gate that takes the lease, opens the store and migrates it; the store seam on ``RuntimeSeams``; the opened store on ``OpenedStore``; the health component named for it; and the report section for it. |
| `budget` | The gate that puts today's request count back into the one governor. |
| `bind` | The gate that binds the health endpoint, and the listener method that does it and returns ``ListenerBound``. |
| `chain` | The gate that asks the node whether the asset is the one the operator described; the chain seam on ``RuntimeSeams``; the loaded chain configuration; and the health component named for the node. |
| `chat` | The gate that registers and identifies to the chat service; the chat seam on ``RuntimeSeams``, nil when this build was given no surface; the ``SettingsGroup`` the surface's own variables are listed under; and the health component the session's own opening event reaches. |
| `loops` | The gate where a sweep and a scheduler will go. It is empty. |
| `BootOutcome` | What a start came to. |
| `running` | It walked the gates and is up: the outcome case, and the ``RuntimeResult`` case that carries the instance the caller waits on. |
| `refused` | It stopped, carrying the refusal, the report it still wrote and the gates that ran. |
| `report` | The report a start wrote, whichever way it went, and the assembled ``Chain/ChainHealthReport`` the endpoint answers from. |
| `partsTitle` | The heading the Parts section is written under, named once because the gate that learns what the node said writes it and the finish has to know it is there. |
| `gatesPassed` | The gates that ran, in the order they ran. Recorded rather than declared, so a test asserts what happened. |
| `failure` | The refusal, or nil when it is up. |
| `BootSequence` | The eight gates, in order, with nothing between them that a setting could reorder. |
| `run` | Walks the gates; also the verb that is the default with no arguments. |
| `ChainGateOutcome` | What the node said about the asset when the boot asked. |
| `confirmed` | The node confirmed the asset and its precision. |
| `notProbed` | The operator turned the check off, so nothing was asked. |
| `unreached` | The node did not answer, or answered something that says nothing about the configuration. The instance stays up and `starting`. |
| `contradiction` | The node contradicted the configuration. The boot stops. |
| `ChainGate` | Asking the node, once, whether the asset is the one the operator described. |
| `firstRetryDelay` | How long the first retry waits: five seconds. |
| `maximumRetryDelay` | The longest a retry ever waits: fifteen minutes, so a node down overnight cannot spend the day's budget on retries. |
| `nextRetryDelay` | The wait before the retry after one that waited this long. Pure, so the schedule is pinned by a test rather than by waiting for one. |
| `probe` | Asks the node once and classifies the answer. |
| `classify` | Which of the four answers an error is. Asks whether a 403 is the provider's own quota refusal before treating it as a wrong credential. |
| `ChatGateway` | The chat service, as this module is willing to know about it: a protocol over Foundation types with a role and a member both `String`. One target conforms to it, and it is the only one that may: the adapter that knows what a snowflake is. |
| `settingsEntries` | Every variable the linked surface reads, described as this module's own catalogue describes its own. The surface describes itself because a module that links no chat library may not name a chat variable, and the descriptions are what put those variables in the report, count them as read, and stop them being refused as belonging to a part that does not exist. |
| `connect` | Registers what this build offers, then identifies to the service. Takes the proof that a listener is already bound, which is what makes the wrong order a compile error, and the closure the surface reports its session through, because returning from it is not a websocket. |
| `ChatSessionState` | Whether the chat session is open, as the gateway itself sees it. Two cases and no detail: the reason a session ended belongs in the surface's own log, where the words for it exist. |
| `closed` | The session ended, and nothing is being delivered. |
| `roleIds` | Every role a member holds now, including ones this build knows nothing about. |
| `setRoles` | Sets a member's roles to exactly this set. |
| `disconnect` | Stops talking to the service. |
| `ExitCode` | How the process ends, and why. Distinct codes, because one number cannot tell a supervisor a wrong token from a full disk. |
| `ok` | Stopped cleanly, on a signal. Zero. |
| `usage` | An argument nobody recognises. Sixty four. |
| `unavailable` | Something is already here, or cannot be used: a held store, an address in use, a volume that cannot promise a write. Sixty nine, and the one to put in a supervisor's do-not-restart list. |
| `internalError` | This program is wrong rather than its configuration. Seventy. |
| `label` | One word for the code, for a report line. |
| `HealthListenerError` | Why the health endpoint could not be opened. |
| `addressUnusable` | The address is not one this machine can bind. |
| `addressInUse` | Something is already listening there. |
| `refused` (error) | The operating system refused, and this is which step and which errno. |
| `errorDescription` | The refusal written out for a person, on `HealthListenerError` and on `StoreGateError`, each naming the variable to change. |
| `exitCode` | What the process exits with: on a listener error, and on a ``RuntimeResult`` that finished. |
| `HealthListener` | The one socket this process opens on the operator's own machine. A hand written listener over the platform's sockets, answering one path. |
| `maximumRequestBytes` | How many bytes of a request are read before it is answered or dropped. |
| `readTimeoutSeconds` | Seconds a client has to send its request line. Spent on a thread of the connection's own, never on the accept loop, so one client that sends nothing costs one connection rather than the endpoint. |
| `maximumConsecutiveAcceptFailures` | How many `accept` failures in a row mean the listener is dead rather than busy. |
| `onDeath` | What to do if the accept loop stops on its own. Set after the bind, and a reason that arrived before the handler did is kept and handed over. |
| `HealthListenerDeath` | Why the accept loop stopped without being asked to. A listener that will never accept another connection is a dead instance, not a degraded one: nothing watching can tell it from a healthy one and this process goes on holding the store's lease. |
| `pollFailed` | Waiting on the socket failed for a reason that is not an interruption. |
| `listeningSocketBroken` | The listening socket reported an error, a hangup, or that it is not a socket. |
| `acceptRefused` | `accept` refused with something that cannot come right on its own. |
| `acceptKeptFailing` | `accept` failed this many times in a row. |
| `sentence` | What happened, in one sentence for whoever reads the log. |
| `stop` | Stops answering and gives the port back. It waits for the accept loop to finish, because the loop is the only thing that closes the listening socket: closing it from outside would let the operating system hand the same descriptor number to the next socket anybody opens while a stale loop is still accepting on it. |
| `HealthState` | What this instance has reached, kept where the listener can read it without touching anything. |
| `markReached` | Records that a component has been reached. A name that is not a declared component is ignored rather than added. |
| `markUnreached` | Records that a component is no longer reached. |
| `proofRefreshWanted` | One element per answer given, for whoever refreshes the provider proof. Sent after the answer is assembled, never before, so no network call is on the request path, and it is what keeps the probe on demand rather than on a timer. |
| `answer` | The whole answer a request gets: 200 when every enabled component is reached, 503 otherwise, the same body either way. |
| `HealthAnswer` | One answer to one health request. |
| `statusCode` | 200 or 503. Not reached outranks throttled; a spent budget is a fact in the body and never a failing check. |
| `body` | ``Chain/ChainHealthReport/jsonBody``, reused rather than respelled. |
| `headers` | Provider proof headers to copy onto the answer, when there is proof. |
| `HealthComponent` | The names of the components this build can declare, as constants, so the report, the gates and the health answer cannot disagree. |
| `ListenerBound` | Proof that a listener is bound, and where. Its initialiser is internal, so connecting before binding does not compile. |
| `address` | The address bound: on ``ListenerBound``, and the configured one on ``RuntimeSettings``. |
| `port` | The port actually obtained, which is not the configured one when the configured one was zero. |
| `description` | The address and port as one line for the report. |
| `Rehearsal` | The role rules run over members this invents, against the operator's own configuration. Members and holdings only, never configuration. |
| `members` | The invented members, in the order they are printed. |
| `RunningInstance` | A process that walked the gates and is up, holding the pieces that have to be let go of in the right order. |
| `listener` | What the bind produced, and the report section naming the address and port. |
| `currentHealth` | What the health endpoint would answer right now. Reads state already in memory and makes no request. |
| `requestBudget` | What this process has spent of today's request budget, read from the one governor every caller shares. |
| `waitUntilStopped` | Returns when the instance has been stopped. |
| `shutDown` | Stops the listener, closes the store, which releases the lease, and releases whoever was waiting. Safe to call more than once. |
| `RuntimeResult` | What running a verb came to. |
| `finished` | Nothing is left running, and this is what the process exits with. |
| `Runtime` | The composition root. Handed its seams, so nothing in it reads the process environment, opens a file it was not given a path to, or knows a chat library exists. |
| `execute` | Runs one verb, or whatever the arguments ask for, refusing an argument nobody recognises. |
| `RuntimeCommand` | What the binary was asked to do: four verbs, parsed by hand. |
| `check` | Load the settings and print the report a start would, touching nothing. |
| `rehearse` | Run the role rules over members and holdings this invents, using the operator's own ladder. |
| `help` | Print the four. |
| `usage` (text) | What each verb does, one line each, with the exit codes. |
| `parse` | The verb in the arguments, or the refusal to print. |
| `needsChatSurface` | Whether this verb needs a chat surface built before it runs. Two of the four: `help` has to work on a machine where nothing is configured, and `rehearse` speaks to nobody. |
| `RuntimeOutput` | Where the report and the refusals go. A seam, because the report is something a test has to read, and because where a report should go when the process is not a terminal is not settled. |
| `write` | Writes lines an operator is meant to read. |
| `writeError` | Writes lines about something being wrong. |
| `StandardStreams` | The process's own output and error. The report goes to standard output and refusals to standard error, so a supervisor capturing only one still sees the refusal. |
| `RecordingOutput` | Output kept in memory, so a test can read what a start printed. Its `out` and `errors` hold every line written to each, in order. |
| `outText` | Everything written to output, as one string. |
| `errorText` | Everything written to error, as one string. |
| `allText` | Everything written to either, as one string. |
| `ChainSourceProviding` | Where the chain reader and the provider probe come from. A seam, so the whole boot can be driven with a stub and no network. |
| `dataSource` | The data source to read accounts and assets through. |
| `proofProbe` | The probe whose response headers are copied onto a health answer, or nil for none. It deliberately does not go through the request governor. |
| `RuntimeSeams` | Everything live that the boot sequence is handed rather than builds. |
| `output` | Where the report and the refusals go. |
| `spending` | Whether this build can move anything. A parameter, never a reading. |
| `now` | The clock, injected so a test pins the day the budget belongs to. |
| `RuntimeEnvironment` | The names of the variables this program reads for itself, held in one place so a refusal names the exact variable. |
| `storePath` | `STORE_PATH`: where this instance keeps what it remembers. Required, and absolute. |
| `healthPort` | `HEALTH_PORT`: the port the health endpoint listens on. Required, with no default. |
| `healthAddress` | `HEALTH_ADDRESS`: the address the health endpoint binds. Loopback unless set. |
| `defaultHealthAddress` | The address the endpoint binds when nothing says otherwise: the loopback address. |
| `RuntimeSettings` | What this program needs that no other module reads. Three values, two of them required with no default. |
| `load` | Reads them, or refuses naming the variable; also the whole configuration, in the order the existing code requires. |
| `LoadedConfiguration` | Everything the boot needs, loaded and checked, before anything is touched. |
| `gating` | What holding something earns somebody. |
| `runtime` | What this program needs for itself. |
| `keysRead` | Every variable any loader asked for: on the loaded configuration, and on the reader that recorded them. |
| `SecretRedaction` | The one place a value is turned into something safe to print. |
| `placeholder` | What stands in for a value that may not be printed. |
| `host` | A URL as scheme, host and port, and nothing else. |
| `applied` | Every occurrence of a value this build must not print, taken out of a line on its way to standard error. |
| `Settings` | Everything the operator wrote down, as one value read once. There is no initialiser that reaches the machine. |
| `value` | One variable's value, unchanged, or nil when it is not set. |
| `names` | Every variable name that was set. |
| `dictionary` | The variables as a dictionary, for the one loader that takes one. |
| `read` | Runs a body against a reader that remembers every key it was asked for, and hands back both the result and that list. |
| `SettingsReader` | A view onto the settings that remembers what it was asked for. Handed to the loaders as the lookup they already take. |
| `settings` | What the reader reads. |
| `lookup` | One variable, recorded as read. |
| `note` | Records keys read by something that could not be handed this reader, taken from the catalogue rather than retyped. |
| `UnreadSetting` | A variable that is set, belongs to this build, and nothing read. |
| `name` | The variable as the operator wrote it, and the entry's own name where one is being described. |
| `nearest` | The catalogue entry it is within one edit of. A suggestion, never a correction. |
| `SettingsAudit` | What the catalogue makes of the variables that are actually set: read, owned and unread, or reserved for a part this build has not got. |
| `unread` | Set, owned by this build, and read by nothing. Reported, never a refusal. |
| `reserved` | Set, and belonging to a part this build does not have. Each one is a refusal. |
| `undescribed` | Read by a loader and described by no catalogue entry. A fault in the program rather than in the operator's file. |
| `refusal` | The refusal this audit produces, or nil. The undescribed keys come first because an operator can do nothing about them. |
| `of` | Runs the audit. |
| `SettingsRequirement` | Whether a variable has to be set for the build to start. |
| `required` | No default exists and boot refuses without it. |
| `optional` | Absent means the documented behaviour, never somebody else's value. |
| `SettingsSecrecy` | Whether a variable's value may be printed. |
| `plain` | The value may appear in the startup report. |
| `secret` | The value may never appear anywhere: not its length, not a prefix, not a hash. |
| `url` | The value is a URL, so only its scheme, host and port may be printed. |
| `SettingsGroup` | Which part of the build reads a variable, for grouping the report. |
| `token` | The group for the token the ladder is measured in, and the token itself on the loaded gating configuration. |
| `ladder` | The group for the rungs of the holder ladder. |
| `collections` | The group for the collections gated on. |
| `pools` | The group for the liquidity pools counted. |
| `access` | The group for roles and administrators. |
| `SettingsEntry` | One variable this build reads, described exactly once. |
| `pattern` | The variable, or the family pattern with `#` where a number goes. |
| `purpose` | What it is for, in one sentence an operator can act on. |
| `requirement` | Whether boot refuses without it. |
| `secrecy` | Whether its value may be printed. |
| `group` | Which part of the build reads it. |
| `isFamily` | Whether this entry describes more than one variable. |
| `matches` | Whether a name is one of the variables this entry describes. |
| `SettingsCatalogue` | Every variable this build reads, described once. The report, the audit and the secret rule are all rendered from it. |
| `ownedPrefixes` | Prefixes this build owns. A variable inside one that nothing read is reported as a probable typo. |
| `reservedPrefixes` | Prefixes reserved for a part this build does not have. A variable inside one refuses the boot. |
| `reservedPart` | What a reserved prefix is reserved for, for the refusal's sentence. |
| `entries` | Every variable, in the order the report prints them. |
| `entry` | The entry describing a name, or nil when nothing does. |
| `chainNames` | Every non-family variable in the chain group, for the one loader that takes a dictionary and cannot record its own reads. |
| `reservedPrefix` | Which of the reserved prefixes a name carries, if any. |
| `isOwned` | Whether a name carries a prefix this build owns. |
| `SpendingPayer` | Something that can move value, and the account it moves it from. Nothing in this package conforms to it, which is the point. |
| `payerName` | What this payer is, for the banner. The name of the mechanism, never a secret. |
| `publicAccount` | The public account it signs for. Public by construction, and the one fact derived from a key the report prints. |
| `SpendCapability` | Whether this build can move anything, as a fact about the composition and never a reading of the settings. |
| `cannotSpend` | No payer is compiled into this build, so nothing can be moved. |
| `canSpend` | A payer is compiled in, and this is it. |
| `canSign` | Whether anything in this build could move value. |
| `ReportSection` | One heading of the startup report and the lines under it. |
| `title` | The heading. |
| `StartupReport` | What the build made of the settings, written at every start and suppressible by nothing. Its `sections` are in the order they are printed. |
| `append` | Adds a section to the end. |
| `appendIfAny` | Adds a section unless it has no lines. |
| `rendered` | The whole report as one string. |
| `RuntimeVersion` | What this build says its version is: a constant edited when a release is cut. |
| `current` | The version this source declares. |
| `StartupReportWriter` | Turns what is known into the sections the report prints. Every section is a function from values. |
| `opening` | The banner and the version, printed before the settings are even read. |
| `catalogue` | Every catalogue entry, grouped, marked set or unset. Marked, never printed. |
| `understanding` | What the build made of the settings: every rung in whole tokens and smallest units, every collection, every pool, the admin allowlist in full, the node's host, and the variable each numbered list stopped at. |
| `parts` | Which parts are on, which are off, and why each off one is off. |
| `audit` | Variables nothing read, and the entry each is nearly. |
| `OpenedStore` | A store that was opened, and what opening it did. |
| `migrationsApplied` | Migrations this start applied, named. |
| `createdFile` | Whether there was no store at this path and this start made one. |
| `StoreGateError` | Why a store could not be opened, in the two shapes the boot has to tell apart. |
| `heldByAnotherProcess` | Another process is holding this store. The other copy keeps serving, and this one stops. |
| `unusable` | The store is there and cannot be used. |
| `StoreOpening` | Where the durable store comes from. A seam, so the store gate's refusals are reported by this module while this module still links no database. |
| `open` | Opens the store, taking whatever lock keeps a second process out. |

## Invariants

1. **The bind precedes any identify.** A successful bind returns a
   ``ListenerBound`` whose initialiser is internal to this module, and
   ``ChatGateway/connect(afterBinding:reporting:)`` requires one, so
   identifying first does not compile from another target.

   **The limit of that, stated.** It proves a bound listener exists when
   connect is called. It does **not** prove the bind happened first in time,
   because nothing stops a caller holding a value from an earlier bind. What
   closes that gap is that this module is the only thing that can make one and
   makes exactly one, in ``BootSequence``, at the gate before the chat gate,
   and `BindBeforeIdentifyTests` asserts the recorded order.

2. **A bound socket is not readiness.** The endpoint answers 503 and
   `starting` from the moment it is up until every enabled component has been
   reached. Binding is how a second copy discovers a first one, so the socket
   cannot also be the readiness signal.

3. **A secret is never printed.** The report is rendered from the catalogue
   and the renderer has no path to the value of an entry marked secret: not
   the value, not a length, not a prefix, not a hash. A URL is printed as
   scheme, host and port only. A refusal, which does quote values, is filtered
   through ``SecretRedaction`` on its way to standard error.

4. **No environment variable can make this build able to spend.**
   ``SpendCapability`` is a parameter of the composition. There is no code
   path from ``Settings`` to it, no variable is consulted, and there is no
   `TEST_MODE`, `DRY_RUN` or `SAFE_MODE` in the catalogue.

5. **The environment is read in one place.** `BotMain` takes one snapshot.
   Nothing in `Runtime` mentions `ProcessInfo` or calls
   ``Chain/ChainConfiguration/loadFromProcessEnvironment(token:)``, and
   `SettingsSourceTests` reads the source beside its own `#filePath` to keep
   it that way.

6. **Only the accept loop closes the listening socket.** It is woken through
   a pipe rather than by having its descriptor closed underneath it, so a
   stopped listener can never accept a connection on a descriptor number the
   operating system has already given to something else.

7. **The store's lease is taken before the socket is bound.** The lease asks
   whether another instance is using *this data*; a port clash only
   approximates that, and approximates it wrongly when one machine hosts
   several communities with a store and a port each.

8. **The gate order is fixed and unreorderable by configuration.** It is
   ``BootGate/allCases``, and ``RunningInstance/gatesPassed`` records what
   actually ran so a test asserts the order rather than a constant claiming
   it.

9. **A variable this build reads is described exactly once**, or the boot
   stops with the internal code. A variable inside a reserved prefix stops the
   boot with the configuration code. A variable inside an owned prefix that
   nothing read is reported and never stops the boot.

10. **Answering a health request costs no chain request.** Everything in the
   answer is read from ``HealthState``, which the runtime wrote. The provider
   proof is refreshed off the request path and never inside the handler.

    **And never on a timer.** One probe when the loops gate starts, and after
    that one per answer given, which the probe's own cache reduces to at most
    one per `CHAIN_HEALTH_PROBE_CACHE_SECONDS`. An instance nobody ever checks
    costs the provider one request for its whole life. The alternative, a loop
    ticking every cache lifetime, is one request every thirty seconds for ever
    whether or not anybody asks, and the probe deliberately does not go through
    the request governor, so `CHAIN_DAILY_REQUEST_BUDGET` would neither count
    nor stop those.

11. **`check` and `rehearse` open no socket, no store file and no network
    connection.**

12. **A part that is off contributes no component.** The components are built
    from the configuration and from what was linked, not from a constant:
    `CHAIN_VERIFY_ASSET_DECIMALS=false` means the node is not a component of
    this instance at all, rather than a component marked reached that nothing
    has reached, and a build with no chat surface declares no chat component
    rather than waiting for ever on one. An answer that says this instance has
    spoken to the node when nothing ever has is the three hour incident the
    endpoint exists for. The off part is named in the report's Parts section
    instead.

13. **The report is written as it is produced, not buffered to the end.** Each
    gate's section goes to standard output as the gate finishes, so a start
    killed by a supervisor's start-up timeout while the chain gate waits on a
    node that is black-holed has still printed the banner, the catalogue, what
    it made of the settings, the store line and the address it bound. The
    sections a gate cannot fill in yet are written by the finish, once, on
    both the way out of a refusal and the way up.

14. **A listener that dies stops the instance.** The accept loop carries a
    reason out on every way out but the wake pipe, ``RunningInstance`` writes
    it to standard error, releases the store's lease and stops with 70. It is
    never rebound in place: the endpoint would answer for an instance nothing
    is watching, and a replacement pointed at the same `STORE_PATH` would be
    refused as a duplicate while this process held the lease.

15. **A variable set to nothing is unset.** The audit trims and treats blank as
    unset, which is what every loader in the package already does, so a
    compose file passing an empty variable through is not a refusal from one
    layer that the next layer would have ignored.

16. **The chat gate returning is not health.** A linked chat surface
    contributes ``HealthComponent/chat``, and the gate never marks it
    reached: identifying is asking for a websocket, and the call returns as
    soon as the attempt is under way. Only the session's own opening event
    raises it, through the closure
    ``ChatGateway/connect(afterBinding:reporting:)`` takes, and the session
    ending lowers it again. A process whose websocket never opens, or opens
    and dies, is not a degraded bot: it is a bot that is not in the server,
    and nothing watching could tell the two apart, which is what the endpoint
    is for (`SEE-1`, `SEE-1.a`).

17. **The verb is known before anything is built.** `BotMain` parses the
    arguments first and builds a chat surface only for the two verbs that
    would use one. `help` has to work on a machine where nothing is
    configured, `check` exists to say what is wrong with the settings, and a
    refusal that pre-empted it disabled the one diagnostic verb with exactly
    the class of fault it is for, then named it as the thing to run. A `check`
    whose chat settings are refused prints the whole listing first and the
    refusal last, with the surface's own variables still in the listing.

## Behavioral Examples

**A clean machine.** `bot` with nothing set prints the banner, lists the whole
catalogue marked set or unset, and exits 78 on standard error with:

```
refused: TOKEN_ASSET_ID
  TOKEN_ASSET_ID is not set. It is the on-chain id of the asset your holder
  ladder is measured in. There is no default: ...
```

The asset id is first because `GatingConfiguration.load` reads the token before
anything else: the ladder's thresholds cannot be converted without its decimals
and the pools cannot be given an asset id without its asset id.

**A configured start, with the node down.** The eight gates run, the socket
binds, and `GET /health` answers:

```
HTTP/1.1 503 Service Unavailable
{"status":"starting","waiting":["chain"]}
```

The instance stays up. A node that does not answer has said nothing about the
configuration, and the retry backs off from five seconds to a fifteen minute
ceiling through the same governor everything else uses, so a node that comes
back moves the answer to 200 with no restart.

**A second instance, on the same store, on a different port.** It is refused
at the store gate with 69 and `Another process is already holding the store at
...  That copy is still serving your server, so this one stopped rather than
taking its place.` It never reaches the bind, and it never identifies to
anything.

**A dropped rung.** With `TIER_1_*` and `TIER_2_*` set and `TIER_4_*` written
by mistake, the report says `Ladder, 2 rungs` and `the ladder stopped at
TIER_3_NAME, which is not set`. The fourth rung is dropped rather than
renumbered, and it is visible before a sweep acts on it.

**A chat token on a build with no chat surface.** `DISCORD_BOT_TOKEN` set,
and ``RuntimeSeams/chat`` nil, refuses at the configuration gate with 78,
naming the variable and saying this build has no chat surface. It does not
start and answer healthy while never appearing in the server.

**A chat surface that never opens its websocket.** Every gate passes, the
report says `on   chat surface`, and `GET /health` answers:

```
HTTP/1.1 503 Service Unavailable
{"status":"starting","waiting":["chat"]}
```

It stays that way until the session's own opening event arrives, and goes back
to it if the session ends. A gateway outage, a token revoked at runtime, or a
privileged intent the application was never granted all look like this, and in
each of them the registration over HTTP has already succeeded, so the boot has
nothing to refuse on. A deploy gate polling this endpoint holds rather than
going green on a bot that is not in the server.

**`bot help` on a machine with half a chat surface.** `DISCORD_GUILD_ID` set
and no token: the usage text, exit 0. The surface is built only for `run` and
`check`, so a verb that reads none of those variables is not refused for one.
`bot check` with the same settings prints the banner, the whole catalogue
including the chat variables, what it made of the rest, and then the refusal
naming `DISCORD_BOT_TOKEN`, exiting 78.

**A chat token on a build that has one.** The same variable, with a surface
linked, is ordinary. The surface described it through
``ChatGateway/settingsEntries``, so the listing prints it under **The chat
service**, the audit counts it read, and a value never appears anywhere
because the surface marked it secret. A **typo** under that prefix,
`DISCORD_BOT_TOKE`, is then a probable typo reported beside its correction
rather than a refusal: the prefix belongs to a part this build has, and
refusing an unknown name there would break both directions of an upgrade.

## Error Cases

| Case | Code | What it means |
|------|------|---------------|
| A required variable is unset or unusable | 78 | ``BootFailure`` naming it and the sentence its loader carries |
| `STORE_PATH` is relative | 78 | A supervisor restarting elsewhere would open a different, empty store |
| `HEALTH_PORT` is not a port | 78 | Zero to 65535; zero lets the operating system choose |
| A variable in a reserved prefix is set and nothing linked describes it | 78 | This build has no chat surface or no verification. A prefix a linked part claims is no longer reserved, whole |
| The node says the asset does not exist | 78 | ``ChainGateOutcome/contradiction``, naming `TOKEN_ASSET_ID` |
| The node says the precision differs | 78 | Naming `TOKEN_DECIMALS`; every balance would be wrong by a factor of ten per place |
| The node answers 401, or 403 that is not a quota refusal | 78 | Naming `CHAIN_API_TOKEN`; waiting does not fix a credential |
| The node does not answer, or refuses on quota | none | ``ChainGateOutcome/unreached``. The instance is up and `starting` |
| The store is held by another process | 69 | ``StoreGateError/heldByAnotherProcess``; the other copy keeps serving |
| The store cannot be used | 69 | ``StoreGateError/unusable`` |
| The address is already in use | 69 | ``HealthListenerError/addressInUse`` |
| `HEALTH_ADDRESS` is not an address this machine can bind | 78 | ``HealthListenerError/addressUnusable`` |
| The day's request count is on record and unreadable | 70 | Starting would hand this process a second day's allowance |
| A loader read a key the catalogue does not describe | 70 | A fault in the program, not in the operator's file |
| The health endpoint's accept loop dies after the boot | 70 | ``HealthListenerDeath``, written to standard error; the lease is released so a replacement is not refused as a duplicate |
| An argument nobody recognises | 64 | The four verbs are printed |

## Dependencies

`Runtime` depends on `Gating`, `Chain` and `Store`, and on nothing else. Not
`Games` and not `Reserve`, because neither is reachable without a surface to
play on or a payer to pay with. Not `StoreSQLite`, because it takes
`any BotStore`.

`BotMain` depends on `Runtime` and `StoreSQLite`, and on nothing else.

This change adds **no** package dependency. The chat seam is declared here over
Foundation types, so the adapter that will know about snowflakes depends on
this target, SwiftPM refuses a cycle, and this target can never acquire it
back; `Store` is two edges further away still.

`Runtime` is a plain target and not a library product, deliberately. A product
is a promise about an API and the composition root is at its least stable
moment: it grows a parameter every time a surface lands. Promoting a target to
a product later breaks nobody; demoting one is a breaking change.

## Change Log

- **1**. First version. The composition root, the eight boot gates, the
  settings catalogue and its audit, the startup report and its secret rule, the
  health state and the one-route listener, the bind-before-identify type, the
  four verbs, and the executable. No chat client, no payer, no verification and
  no loops.
- **1**. The chat seam is filled. ``RuntimeSeams/chat`` is a real gateway in
  the assembled executable and nil in a build that links no adapter, and the
  chat gate hands it the value the bind produced. A linked surface describes
  its own variables through ``ChatGateway/settingsEntries``; the listing, the
  audit and the reserved-prefix rule all read the same list, so a chat
  variable is known rather than reserved **when something reads it** and is
  refused exactly as before when nothing does.
- **1.1**. The chat surface is a health component. It is declared when one is
  linked, the chat gate never marks it reached, and the surface reports its
  own session through a closure ``ChatGateway/connect(afterBinding:reporting:)``
  takes: the opening event raises it and the session ending lowers it. The
  gate's refusal path now leaves the session before it unwinds the port and
  the store, and `BotMain` parses its verb before it builds anything, so
  `help` and `rehearse` are no longer gated on the chat settings and `check`
  prints its listing before the refusal.
