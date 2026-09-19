---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: tasks
---

# Tasks

Worked through in the order of `plan.md`. Each item is meant to be answerable
with yes or no by looking at the tree, not by judgement. The reasoning behind
the ones that look arbitrary is in `plan.md`, cited by decision number; the
normative statements are in `requirements.md`, cited by requirement id.

## Before any code

- [ ] Read the sibling definition,
      `satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted`,
      and hold to the split in REQ-runtime-032: this change adds no health
      vocabulary of its own, and the chain gate names the instance's own work
      when that change makes a caller required on `ChainReader`.
- [ ] Write `specs/runtime/runtime.spec.md` with all seven sections
      `.specsync/config.toml` requires: Purpose, Public API, Invariants,
      Behavioral Examples, Error Cases, Dependencies, Change Log.
- [ ] List every file of both new source directories in that spec's `files:`
      frontmatter, the way `specs/store/store.spec.md` covers three
      directories in one spec (D15).
- [ ] State as invariants, not as prose: the bind precedes any identify; a
      bound socket is not readiness; a secret is never printed; no environment
      variable can make the build able to spend.
- [ ] State in the spec the limit of the `ListenerBound` trick: it proves a
      bound listener exists, not that the bind happened first in time (D8).
- [ ] Add `Sources/Runtime` and the executable's directory to `source_dirs` in
      `.specsync/config.toml`, extending the list rather than replacing it.
- [ ] Add only the companion files the policy selects for `specs/runtime/`, and
      no empty ones for ceremony.

## Manifest

- [ ] Add the `Runtime` target: dependencies `Gating`, `Chain` and `Store`,
      strict concurrency enabled like every other target.
- [ ] Add the `BotMain` executable target, strict concurrency enabled.
- [ ] Add exactly one executable product, `bot`, so bare `swift run` is
      unambiguous (D1, REQ-runtime-001).
- [ ] Do not add a library product for `Runtime` (D2), and add no new package
      dependency anywhere in this change (D14).
- [ ] Write the manifest comment for `Runtime` saying what it may never depend
      on and why: no chat SDK, no database, so `Store` keeps the guarantee the
      existing `Store` comment already claims.
- [ ] Add the `RuntimeTests` target, depending on `Runtime`, `Store` and
      `StoreSQLite`, because REQ-runtime-030 composes `SQLiteStore.inMemory()`
      and a temporary store directory.

## Settings, read once and described once

- [ ] Add `Settings`: built from a dictionary, answering both shapes the
      existing loaders want, recording every key it was asked for
      (REQ-runtime-004).
- [ ] Put the `ProcessInfo` snapshot in the executable target and nowhere else
      (D3, REQ-runtime-003).
- [ ] Add the catalogue: one entry per variable this build reads, each with the
      name taken from the module constant that owns it, a purpose, whether it
      is required and whether it is a secret (REQ-runtime-005).
- [ ] Describe numbered families as families, not as thirty-two entries each.
- [ ] Fail the boot with the internal error code when a loader asked for a key
      the catalogue does not describe (REQ-runtime-006).
- [ ] Report a variable that is set, carries a prefix this build owns and was
      read by nobody, with the catalogue entry it is one edit away from, and do
      not refuse the boot for it (REQ-runtime-007).
- [ ] Refuse the boot when a variable belonging to a part this build does not
      have is set, naming it and saying the part is not in this build
      (REQ-runtime-014).
- [ ] Add no boolean setting anywhere in this change. The only new variables
      are `STORE_PATH`, `HEALTH_PORT` and `HEALTH_ADDRESS` (D6, D9,
      REQ-runtime-024).

## The refusal path and the verbs

- [ ] Compose the loaders in the order the existing code requires: token first,
      then gating, then chain around the same token value, then the runtime's
      own settings.
- [ ] Carry a refusal as a value holding the variable, the sentence and the
      exit code, and render it as one line on stderr.
- [ ] Refuse a missing `STORE_PATH`, and refuse a relative one, saying why a
      relative path is refused (REQ-runtime-011).
