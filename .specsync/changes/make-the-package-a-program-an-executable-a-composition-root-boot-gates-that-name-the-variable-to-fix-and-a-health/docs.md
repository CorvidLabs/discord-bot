---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: docs
---

# Docs

This change makes the opening sentence of almost every document in the
repository false. `README.md` says "Not runnable yet". `AGENTS.md` says "There
is no gateway, no slash command and no executable". `INTENT.md` says "nothing
that can be deployed". `docs/WHAT-IT-TALKS-TO.md` says "there is no executable
target, so there is no moment at which it could fetch anything". `SECURITY.md`
says the scope has "no network access, no key material and no persistence of
its own". Four of those five were true when written; the fifth stopped being
true when the store landed and nobody went back.

The standard this repository has held to is that a short true statement beats a
long plausible one, so the rule for this pass is: **a sentence that is now
false is worse than one that is missing.** Every claim listed here is rewritten
or deleted. Nothing is left to be inferred from what is no longer listed.

Two claims get harder rather than easier, and they are the ones to write first,
because writing them is how you find out whether the design survives contact
with a reader. TRUST-4.a, that nothing arrives at startup from somewhere nobody
named, was free while there was no startup and now has to be argued. And
TRUST-1's list has only ever had outbound entries, because until now nothing
could talk **to** this.

## README.md

This is the document ADOPT-4 is measured against: somebody gets from a clean
machine to a running bot by following it alone. For the first time that is
partly achievable, so the README stops being a description of a library and
starts being something a person follows.

**The State section.** "Early. Not runnable yet" becomes a statement of what
running it does. The danger of the first runnable version is that a reader
assumes a bot, so the first two sentences must say both halves: it boots, reads
a configuration, opens a store, checks the asset against the node and answers a
health endpoint; it joins no server, answers no command, verifies no wallet and
sends nothing. The paragraph about being built in the open out of a private bot
stays as it is. It is the honest framing and it names nothing.

**A new section, before the engine chapter**, because it is now what most
readers came for. As transcripts rather than prose:

- `swift run bot` on a clean machine: the spending banner, the one variable
  named, its purpose sentence, exit 78, and the line pointing at `check`. This
  is the most useful paragraph in the README for a new contributor and it is
  the acceptance criterion made visible.
- `swift run bot check`: the whole catalogue with each entry marked set or
  unset, plus the first refusal. Say plainly that it opens no socket, no store
  and no connection, so a reader knows they can run it with a half-written
  configuration and learn something.
- `swift run bot rehearse`: the operator's own ladder decided over invented
  members. Say that the members are invented and the configuration is not,
  because that distinction is the whole value of it (BUILD-1.b, ADOPT-6.a).
- `swift run bot` with a valid configuration: the report, then the health
  endpoint answering 503 `starting` and then 200.
- One sentence on the default: no arguments means `run`, because that is what a
  container's default command does.
- The exit codes, as a five-row table. An operator writing a supervisor unit
  needs 69 in particular, and it is the difference between a duplicate instance
  dying once and a restart loop.

**The variables.** The README needs the complete list of what this build reads:
required or optional, the purpose, the default where there is one. It is the
same content as the table in `docs/WHAT-IT-TALKS-TO.md`, framed differently:
the disclosure lists them because TRUST-1 asks what the package asks of you,
the README lists them because ADOPT-4 asks that following it is enough. Both
should be produced by running `bot check` and reading the output, not written
from memory. A test asserts the catalogue covers every key constant the library
targets export, so the catalogue is the one place that can be trusted.

New here: `STORE_PATH` and `HEALTH_PORT`, both required with no default, and
`HEALTH_ADDRESS`, defaulting to loopback. The README must give the reasons,
because a reader will expect defaults and read their absence as an oversight. A
default store path becomes a second, empty database the first time a supervisor
starts the process from another directory. A default port collides on the
second community hosted on one machine and reads as a duplicate instance. A
default of every interface publishes the waiting list and any provider proof
headers to whoever can reach the box.

**The target table** gains `Runtime` and the executable. Say that `Runtime` is
a target no library product reaches, so nothing downstream can depend on the
composition root's shape while it is at its least stable, and point at
`StoreTestKit`, which is already arranged that way. A reader who has understood
one has understood the other.

**What is missing** loses "No executable" and gains its replacement in the same
place: there is a program, and it hosts nothing yet. Still missing: the chat
surface, wallet verification, every member command, the sweep loop, the
scheduler, and a payer. The line "The Discord surface, the wallet verification
flow and a host that wires the libraries together come next, in that order" is
now one third done and needs rewriting rather than deleting.

**The test figure** on line 28 changes. It is quoted in three places and they
have already drifted apart once; see the last section.

## AGENTS.md

The first thing a contributing session reads, and the document that will
otherwise send somebody looking for an executable it says does not exist.

