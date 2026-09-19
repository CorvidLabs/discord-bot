---
spec: runtime.spec.md
---

## How this is tested

Everything offline. The store is `SQLiteStore.inMemory()` or a file the test
made under its own temporary directory, the chain is a stub `AccountDataSource`,
the chat is a spy, and the only socket is a loopback bind on port zero. Nothing
reaches a real chain, a real server or a real account.

| Suite | What it holds |
|-------|---------------|
| `SettingsTests` | Settings as a value built from a literal, and the recording of every key a loader asked for. |
| `SettingsCatalogueTests` | That every variable a full load reads is described, that families are one entry, that exactly one variable is a secret, and that no money switch exists. |
| `SettingsAuditTests` | Owned and unread is reported with a suggestion; reserved refuses by name; somebody else's variable is ignored; a variable set to nothing at all is unset, which is what every loader in the package already says. |
| `SettingsSourceTests` | The source read as text: no `ProcessInfo` in the root, no chat client in either target, nothing forced, and the socket option that would let a duplicate bind never asked for. |
| `BootSequenceTests` | The eight gates in the order that happened, an empty environment naming the first variable, each required variable removed on its own, and the day's count restored or refused. The restore is asserted against the governor rather than against the row it came from: the counter is only written back every so many requests, so a boot making one request leaves the row unchanged either way and an assertion on it cannot fail. Also that the report reaches standard output while a gate is still waiting on a node, that the provider proof is probed once and then only on demand, and that a listener that dies stops the instance with 70. |
| `StoreGateTests` | A relative path refused, a held store stopping this instance, an unusable store as its own refusal, and a real file opened, migrated and reported. |
| `ChainGateTests` | Which answers contradict and which do not, including a 403 on quota against a 403 on a credential, and the retry schedule. |
| `BindBeforeIdentifyTests` | Connect after the bind, holding what the bind produced; a second bind of the same port refused; a port in use stopping the boot. |
| `HealthListenerTests` | The body and the code in both states, one route over a real loopback socket, the endpoint answering with the budget spent, and the probe never called from the handler. Also that three clients which connect and send nothing do not delay one health check, that a client aborting before the answer leaves the endpoint answering, and that a loop which stops on its own hands the reason over. A body is pinned against what `ChainHealthReport` renders plus the one fact each test is about, never against a whole literal frozen in the test, because a sibling change appends a section to the same body. |
| `StartupReportTests` | The banner first, every rung in both units, a dropped rung as a shorter ladder, empty catalogues printed as empty, and a created store said loudly. |
| `StartupReportSecretTests` | A unique sentinel in every secret entry and one in a node URL's query, absent from the whole of what was printed. |
| `SpendCapabilityTests` | Every catalogue variable set truthy and then falsy, with the banner unchanged. |
| `CommandLineTests` | The four verbs, an unrecognised argument, and `check` touching nothing with a path that cannot exist and a node that would fail. |
| `RehearsalTests` | The operator's own rungs rehearsed, a different ladder rehearsing differently, and unread shown as unread. |
| `LifecycleTests` | The port given back, the lease released, and stopping twice not being an error. The first of those is only deterministic because stopping waits for the accept loop to close the socket; it caught a descriptor reuse race when it did not. |
| `RuntimeCompositionTests` | The manifest read as text: the dependency lists, one executable product, no new package, and both source directories registered with the contract gate. |

## What no test here covers

- **Two processes.** The lease and the bind are both about a second instance
  and the suite runs in one process. What is provable here is that a second
  bind of the same port is refused and that a held store is reported as a
  named refusal. The real duplicate-instance case is reproducible by hand and
  is in the spec's behavioural examples; a test cannot do it.
- **A node that answers.** Every chain answer here comes from a stub. A
  configuration that passes `check` can still fail at a start on the node, and
  the chain gate is what closes that, at the cost of one request.
- **The volume.** `DurableVolume` is internal to `StoreSQLite`, so `check` can
  only say that the path is absolute and its parent is writable. A store on a
  network filesystem is refused at a start and not at `check`.
- **The signal handlers.** They live in the executable and are the one thing
  the suite cannot drive. What is tested is what they call: `shutDown` and
  `waitUntilStopped`, and, by reading the source, that `SIGPIPE` is ignored
  before the process does anything that could write.

- **A listener that really dies.** Making `accept` fail fifty times in a row
  means exhausting the process's file descriptors, which would take the test
  runner with it. What is tested is the whole path either side of that: the
  loop hands a reason to whoever is listening, and an instance told one
  writes it, releases the lease and stops with 70.

- **SIGPIPE under the default disposition.** A test cannot assert that a
  process is not killed without being killed. The socket option that would
  turn the write into an error is set as early as it can be and is measurably
  not enough on its own: on Darwin it fails on a connection the peer has
  already reset, which is the one it is wanted for. So the endpoint test
  ignores the signal for itself, the way a host does, and asserts what is
  left: the write gives up on that connection and the endpoint carries on.