- [ ] Refuse a missing or unusable `HEALTH_PORT` by name, default
      `HEALTH_ADDRESS` to loopback, and accept port zero (REQ-runtime-018).
- [ ] Parse the four verbs from `CommandLine.arguments` with no dependency: no
      argument runs, `check`, `rehearse`, `help`; anything else prints the four
      and exits with the usage code (REQ-runtime-025).
- [ ] Make `check` open no socket, no store file and no network connection, and
      with nothing set print the whole catalogue marked set or unset together
      with the first refusal (REQ-runtime-026).
- [ ] Make `rehearse` invent members and holdings only, never configuration, so
      what a contributor watches is their own ladder (REQ-runtime-027).
- [ ] Map every outcome to the codes in REQ-runtime-029: 0, 64, 69, 70, 78
      (D13).

## The startup report

- [ ] Print the spending banner first, before the configuration is read, in the
      words of BUILD-3.b and SPEND-6.c (REQ-runtime-023).
- [ ] Print the version the source declares, saying in words that it is what
      the source claimed rather than what was built (REQ-runtime-019).
- [ ] Print the report at every start, including one that then refuses, and let
      no setting suppress it (REQ-runtime-019).
- [ ] Print the token: asset id, symbol, display name, decimals.
- [ ] Print every rung with its name and its threshold in whole tokens and in
      smallest units (REQ-runtime-021).
- [ ] Print the variable each numbered list stopped at, for the ladder, the
      collections, the pools, the admin accounts and the token links, so a rung
      a typo dropped is visible before a sweep acts on it (ADOPT-9.a).
- [ ] Print an empty catalogue of collections or pools as empty rather than
      omitting the line (ADOPT-6.b).
- [ ] Print the admin allowlist by size and by contents, and print an empty one
      as nobody, which `AdminAllowlist` already treats as legitimate.
- [ ] Print every URL as scheme, host and port only (REQ-runtime-020).
- [ ] Print a secret as set or unset and nothing else: no length, no prefix, no
      hash.
- [ ] Print which parts are on and which are off, each off one with a reason
      (ADOPT-10.a, BUILD-1.a).
- [ ] Print the store path, the migrations applied, whether this start created
      the store file, and the address and port actually bound.
- [ ] Add no generic dump: no `Mirror`, no `Encodable` configuration, no
      `description` of a whole configuration value (D12).

## Readiness and the listener

- [ ] Add a readiness value holding one component per enabled part, rendering
      through `ChainHealthReport` rather than a second spelling of the same
      shape (REQ-runtime-015).
- [ ] Declare no component for a part that is off, and no component for the
      chat gateway, which does not exist in this build (REQ-runtime-016).
- [ ] Answer `GET /health` and nothing else: 200 when every enabled component
      is reached, 503 otherwise, both with the same body.
- [ ] Answer from state already in memory, making no request, so a check never
      spends the day's budget and still answers once it is gone
      (REQ-runtime-017).
- [ ] Wire `ProviderProofProbe` for the provider proof, and prove by test that
      **with proof headers configured and the cache stale**, answering a health
      request calls no probe: the refresh happens on the runtime's own
      schedule, off the request path (D10, REQ-runtime-017).
      Not "an unset `CHAIN_PROOF_HEADERS` makes no request": that passes
      already, because `proof(now:)` returns early when no header names are
      configured, so a handler that calls `proof(now:)` on every request keeps
      that test green and reaches the network the first time an operator
      configures headers and the cache expires. A test that cannot fail the
      thing it is named for is worse than no test, because it is counted.
- [ ] Bound the read of the request line, and close the connection after one
      answer (D14).
- [ ] Never set `SO_REUSEPORT`, with the comment saying why: it permits the
      second bind this bind exists to refuse.
- [ ] Refuse a port already in use with the unavailable code and a message
      naming `HEALTH_PORT` and the port.

## The boot sequence

- [ ] Run the eight gates in the fixed order and make them unreorderable by
      configuration (REQ-runtime-008).
