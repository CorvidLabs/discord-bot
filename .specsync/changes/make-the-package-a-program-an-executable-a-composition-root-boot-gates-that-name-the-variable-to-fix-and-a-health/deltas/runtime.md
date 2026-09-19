---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
module: runtime
---

# Semantic delta: runtime

## Added

### REQUIREMENT REQ-runtime-001

The runtime SHALL be one library target holding the composition root, the boot
sequence, the settings catalogue, the startup report, the health state and the
health listener, and the program SHALL be a separate executable target holding
only argument handling, the one process environment snapshot, the construction
of the live seams, signal handling and the exit. The library SHALL depend on
the gating, chain and store contract modules and on nothing else: not on the
games or reserve modules, which no gate in the boot sequence reaches, and not
on the concrete durable store, because the composition root takes the store as
a protocol. The executable SHALL depend on the runtime library and on the
concrete durable store and on nothing else.

Acceptance Criteria
- `RuntimeCompositionTests.swift` proves each new target's dependency set
  against the manifest and fails on an added edge (ADOPT-4, BUILD-4).

### REQUIREMENT REQ-runtime-002

The runtime SHALL declare the chat seam as its own protocols over Foundation
types, naming a role and a member by `String`, and SHALL add no chat client
package dependency to the manifest. A chat adapter SHALL be a separate target
depending on the runtime, so that the package manager's own refusal of a
dependency cycle is what keeps the runtime, and the store behind it, unable to
see a chat client.

Acceptance Criteria
- `RuntimeCompositionTests.swift` proves no chat client package is reachable
  from the runtime or from any target it depends on (TRUST-1.b, BUILD-4).

### REQUIREMENT REQ-runtime-003

The runtime SHALL NOT read the process environment. The executable SHALL read
it exactly once, at the top, and SHALL turn that snapshot into a `Settings`
value; every runtime entry point SHALL take `Settings` as a parameter with no
default. The runtime SHALL NOT call the chain module's own environment loader,
which is the other door onto the machine's settings. `Settings` SHALL answer
the `(String) -> String?` lookup every existing loader already takes,
SHALL record every key it was asked for, and SHALL be constructible from a
dictionary by a test that touches no machine.

Acceptance Criteria
- `SettingsSourceTests.swift` walks the source directories beside its own
  `#filePath` and fails on a process environment read, or on a call to the
  chain module's environment loader, anywhere outside the executable
  (BUILD-2.a).
- `SettingsTests.swift` builds a `Settings` from a dictionary literal and
  proves both the lookup and the recorded read keys (BUILD-2).

### REQUIREMENT REQ-runtime-004

The catalogue SHALL describe every variable this build reads exactly once,
each entry carrying the variable name taken from the module constant that owns
it rather than retyped, a purpose sentence, whether it is required, and
whether its value is a secret. A numbered family SHALL be one entry describing
the family rather than one entry per index. Boot SHALL fail with the internal
error code when a loader asked `Settings` for a key the catalogue does not
describe, so that a variable added to a module without being described cannot
ship.

Acceptance Criteria
- `SettingsCatalogueTests.swift` proves every entry's name comes from the
  constant that owns it and that a numbered family is one entry (TRUST-1).
- `SettingsCatalogueTests.swift` proves a read of an undescribed key fails the
  boot with the internal error code (ADOPT-9, TRUST-1).

### REQUIREMENT REQ-runtime-005

Every gate that refuses SHALL name what to change: the variable, the purpose
sentence its loader carries for it, and the one command that lists the rest.
Started with nothing configured, the program SHALL exit non-zero with the
configuration code and SHALL print the first variable to set, rather than
starting and failing later at the first sweep. A refusal SHALL NOT be reduced
to a message naming only the stage that failed.

Acceptance Criteria
- `BootSequenceTests.swift` proves an empty environment refuses with the
  configuration code and names the first required variable together with its
  purpose sentence (ADOPT-2, RUN-9.a).
- `CommandLineTests.swift` proves the refusal also prints the command that
  lists the remaining variables (RUN-9.b, BUILD-1).

### REQUIREMENT REQ-runtime-006

A variable that is set and carries a prefix this build reserves for a surface
it does not contain SHALL stop the boot, naming the variable and saying that
the part is not in this build, rather than starting, answering healthy and
never appearing in the server. The reserved prefixes SHALL be a list stated in
the code rather than left to whoever implements a gate, so that one
environment file does not produce three different boots. A variable that is
set, carries a prefix this build owns, and was read by nothing SHALL be
reported in the startup report, together with the catalogue entry it is within
one edit of when there is one, and SHALL NOT refuse the boot.

