---
spec: runtime.spec.md
---

## Key Decisions

- **The lease before the bind**, where the bot this was ported from binds
  first. That bot's reasoning is right and the conclusion moves. Binding is
  how a process discovers another copy, and this package has something that
  asks the exact question instead of a proxy for it: `SQLiteStore.open` takes
  an exclusive lease on a sibling of the store file before it opens the
  handle. The real question is whether another instance is using *this data*.
  A port clash approximates that, and approximates it wrongly in a case this
  product has to support: one machine hosting several communities has several
  instances, each with its own store and its own port, and a second instance
  pointed at the same store on a different port passes a port check and fails
  a lease. So the lease goes first, the bind second, and both go long before
  anything could identify. The counter-argument, recorded rather than
  dismissed: the ported bot's ordering is battle tested and this one is not.
  It is checked by running two processes by hand, which is in the spec's
  behavioural examples and is what a test in one process cannot do.

- **Bind before identify, enforced by a type.** A comment saying "these two
  statements must stay in this order" is how the rule gets lost. A successful
  bind returns `ListenerBound`, whose initialiser is internal, and the chat
  seam's connect call requires one, so identifying first does not compile from
  another target. The same trick the store already uses for claim-before-pay.
  Its limit is stated in the spec rather than left for somebody to discover:
  it proves a bound listener exists, not that the bind happened first in time.

- **An unreachable node does not stop the boot.** The other way, which the
  ported bot takes for its verification portal, turns every provider blip
  during a restart into an outage. The cost of this choice is real and is
  accepted: a misconfigured node URL that resolves to nothing leaves a process
  running and permanently `starting` rather than exiting. The health answer is
  what makes that safe, and it is only safe if the deploy gate reads it.

- **A 401, and a 403 that is not a quota refusal, do stop it.** Those are the
  operator's credential and no amount of waiting fixes them.
  `ChainError.isProviderQuotaRefusal` is asked first, because a provider's own
  quota refusal also arrives as a 403 and sending somebody to edit a perfectly
  good token is worse than waiting.

- **A chat variable set on a build with no chat surface refuses.** A loud
  warning would also be defensible and would let somebody stage an environment
  file ahead of a release. Refusing wins because the failure it prevents is
  silent: a process that starts, answers healthy and never appears in the
  server is the three hour outage the SEE family opens with. The cost is that
  a rollback from a later chat-capable build is a boot refusal until the
  operator edits their environment, which is accepted here rather than
  discovered.

  **What the rule asks was sharpened rather than removed** when a surface
  landed. It no longer asks whether a prefix is on a list; it asks whether
  anything linked into this build reads the variable, and a linked part
  answers by describing its own through ``ChatGateway/settingsEntries``. The
  prefix stays on the reserved list, and a build without the part refuses
  exactly as it did with nothing having been edited. The alternative
  considered and rejected was naming the chat variables in this module's own
  catalogue, which would have put the words a chat library uses into a target
  that is not allowed to know them.

- **The reserved prefixes are written down in the code**, as `DISCORD_` and
  `VERIFY_`. There is no chat module yet whose constants could be enumerated,
  so leaving it to whoever implemented the check would have given three
  different boots from one environment file: one reserving the whole prefix,
  one reserving a single variable, one adding the portal keys.

- **`HEALTH_PORT` and `STORE_PATH` are required with no defaults.** Two more
  lines in a first run, against the two defaults that bite hardest later: a
  shared port that collides on the second community, and a relative path that
  quietly becomes a second empty store after a supervisor restarts the process
  from another directory.

- **A hand written listener instead of an async networking package.** More
  code here, no new pin, and one fewer thing for a reader of the disclosure
  document to weigh. The precedent for the platform conditionals is already in
  the store's instance lease.

- **Spending is a parameter and never a reading.** There is no code path from
  the settings to it, and therefore no `TEST_MODE`. The bot this was ported
  from carries a note in its own documentation saying its test mode is not a
  money switch; a project that has to carry such a note has already failed to
  say so in software, and the note is load-bearing only until somebody new
  does not read it.

- **URLs are reported as scheme, host and port.** Slightly annoying when an
  operator wants to confirm the path they typed. Worth it, because the report
  is designed to be pasted into an issue and some providers put the credential
  in the path.

- **The report is written as rendered; only the refusal is filtered.** The
  report is rendered from the catalogue, so the renderer has no path to a
  secret's value and cannot print one. A refusal is different: the loaders
  quote the value they could not use. Filtering both was tried and was wrong:
  a secret that happens to be a short common word turns ordinary sentences
  into nonsense, which teaches the next reader that the output is unreliable.

- **`Runtime` is a target and not a product.** Somebody wanting to embed an
  instance in their own process has to run the binary instead. That is the
  right trade while the shape is changing weekly, and it is the reversible
  direction: promoting a target to a product breaks nobody, demoting one is a
  breaking change.

## Divergences from the change definition

Recorded rather than quietly absorbed, because each was a place the definition
and the tree disagreed and the tree won.

- **`ProcessInfo.processInfo.environment` is not the executable's alone.** The
  definition says the snapshot in `BotMain` is the only reference in
  `Sources/`. `Chain.ChainConfiguration.loadFromProcessEnvironment(token:)` is
  a merged public convenience with one of its own. Nothing calls it, the
  runtime contract forbids the root from starting to, and the source scan
  pins the whole set at two rather than asserting a one that is not true.

- **`SpendCapability` carries a `SpendingPayer` declared here, not
  `Reserve.ReservePayer`.** The definition names the latter, and the same
  definition says this target depends on `Gating`, `Chain` and `Store` and on
  nothing else. The dependency rule is the load-bearing one, so the protocol
  is declared here and an adapter holding a real payer conforms to it.

- **`ChainReader.verifyAssetDecimals()` takes no caller.** The definition
  anticipates a sibling change making every public read on `ChainReader` name
  its caller. That change has not landed, so the call is as the tree has it,
  and whichever change lands second carries the one-line edit.

## What is missing

- ~~**No chat surface**~~. The seam is filled: the adapter conforms, the
  executable builds one when a token is configured, and the boot hands it the
  value the bind produced. What is still absent is a sweep that would call
  ``ChatGateway/roleIds(ofMember:)`` and
  ``ChatGateway/setRoles(ofMember:to:)``, so those two exist and nothing in
  this module calls them yet.
- **No wallet verification**, and deliberately no boot gate for one.
- **No payer.** Nothing in the package can move value.
- **No sweep loop and no scheduler.** Gate eight is where they go and it is
  empty, so the health component list is `store`, `chain` when the boot was
  told to confirm the asset, and `chat` when a surface is linked.
- **No invite link and no permission list.** Both need a chat client to mean
  anything.
- **No revision stamped from the commit.** The version is a constant, and the
  report says so in words.
