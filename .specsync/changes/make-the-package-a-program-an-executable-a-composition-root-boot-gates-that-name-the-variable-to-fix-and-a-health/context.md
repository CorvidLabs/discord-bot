---
change: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
artifact: context
---

# Context

## The problem

There are six library products, 635 tests and 18,521 lines of source in this
repository, and nobody can run any of it. `Package.swift` declares libraries
and no binary, which `README.md:58` states plainly and `AGENTS.md:24` states
again. Every layer can be exercised by a test and no layer can be exercised by
a person.

That is not only a missing convenience. Three things the repository already
claims are unprovable until a program exists.

`ChainHealthReport` (`Sources/Chain/ChainHealth.swift:147`) knows how to say
`starting` rather than `ok`, and nothing serves it. The disclosure document
admits the gap in as many words: "there is no surface that reports it, because
there is nothing running to report it to"
(`docs/WHAT-IT-TALKS-TO.md:146-151`).

Every configuration loader refuses a bad value and names the variable, which is
ADOPT-2, and no operator has ever seen one of those refusals because no process
ever calls a loader. ADOPT-9, reading back what the bot made of the settings,
has nowhere at all to happen: there is no startup, so there is no startup
report.

And the egress check that `docs/WHAT-IT-TALKS-TO.md:274-281` calls the only way
to actually be sure, running the thing behind a firewall rule that permits one
host, "becomes the real check the day an executable target lands". Today it
goes as far as `swift test`.

So the gap this change closes is not "add a `main.swift`". It is that four
separate promises in this repository are written down, implemented, and
unreachable.

## How it was noticed

By counting what the last several tranches built against what a person can do
with it. The engine came first on purpose, and `INTENT.md:37-42` argues that
case well: a bot that renders a card badly is embarrassing for an afternoon,
and a bot that pays a finite reserve twice has spent value nobody can put back.
The cost of that order is that the parts which can only be proved by running
accumulated unproved, and they are now the majority of what stands between this
and somebody else's server.

The second thing that surfaced it is the lifecycle change itself. This
repository has just turned the SpecSync gate on, so anything touching
`Sources/`, `Tests/`, `hi/`, `Package.swift`, `fledge.toml` or `.github/` needs
a defined and approved change workspace. Writing this document before any Swift
exists is the correction to how the previous tranches were done, and the first
target it applies to is the one that will be hardest to change later, because
it is the one every other target gets wired through.

## What this change is not allowed to break

**The binds come before the chat gateway identifies.** This is the one rule
with no acceptable exception, and the reasoning is in `research.md`. Short
version: binding a port is how a second copy of this process finds out a first
copy is running, and a second copy that identified to Discord before finding
that out takes the live copy's session away from it on the way to its own
death. Under a supervisor that restarts it, that is a loop that knocks the
healthy bot offline every time the doomed one boots. The repository already
holds half of this rule: `Sources/StoreSQLite/InstanceLease.swift:20-24`
explains it about the store's file lease, and `SQLiteStore.open` takes that
lease before it opens the handle (`Sources/StoreSQLite/SQLiteStore.swift:123-127`).

**A bound socket is therefore not health.** If binding comes first, there is a
window in which the listener answers and the bot is doing nothing. A deployment
gate that treats an answering port as a working bot will promote a version that
never came up, which is RUN-3 failing in the one way it must not. The listener
has to answer `starting` and say what it is waiting on until the things it is
waiting on are there.

**No target may quietly acquire a chat client.** `Store` declares no chat
dependency, so `import DiscordBM` there is a missing module rather than a
review comment, and `Package.swift:120-123` records that argument. An
executable has to see both a chat client and the store, so it is the first
thing in the repository that could undo that by accident. The graph has to keep
the property by construction once the executable exists.

**Tests keep needing nothing.** BUILD-2 is that the tests run with no network,
no signing key and no database anybody set up, and BUILD-2.a is that nothing in
them can reach a real chain, a real server or a real account whatever is
configured on the machine. A composition root is the exact place that rule
dies, because a composition root's job is to reach for the real things. Every
boot gate in this change has to be reachable from a test that composes doubles,
which means the sequencing lives in something that takes its collaborators as
parameters and the executable is a thin shell that supplies the real ones.