- [ ] Return `ListenerBound` from a completed bind, initialiser internal to
      `Runtime`, and require one on the chat seam's connect call
      (REQ-runtime-010).
- [ ] Declare the chat seam over Foundation types, with a role and a member
      both `String`, and no conformance in the package (REQ-runtime-002).
- [ ] Take the store as a seam the sequence calls at its gate, so the refusal
      is reported by `Runtime` and `Runtime` still links no database.
- [ ] Open the store before any socket is bound, and stop a second instance
      with the unavailable code and a message saying the other copy keeps
      serving (REQ-runtime-011).
- [ ] Restore the day's request count into the shared governor before the first
      chain request, and refuse the boot when the stored count cannot be read
      (REQ-runtime-012, RUN-8.b).
- [ ] Share one governor between everything that reads, and later signs.
- [ ] Classify the chain gate's failures exactly as REQ-runtime-013 sets out,
      asking `ChainError.isProviderQuotaRefusal` before treating a 403 as a
      credentials refusal (D11).
- [ ] Back the chain gate's retry off from five seconds to a fifteen minute
      ceiling, reserving every retry from the governor.
- [ ] Say in the report, when `CHAIN_VERIFY_ASSET_DECIMALS` is off, that the
      node was not probed at start and why.
- [ ] Stop the listener, close the store, which releases the lease, and exit
      zero on `SIGINT` or `SIGTERM`, and exit immediately on a second signal
      (REQ-runtime-028).

## Tests, all offline

- [ ] Name every test for the criterion it protects, as the rest of the suite
      does.
- [ ] An empty environment refuses, names `TOKEN_ASSET_ID`, prints its purpose
      sentence and exits with the configuration code.
- [ ] Each required variable, removed one at a time from a complete fixture,
      produces a refusal naming that variable.
- [ ] A key read but not in the catalogue fails the boot with the internal
      error code.
- [ ] A variable set with a prefix this build owns and read by nobody appears
      in the report and does not refuse the boot.
- [ ] A unique sentinel in every secret catalogue entry, and one inside a node
      URL's query string, appears in neither the report nor any refusal.
- [ ] The banner says the build cannot spend for every catalogue variable set
      to a truthy value and again to a falsy one (REQ-runtime-022).
- [ ] A dropped rung reads as a shorter ladder: set two rungs, leave the third
      unset, assert the report names the variable the list stopped at.
- [ ] The body is `starting` and names what it is waiting for while a component
      is unreached, and `ok` with 200 once every enabled component is reached.
- [ ] A second bind of the same port is refused, using an ephemeral port read
      back from the first bind so the test needs no fixed number.
- [ ] The health endpoint answers with the governor's budget exhausted.
- [ ] A spy gateway records that connect was not called before the bind, and
      `ListenerBound` proves the other order does not compile.
- [ ] The boot refuses when the stored request count cannot be read, and does
      not refuse when there has never been one.
- [ ] A node that never answers leaves the instance up and `starting` with
      `chain` named; a node answering with disagreeing decimals refuses.
- [ ] `check` and `rehearse` open no file and make no request, proved with a
      store path in a directory that does not exist and a node URL that would
      fail.
- [ ] A source scan finds no `ProcessInfo` and no call to
      `ChainConfiguration.loadFromProcessEnvironment(token:)` under
      `Sources/Runtime` (REQ-runtime-003).
- [ ] `swift test` passes on macOS and on Linux with no network.

## Documentation and the gate

- [ ] Rewrite the README state section: there is an executable now, and the
      missing list loses its "no executable" line and keeps the rest.
- [ ] Document the four verbs, the four new variables and the exit codes in the
      README, so ADOPT-4 still holds: a clean machine to a running process from
      the README alone.
- [ ] Update `docs/WHAT-IT-TALKS-TO.md`: there is a startup now, so the
      paragraph saying the package has none is false; there is a second
      outbound call site, off unless `CHAIN_PROOF_HEADERS` is set; the process
      writes files, namely the store and its lease; and it opens a listening
      socket on the operator's own machine.