Acceptance Criteria
- `SettingsAuditTests.swift` proves a reserved prefix set in the environment
  refuses the boot and names both the variable and the part that is absent
  (RUN-9.a, SEE-1.a, BUILD-4).
- `SettingsAuditTests.swift` proves an owned but unread variable is reported
  with the nearest catalogue entry and starts anyway (ADOPT-9.a, ADOPT-2).

### REQUIREMENT REQ-runtime-007

The boot sequence SHALL run its gates in one order that no configuration can
change: the spending banner, the configuration gate, the store gate, the
request budget restore, the listener bind, the chain gate, the chat gate, then
the loops. Each gate SHALL either pass, or stop the process with the exit code
its failure class carries and a message naming what to change.

Acceptance Criteria
- `BootSequenceTests.swift` proves the recorded gate order over a fully
  stubbed composition, and proves that no setting reorders it (RUN-9.a,
  SEE-11).

### REQUIREMENT REQ-runtime-008

The store gate SHALL open the durable store before any socket is bound, so
that the store's exclusive lease is what discovers a second instance. The
store path SHALL be required, and a relative path SHALL be refused, because a
supervisor restarting the process from another working directory would
otherwise hand the same command a different and empty database. A store
already held by another process SHALL stop this one with the unavailable code
and a message saying that the copy already running keeps serving.

Acceptance Criteria
- `StoreGateTests.swift` proves a relative path is refused by name, and proves
  a held store stops the second process with the unavailable code (RUN-7.a,
  ADOPT-2).
- `BootSequenceTests.swift` proves the store opens before the listener binds
  (SEE-8).

### REQUIREMENT REQ-runtime-009

The day's request count SHALL be restored from the store into the shared
request governor before the first chain request of the process, and one
governor SHALL be shared by everything that reads the chain or signs, so that
a restart does not refund a budget the operator has already spent.

Acceptance Criteria
- `BootSequenceTests.swift` proves a restored count is visible to the governor
  before the first request (RUN-8, RUN-8.b).
- `BootSequenceTests.swift` proves every chain caller in the composition holds
  the same governor instance (RUN-10.a, SEE-9).

### REQUIREMENT REQ-runtime-010

The chain gate SHALL verify the configured asset's precision against the node
when chain reads are enabled, and SHALL refuse the boot only on an answer that
contradicts the configuration: an asset the node has never heard of, a
precision that disagrees, or a provider refusal that rejects the credentials,
each naming the variable to correct. A network failure, or any other provider
refusal, SHALL leave the chain component unreached and SHALL NOT stop the
boot. An unreached chain component SHALL be retried through the same request
governor, backing off from five seconds to a ceiling of fifteen minutes, so
that a node down overnight cannot spend the day's budget on retries, and a
node that comes back SHALL move the health answer from starting to ready
without a restart.

Acceptance Criteria
- `ChainGateTests.swift` proves each contradicting answer refuses the boot and
  names a variable, over a stub account data source (ADOPT-12.a, ADOPT-2).
- `ChainGateTests.swift` proves a network failure leaves the component
  unreached rather than stopping the boot, and that the retry backs off to the
  ceiling (SEE-10.a).
- `ChainGateTests.swift` proves a node that comes back turns the health answer
  ready with no restart (RUN-3).

### REQUIREMENT REQ-runtime-011

Nothing SHALL be able to identify to a chat service before the listening
socket has bound, and this SHALL be enforced by the types rather than by the
order of two statements: a successful bind SHALL return a value whose
initialiser is internal to the runtime, and the chat seam's connect call
SHALL require that value, so that identifying first does not compile. Binding
first is how a second copy of the program learns that a first copy is already
serving, so the bind SHALL NOT be made to wait on a connection.

Acceptance Criteria
- `BindBeforeIdentifyTests.swift` binds on port zero and proves the recorded
  order on a spy gateway, with no real chat service (RUN-7, RUN-7.a, RUN-3).

### REQUIREMENT REQ-runtime-012

The listener SHALL answer one health route and nothing else. It SHALL report
ready only when every component the operator switched on has been reached, and
SHALL otherwise report that it is still starting together with the list of
what it is waiting for, so that a bound socket alone never reads as ready and
a version that came up half way is never promoted over the one that was
working. A part that is switched off SHALL contribute no component and no
wait, and SHALL instead be listed as off, with a reason, in the startup
report; an instance with nothing to wait for SHALL read as ready. The runtime
SHALL add no health vocabulary of its own: the status, the waiting list and
the rendered body belong to the chain module and SHALL be consumed rather than
spelled a second time. The listen port SHALL be required, the listen address
SHALL default to the loopback address, a port of zero SHALL be accepted so
that a test can bind without choosing a number, and the port actually obtained
SHALL be reported in the startup report.