**Nothing falls back to somebody else's value.** ADOPT-6.a. The loaders already
hold this line and the composition root must not soften it by filling in a
plausible default on their behalf.

## Already ruled out

**Reimplementing configuration in the executable.** Every layer already has a
loader that takes a lookup function and refuses by naming the variable:
`TokenProfile.load` (`Sources/Gating/TokenProfile.swift:179`),
`GatingConfiguration.load` (`Sources/Gating/GatingConfiguration.swift:102`),
`ChainConfiguration.load` (`Sources/Chain/ChainConfiguration.swift:132`), and
the numbered-list rules they all share in
`Sources/Gating/NumberedEnvironment.swift`. The job is to call them in an order
and hold the result. A second reader of the same variables is how one layer
comes to disagree with another about what a value means, which this repository
has already paid for twice: the asset written down in two places
(`Sources/Chain/ChainEnvironment.swift:10-16`) and the two layers disagreeing
about whether a trailing newline counted as part of a value
(`Sources/Chain/ChainConfiguration.swift:177-183`).

**A reachability gate on somebody else's service.** The reference
implementation refuses to start when its verification portal does not answer a
health ping. That is rejected here: it makes this bot's ability to start depend
on a third party being up, so their outage becomes an outage plus a restart
loop, and SEE-7 wants the opposite, that a verification outage costs
verification and nothing else. The general answer is that such a dependency is
a named component in the health report, so it does not fail silently either.
This is a deliberate disagreement with the reference and somebody may want to
argue it.

**A mode variable that means "do not spend".** BUILD-3.a forbids it and the
reference implementation is the cautionary tale: it carries a flag that skips
role changes only, a warning in three separate documents saying the flag is not
a money switch, and an audit finding that two commands ignore the flag anyway.
BUILD-3's own intent text says that if a project has to carry a note warning
that a particular flag is not a money switch, the software has already failed
to say so itself, and the note is only load-bearing until somebody new does not
read it. Whatever this change does about spending, it is not that.

**Deleting `ChainConfiguration.loadFromProcessEnvironment`**
(`Sources/Chain/ChainConfiguration.swift:165`). It is the only `ProcessInfo`
reference in `Sources/` today and having two places that read the process
environment is the thing this change is supposed to prevent. It stays anyway,
because `Chain` is a published library product and somebody embedding it alone
is entitled to that convenience. The rule is about this program: the executable
reads the environment once and passes the value down, and does not call that
method. Reasonable people can want it gone instead.

## What a session picking this up mid-flight needs to know

The change title lists four things and they are one thing. The executable is
trivial. The composition root, the gates and the health listener are the work,
and the order they run in is the whole design.

`specs/runtime/` does not exist yet. `change.md` records that this target
arrives with its own contract there and that no merged module's contract text
changes, which is why the change carries no affected canonical spec. The
`Runtime` name is settled by that rationale rather than chosen here; note that
this repository otherwise says "a host" for the thing that wires the libraries
together (`README.md:60`, `Sources/Reserve/ReservePayer.swift:30-33`), so a
reader may expect `Host`, and `Host` is taken by an intent family about
somebody else running your instance, which is a different idea.

`.specsync/config.toml:9-17` lists every source directory with a contract, and
its own comment warns that two branches have already replaced that list rather
than extending it. A new `Sources/Runtime` has to be added to it, and adding it
before the contract exists turns the gate red on purpose.

**A second change is being defined at the same time**, and it owns the other
half of the health answer:
`satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted`
ships the `Chain` side of SEE-1.b, which is the pure assembly of a report from
values, a non-probing read of the last provider proof, and the budget and pause
facts in the body. This change ships the surface: the listener, the route, the
HTTP mapping, the components and the probe's wiring. REQ-runtime-032 writes the
split down, and the same requirement names the other edge between the two, which
is that the sibling change makes every public read on `ChainReader` name its
caller, so the chain gate here names the instance's own work. Neither change
blocks the other; whichever lands second carries the one-line edits.

Read `hi/build.md` BUILD-3 and `hi/adopt.md` ADOPT-2 and ADOPT-9 before
deciding anything about the startup report, and `hi/see.md` SEE-1 before
deciding anything about health. SEE-1.b in particular constrains the
implementation: checking must not spend the day's budget for reading the chain,
and must still answer once that budget is gone, so the health handler reads a
cached snapshot and never issues a request of its own.