- "What this is": rewrite the two sentences that say there is none. Keep the
  shape, a list of what each target is for, and add `Runtime` as the
  composition root with the executable beside it.
- "Where things live": rows for `Sources/Runtime`, `Sources/BotMain` and
  `Tests/RuntimeTests`, in the voice of the existing rows, which say what a
  directory holds and why rather than listing files. The `Sources/Runtime` row
  carries the two prohibitions: it may never link a chat client and it may
  never open a database, because it takes `any BotStore`.
- "Rules that bite" gains three, since this is where the repository keeps what
  a reviewer would otherwise have to remember:
  - *Local resources are claimed before anything announces this process to an
    outside service.* Give the reason in one sentence, because the reason is
    what makes it survive: a second copy that identifies first takes the live
    copy's session away and then dies anyway, and under a supervisor that is a
    loop knocking the working bot over. Then the correction this package makes:
    the duplicate guard is the store lease, not the bind, because the port is
    configuration and a second copy on a different port binds happily.
  - *The process environment is read in one place, in `BotMain`.* Name the
    other door that already exists,
    `ChainConfiguration.loadFromProcessEnvironment`, and say it stays public
    for a third party host and is forbidden here.
  - *Whether a build can spend is a parameter of the composition, never a
    reading of the settings.* And, in the same breath: no `TEST_MODE`, no
    `DRY_RUN`, no `SAFE_MODE`, ever, in any target.
- The existing rule "Nothing below the chat boundary holds an identifier that
  came from a person" now has an above as well as a below. Extend it with the
  allowlist: the composition root and the executable are the only directories
  permitted to name a chat client, and a test scans every other directory under
  `Sources/`.

## docs/WHAT-IT-TALKS-TO.md

The largest change, and REQ-runtime-031 makes it a condition of the change
rather than a courtesy. Eight edits:

1. **The short version table** gains a row: "Does anything talk to it?" The
   answer becomes one TCP listener, on loopback unless you widen it, one path,
   no authentication, and it is the health check.
2. **A new Inbound section** beside the outbound one: what the listener
   accepts, what it answers, what the body can contain and what it never
   contains. The body matters. `ChainHealthReport` copies configured provider
   response headers into its JSON, so the endpoint can carry a value the
   operator's provider sent. That is the argument for the loopback default, and
   the document should make the argument rather than state the default.
3. **The "Nothing phones home" greps.** Two of the three now return hits. The
   socket grep finds the listener; the filesystem grep should already have been
   finding the SQLite layer and did not, because this document predates it.
   Rewrite the section to name the expected hits and say what each one is. A
   disclosure whose commands no longer produce the stated output teaches a
   reader to stop running the commands, which is worse than having none.
4. **The paragraph about having no startup** goes, and TRUST-4.a is argued
   instead of assumed. The argument: the program fetches nothing at boot; the
   only outbound call before it is serving is the asset precision check against
   the node the operator named; that check is switchable with
   `CHAIN_VERIFY_ASSET_DECIMALS`; and the startup report says which gates ran.
   Give the grep that checks it.
5. **The half-answered TRUST-1.a** becomes partly answered: there is now a
   surface that reports which provider served the last probe, and it is the
   health endpoint. Say exactly what it reports and what it still does not,
   which is any history of what the instance has reached.
6. **The secrets table** stays one row. `CHAIN_API_TOKEN` is still the only
   secret the package asks for, and that is worth saying in those words now
   that there is a program, because a reader's prior is that a runnable bot
   wants a token and a key. Add the sentence that the report prints whether a
   secret is set and never its value, nor a length, nor a prefix, nor a hash,
   and that URLs are reported as scheme, host and port because a provider can
   carry a credential in a path.
7. **The variables tables** gain `STORE_PATH`, `HEALTH_PORT` and
   `HEALTH_ADDRESS`. None is a secret. Note that `STORE_PATH` must be absolute
   and why.
8. **The dependency table is unchanged, and the document should say so in those
   words.** No argument parser, no networking package, nothing new in
   `Package.resolved`. That is a deliberate decision of this change, and this
   is the document where somebody deciding whether to install it looks for it.

## SECURITY.md

The Scope section says the engine has no network access, no key material and no
persistence of its own. Two thirds was already wrong and this change finishes
the job by opening a listening socket.

Rewrite Scope to say what the repository now contains and what a report about
it would be about. Add the listener to the things that must go through a
private advisory: anything that reads memory, files or configuration out of the
health endpoint, anything that stops or crashes the process from an
unauthenticated request, and anything that gets the startup report to print a
secret. The three existing bullets stay exactly as they are; they describe code
that still does not exist and the file already says that on purpose.

## CHANGELOG.md

Under `Unreleased`:

- **Added**, one paragraph in the voice of the existing entries, which say what
  a thing is and what rule it keeps rather than listing symbols. It must carry:
  the executable and the composition root; boot gates in a fixed order that
  name the variable to fix; the store lease taken and the listener bound before
  anything could identify to a chat service; a health answer that says
  `starting` until the parts that are switched on are up, so a bound socket
  never reads as ready; a startup report that says what the build made of the
  settings and never prints a secret; and that no build can send anything and
  every start says so.
- **Added**, the new variables, named, with `STORE_PATH` and `HEALTH_PORT`
  marked required.
- **Changed**: nothing in the six library products. Say it explicitly. The
  existing Changed section is careful about source-breaking changes and a
  reader deserves to be told this one is additive.
- **Known gaps**: rewrite the section. "There is no Discord surface, no wallet
  verification, no persistence, no host and no executable target" becomes
  accurate: there is a host and an executable, persistence landed earlier and
  the entry was never updated, and the two real gaps are the chat surface and
  verification. Add the two honest ones this change creates: a misconfigured
  node URL that resolves to nothing leaves a process running and permanently
  `starting` rather than exiting, which is safe only if the deploy gate reads
  the health answer; and the spending state is in the report and not in the
  health body, so a monitoring check cannot see it.

One release consequence, recorded while it is fresh: two new required variables
make this a **minor** bump under the rule `CONTRIBUTING.md` already fixes.

## CONTRIBUTING.md

Three small things.

- The opening says "four library targets, built in the open, with the Discord
  surface still to come". It is six, now with a program around them.
- The Releases section says the first tag "should not be cut until there is
  something a person can run". That sentence now has to decide rather than
  defer. The honest reading is that a bot which joins no server is still not
  something a person can run for their community, so the bar is unchanged. Say
  so, or somebody will read this change as clearing it.
- Cutting a release has to bump the version constant in `Runtime`, so it is a
  numbered step beside the changelog step. A version that lies in the startup
  report is worse than one that is absent.

## specs/runtime/

The new module contract, and the reason this change could declare no canonical
spec changes: it is an addition, not an edit to a merged contract. It needs the
seven sections `.specsync/config.toml` requires, which are Purpose, Public API,
Invariants, Behavioral Examples, Error Cases, Dependencies and Change Log, plus
the companions this repository actually uses.

What each section must carry that is not obvious from the code:

- **Purpose.** That this target composes and does not decide. Every rule about
  tiers, amounts, budgets and records belongs to a target below it, and the
  composition root adds no policy of its own. This is the sentence that stops
  `Runtime` accumulating logic over the next year, and it is worth being the
  first line.
- **Public API.** One row per exported name, in source order, which is the
  shape the other specs use and what `specsync check --strict` compares
  against. Keep the export list deliberately short: the less of the composition
  root is public, the less of it anybody builds on.
- **Invariants.** The gate order; the single settings snapshot; a component per
  part that is on and none for a part that is off; the capability that no
  setting can reach; the report that never prints a secret; and
  `ListenerBound`, with the sentence saying what it makes impossible rather
  than what it is.
- **Behavioral Examples.** The clean machine, the valid configuration, the node
  that does not answer, and the second instance. Those four are what somebody
  reads the spec to find.
- **Error Cases.** Every refusal, each naming its variable and its exit code.
- **Dependencies.** The three targets it links, `Gating`, `Chain` and `Store`,
  and the three it deliberately does not: `Games` and `Reserve`, because
  nothing yet plays or pays, and `StoreSQLite`, because the composition root
  takes `any BotStore` and the executable chooses the durable one. A dependency
  nobody calls is one an auditor has to rule out, and that cost is paid by
  every reader of `docs/WHAT-IT-TALKS-TO.md`.
- **Change Log.** The initial entry.

Companions: `requirements.md` carrying the `REQ-runtime-<n>` ids from this
workspace unchanged, `context.md` for the decisions and the soft spots, and
`testing.md`, which is the module's standing test map. That last one is
distinct from this workspace's `testing.md`: the workspace document is the plan
for this change and will be archived, the spec document is what the module's
tests cover from now on. Write it by carrying the tables and the requirement
coverage across, not by linking to an archive.

## .specsync/config.toml

`source_dirs` gains `Sources/Runtime` and `Sources/BotMain`. Adding sources
without a contract turns the gate red, which is the point, so the spec above is
written first.

One thing to confirm rather than assume: whether one spec may own two source
directories. `specs/chain/chain.spec.md` lists its files explicitly in
frontmatter, which suggests file-level ownership and that a single
`specs/runtime/` covering both is fine. If the tool insists on one spec per
directory, the fallback is to keep `BotMain` at the single file the design
calls for and give it a minimal spec of its own. The fallback is never to leave
a directory out of `source_dirs`: a directory outside the gate is where an
undescribed export goes to live.

## INTENT.md