Acceptance Criteria
- `HealthListenerTests.swift` proves a freshly bound listener with nothing
  reached answers that it is starting, with a waiting list, and answers ready
  once every enabled component is reached (SEE-1, SEE-1.a, RUN-3).
- `HealthListenerTests.swift` proves a part switched off contributes no
  component and no wait, and that the body is the chain module's own rendering
  rather than a second spelling (BUILD-1.a, ADOPT-10, ADOPT-10.a, SEE-10).
- `HealthListenerTests.swift` proves a bind on port zero reports the port
  obtained, and that the startup report prints it (HOST-6, ADOPT-2).

### REQUIREMENT REQ-runtime-013

Answering a health request SHALL cost no chain request, and SHALL still answer
when the day's budget is spent or the governor is paused. Any provider proof
in the answer SHALL be read from a cache refreshed on the runtime's own
schedule, never from inside the handler, so that no network call sits on the
request path. An instance that has been reached but whose chain reads are
throttled or paused SHALL answer ready, carrying the budget and the pause as
facts in the body, because it is serving; an instance that is both unreached
and throttled SHALL answer that it is starting, so that unreached outranks
throttled and a deploy gate cannot roll a working version back over a provider
quota.

Acceptance Criteria
- `HealthListenerTests.swift` proves the endpoint answers with the day's
  budget exhausted and the governor paused, and that the governor records no
  request for the answer (SEE-1.b, SEE-10.a).
- `HealthListenerTests.swift` proves the throttled instance reads as ready and
  the instance that is both unreached and throttled does not (RUN-3, RUN-11).

### REQUIREMENT REQ-runtime-014

A startup report SHALL be written at every start, including a start that then
refuses, and no setting SHALL suppress it. It SHALL state what the build made
of the settings and not only that they loaded: the spending banner, the
version, every rung of the ladder with its name and its threshold in whole
tokens and in smallest units, every collection, every pool, the size and
contents of the admin allowlist, the network the node address points at, which
parts are on and which are off with a reason for each, the address and port
bound, the store migrations applied and whether this start created the store
file, and the settings audit. A rung, a collection or a pool that a typo
dropped SHALL be visible there as a shorter list, before any sweep acts on it.

Acceptance Criteria
- `StartupReportTests.swift` proves the report is written on a start that
  refuses as well as on one that succeeds, and that no setting suppresses it
  (ADOPT-9, SEE-12).
- `StartupReportTests.swift` proves a dropped rung reads as a shorter ladder,
  and that the network and the admin allowlist are reported (ADOPT-9.a,
  ADOPT-12.b, CATALOG-7).
- `StartupReportTests.swift` proves each part that is off carries a reason,
  and that the bound port and the store migrations appear (ADOPT-10.a, SEE-8).

### REQUIREMENT REQ-runtime-015

The report SHALL never contain the value of an entry the catalogue marks as a
secret, and SHALL NOT print its length, its prefix or a hash of it. A secret
SHALL be reported as set or unset and nothing else. A fact derived from a
secret SHALL appear only where the catalogue entry names that derived fact and
the fact is public by construction, such as the account a signing key belongs
to. A value that is a URL SHALL be reported as scheme, host and port only,
because a provider address can carry a credential in its path and the report
is meant to be safe to paste into an issue.

Acceptance Criteria
- `StartupReportSecretTests.swift` sets a unique sentinel for every secret
  entry in the catalogue and proves that no sentinel, and no length, prefix or
  hash of one, appears anywhere in the rendered report (CATALOG-6.a, TRUST-1).
- `StartupReportSecretTests.swift` proves a URL entry renders as scheme, host
  and port only (ADOPT-9.a, TRUST-1.b).

### REQUIREMENT REQ-runtime-016

Whether a build can spend SHALL be a parameter of the composition and never a
reading of the settings, and no code path SHALL exist from `Settings` to the
spending capability. The spending banner SHALL be the first line of every
start, before the configuration is read, and SHALL say either that this build
has no way to move anything, naming that no payer is compiled in, or that it
can sign, naming the payer and the public account it signs for. While the
package contains no payer implementation, every build SHALL print the first
form, and that SHALL be a consequence of the graph rather than of a default.