- [ ] Add the four new variables to that document's tables, marking none of
      them a secret.
- [ ] Add the new targets to the AGENTS.md table with the sentence saying
      `Runtime` may never link a chat SDK or a database.
- [ ] Add the change to `CHANGELOG.md` under `Unreleased`.
- [ ] Add a CI job running the built binary twice: with no configuration,
      expecting the configuration code and the variable named on stderr, and
      with a fixture configuration and `check`, expecting a clean exit and the
      report.
- [ ] Run `fledge lanes run verify`, then `specsync check --strict`, then
      `specsync change check` for this change.

## Gaps

- **`check` cannot test the durable volume.** `DurableVolume` is internal to
  `StoreSQLite` (`Sources/StoreSQLite/DurableVolume.swift`), so the dry run can
  only check that `STORE_PATH` is set, absolute and has a parent directory that
  exists and can be written. A store on a network filesystem is therefore
  refused at `run` and not at `check`, which is the one place the dry run is
  weaker than the real thing. Making the check public changes a merged module's
  contract, so it is a separate change if anybody wants it.
- **`check` cannot prove the node is reachable without spending a request.**
  Deliberate, and it means a configuration that passes `check` can still fail
  at `run` on the node. The chain gate is what closes that, at the cost of one
  request.
- **The version is what the source claimed.** A constant says what was written
  down, not what was built, so SEE-12 is only half answered. Stamping the real
  revision needs a build plugin, which is a new moving part in the manifest and
  is out of scope here; a variable carrying a revision was considered and cut,
  because it adds a fourth new variable for a fact no acceptance criterion asks
  for.
- **The spending banner is not in the health body.** It is the first line of
  every start and it is in the report, which is what BUILD-3.b asks, but a
  monitoring check cannot see it without changing `Chain`'s contract.
- **No test covers two processes.** The lease and the bind are both about a
  second instance and the suite runs in one process. What is provable here is
  that a second bind of the same port is refused and that a held store is
  reported as a named refusal; the real duplicate-instance case stays something
  an operator can reproduce and a test cannot.
- **Nothing in `hi/` says outright that the listener must be bound before
  anything identifies.** RUN-7.a is the nearest and it is about which copy keeps
  serving, not about the order of two steps. The behaviour is required by the
  acceptance criteria and was learned from a real reconnect storm; the want may
  deserve its own criterion, which is a `hi/` change and a product decision
  rather than something to slip into this one.

## Settled since the artifacts were first written

Recorded rather than deleted, because each was a disagreement between two of
these documents and somebody may want to reopen one.

- **Scope.** `affected_paths` in `state.json` now lists the documentation,
  spec, config and workflow paths the items above touch, rather than `Sources`,
  `Tests` and `Package.swift` alone. A release where the executable exists and
  the README still says there is none is worse than a larger diff.
- **The health body's off list.** The off parts are named in the startup report
  and not in the `/health` body, so no merged module's contract text changes
  (REQ-runtime-016).
- **What `BotMain` may depend on.** `Runtime` and `StoreSQLite`, so `Runtime`
  keeps taking `any BotStore` and links no database (REQ-runtime-001).

## Open questions

- **The proof probe's URL.** The probe needs somewhere to send its one request.
  Using the configured node URL with a health path appended assumes a path
  shape the node software happens to offer; the alternative is a fifth
  variable most operators would never touch.
- **Where the report goes.** Plain lines on stdout with stable prefixes so an
  operator can grep, and `research.md` notes nobody has decided whether the
  runtime should also hold it as a value a surface could read later. If anybody
  wants JSON for a log pipeline, say so now: retrofitting a machine-readable
  report means changing every line at once.
- **Which of the two parallel changes lands first.** REQ-runtime-032 names the
  split with the follow-ups change. Neither blocks the other, but the second
  one to land carries two one-line edits: naming the caller on the chain gate's
  read, and the body assertion once a budget section is appended.