Two sentences. "What exists today is four libraries" is six. "There is **no
gateway, no command, no database and nothing that can be deployed**" needs the
last two clauses changed and the first two kept, because the gateway and the
commands are still genuinely absent and that is the whole honesty of the
document. The family index is generated and does not change.

## hi/

**No change, and that is a decision rather than an oversight.** Everything this
change builds is already written down: RUN-9.a for a version that refuses and
names the setting, RUN-7 and RUN-7.a for the second copy, RUN-8.b for the day's
budget surviving a restart, SEE-1 and SEE-1.a for a check that means more than
a live process, SEE-1.b for a check that costs nothing, SEE-10 and SEE-10.a for
naming which piece is down, ADOPT-2 and ADOPT-9 and ADOPT-9.a for finding out
you set it up wrong, ADOPT-12.a and ADOPT-12.b for the network, CATALOG-6.a for
the settings never showing a secret, BUILD-1.a and BUILD-1.b for the
contributor with no credentials, BUILD-3 and its two children for a build that
cannot spend, SPEND-6.c for a community that only wants roles, and TRUST-4.a
for nothing arriving at startup.

One genuine gap is worth recording here rather than quietly filling: **nothing
in `hi/` says outright that the listener must be bound before anything
identifies.** RUN-7.a is the nearest and it is about which copy keeps serving,
not about the order of two steps. The behaviour is required by this change's
acceptance criteria and was learned from a real reconnect storm, so it is not
in doubt; whether the want behind it deserves its own criterion is a `hi/`
change and a product decision, and it should be an issue rather than something
slipped into this one. `CONTRIBUTING.md` asks for criteria to be agreed before
the code, and that applies to us.

## Statements that are already false, and get fixed in this pass

Found while reading, listed so they are fixed deliberately rather than
half-noticed:

- `CHANGELOG.md` known gaps says there is no persistence. There is.
- `SECURITY.md` scope says no persistence and no network access. Both were
  wrong before this change.
- `docs/WHAT-IT-TALKS-TO.md` describes four libraries, and says nothing in
  `Sources/` opens a file. Six, and the SQLite layer does.
- `CONTRIBUTING.md` says four library targets.
- The test count is quoted in `README.md`, in the `Tests/` row of `AGENTS.md`
  and in `specs/chain/testing.md`, and the third already disagrees with the
  other two. Take all three from one `swift test` run in this change and prefer
  the whole-package figure, which `AGENTS.md` already explains is the only one
  worth quoting, because a per-target filter matches suite names across targets
  and double counts.

## Documents that do not change

`hi/*`, `CODE_OF_CONDUCT.md`, `LICENSE` and `Package.resolved`, the last
because this change adds no dependency and that is worth stating rather than
observing.

The workflow files are the argument. `tasks.md` asks for a CI job that runs the
built binary twice, once with nothing set expecting a named variable and a
non-zero exit, and once with a fixture configuration and `check` expecting
zero. It is cheap and it guards the acceptance criterion where a pull request
is actually stopped. It also touches `.github/`, which the SpecSync gate covers
and which this workspace's `affected_paths` does not list, along with
`README.md`, `docs/`, `CHANGELOG.md`, `AGENTS.md`, `specs/` and
`.specsync/config.toml`. Widen `affected_paths` before approval rather than
splitting: a release where the executable exists and the README still says
there is none is worse than a larger diff. If it is split instead, the
documentation half must land in the same pull request anyway, which is the same
diff with extra ceremony.

## Settled, and what is not

Three items here were written as disagreements between the sibling artifacts of
this same definition and turned out not to be. They are recorded rather than
deleted, so nobody re-opens them by reading an old draft.

- **The executable product's name is `bot`.** `requirements.md`, `design.md`
  and `plan.md` (D1) all say `bot`, so the README transcripts say `swift run
  bot`.
- **The report carries a version**, as a constant edited when a release is cut,
  which is why `CONTRIBUTING.md` gains the step above. It is what the source
  claimed and the report says so; the real revision needs a build plugin and is
  out of scope (`plan.md`, deliberately out of scope).
- **`HEALTH_PORT` has no default.** Required, and `plan.md` D6 records that its
  author's first answer, a conventional default, was overruled and why.

Still open:

- **Whether one spec may own two source directories**, above.
- **Where the report is written.** Standard output is assumed. A container that
  captures only standard error would lose it, and losing it takes BUILD-3.b
  with it. Settle it before the first deployment file exists, and it may be as
  simple as writing the banner to both.
- **Which of the two parallel changes lands first.** REQ-runtime-032 names the
  split with `satisfy-four-criteria-...-was-counted`: that change owns the
  `Chain` half of SEE-1.b and this one owns the endpoint. The disclosure
  document's inbound section describes the endpoint either way, and the body's
  budget section is described by whichever change lands second.