Acceptance Criteria
- `SpendCapabilityTests.swift` sets every catalogue variable to a truthy and
  then a falsy value and proves the capability is exactly what the caller
  passed (BUILD-3, BUILD-3.a, HOST-7).
- `StartupReportTests.swift` proves the banner is the first line of a start
  that then refuses at the configuration gate (BUILD-3.b, HOST-7.a,
  SPEND-6.c).

### REQUIREMENT REQ-runtime-017

The catalogue SHALL contain no variable whose effect is to stop money moving,
and the runtime SHALL introduce no test mode, dry run or safe mode variable. A
variable that only changes how much is printed, or where it is printed,
SHALL be described in the report under a heading saying in words that it stops
nothing moving.

Acceptance Criteria
- `SettingsCatalogueTests.swift` proves no catalogue entry claims to stop a
  send, and that the printing variables sit under the heading that says so
  (BUILD-3.a).

### REQUIREMENT REQ-runtime-018

The program SHALL take `run` as its default with no arguments, and SHALL also
take `check`, `rehearse` and `help`; an unrecognised argument SHALL exit with
the usage code and print the four. `check` SHALL run the configuration gate
and print the same startup report a boot would, and with nothing set it
SHALL print the whole catalogue with each entry marked set or unset, together
with the first refusal, and exit with the configuration code. `rehearse`
SHALL load the operator's own configuration and run the role rules over
members, accounts and holdings it invents, printing the decision for each; it
SHALL invent members and holdings only, never configuration, so that a
contributor watches their own ladder rather than somebody else's. Neither
`check` nor `rehearse` SHALL open a socket, a store file or a network
connection.

Acceptance Criteria
- `CommandLineTests.swift` proves the default, the three named commands, and
  the usage code with all four printed for anything else (ADOPT-4, BUILD-1).
- `CommandLineTests.swift` proves `check` with nothing set prints the whole
  catalogue marked set or unset and exits with the configuration code (RUN-9,
  RUN-9.b, ADOPT-9).
- `RehearsalTests.swift` proves a rehearsal decides over invented members
  against the operator's own ladder, and that neither subcommand opens a
  socket, a store file or a connection (BUILD-1.b, BUILD-1, ADOPT-6.a).

### REQUIREMENT REQ-runtime-019

On an interrupt or a termination signal the process SHALL stop the listener,
close the store, which releases its lease, and exit zero. A second signal
SHALL exit immediately.

Acceptance Criteria
- `LifecycleTests.swift` proves the ordered shutdown releases the lease and
  exits zero, and that a second signal exits at once (RUN-7.a, SEE-8).

### REQUIREMENT REQ-runtime-020

Exit codes SHALL be distinct and documented: 0 for a clean stop, 64 for a
usage error, 69 for something already here or unusable, being a held store, an
address in use or a volume that cannot promise a write, 70 for an internal
error, and 78 for a configuration that is wrong. One code for every failure
SHALL NOT be used, because a supervisor cannot tell a wrong token from a full
disk from a single number.

Acceptance Criteria
- `CommandLineTests.swift` proves the usage code and the configuration code
  (RUN-3, SEE-11).
- `BootSequenceTests.swift` proves each gate failure exits with its own
  documented code (RUN-7, SEE-11).

### REQUIREMENT REQ-runtime-021

Every guarantee in this module SHALL be exercised by a test that needs no chat
service, no chain, no wallet and no database anybody installed. The store in
those tests SHALL be an in-memory store, or a file under the test's own
temporary directory; the chain SHALL be a stub account data source; the chat
SHALL be a spy; and the only socket SHALL be a loopback bind on port zero, so
that nothing in the suite can reach a real chain, a real server or a real
account, whatever is configured on the machine running it.

Acceptance Criteria
- The whole of `Tests/RuntimeTests/` runs with no network, no signing key and
  no database the contributor installed (BUILD-2, BUILD-2.a, BUILD-2.b).

### REQUIREMENT REQ-runtime-022

The runtime SHALL open no listening socket other than the health listener, and
the project's statement of what the software reaches SHALL name that listener,
the address and port it listens on by default, what its answer contains, and
that the answer can carry provider proof headers, so that the list a person
reads before installing is still true after this change.

Acceptance Criteria
- `HealthListenerTests.swift` proves one route and one socket (TRUST-1).
- The project's statement of what the software reaches is reviewed in the same
  pull request and names the listener, its default address and port, and the
  contents of its answer (TRUST-1.b).
