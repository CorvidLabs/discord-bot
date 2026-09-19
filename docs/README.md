# The documents, and which one owns which fact

A map, so the set does not drift into contradiction. Documentation drifts when
two files are each a reasonable place for the same sentence: one of them gets
updated and the other keeps saying the old thing, and a reader has no way to
tell which is stale. The fix is boring and works: **one fact, one owner, and
everything else links to it.**

## The whole set

| Document | Owns | Does not own |
|----------|------|--------------|
| [`../README.md`](../README.md) | What this is, what exists today, what is missing, and the `Reserve` engine explained with its worked example. The test count, quoted from `swift test` and nowhere else. | Anything an operator has to set. It names variables only by pointing here. |
| [`../INTENT.md`](../INTENT.md) | The index of intent families and why the engine was built first. | The criteria themselves. |
| [`../hi/`](../hi/) | What somebody wants, as plain sentences with ids that never move. The product decision: a threshold, a default, what happens when we cannot answer. | How any of it is built. A criterion never names a type or a variable. |
| [`../specs/<module>/`](../specs/) | One module's contract: its purpose, every exported symbol, its invariants, its behavioural examples and its error cases. One per target, changed in the same pull request as the code. | Anything about another module, and anything an operator reads. |
| [`CONFIGURATION.md`](CONFIGURATION.md) | Every environment variable: what it means, whether it is required, its default, and what goes wrong when it is wrong. The worked example, which a test loads. | Whether a variable is a secret or leaves the machine. That is the next row. |
| [`WHAT-IT-TALKS-TO.md`](WHAT-IT-TALKS-TO.md) | Every outside service this reaches, every secret it asks for, the dependency graph, and the commands that check each claim. | What a variable means or what a sensible value is. |
| [`../AGENTS.md`](../AGENTS.md) | The order of work (intent, then contract, then code) and the rules that bite while writing it. | Process: branches, commits, pull requests, releases. |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | How a change arrives: branches, commit prefixes, the gates to run, the pull request template, how a release is cut. | The rules about the code itself. |
| [`../CHANGELOG.md`](../CHANGELOG.md) | What changed between two versions. New work under `Unreleased`. | Why a rule exists. That belongs in `hi/` or in a spec. |
| [`../SECURITY.md`](../SECURITY.md) | How to report something, and what is in scope. | Everything else. |
| [`../CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | How people behave here. | Everything else. |
| [`../Package.swift`](../Package.swift), `Package.resolved` | What is built, what it depends on, and at exactly which version. | Any prose about the same, which links here instead. |
| [`../.specsync/config.toml`](../.specsync/config.toml), [`../.github/workflows/`](../.github/workflows/) | Which gates run and over what. | Nothing a human reads for meaning. |

## Where to start, by what you came for

| You are | Read |
|---------|------|
| Deciding whether to install this at all | [`WHAT-IT-TALKS-TO.md`](WHAT-IT-TALKS-TO.md), then [`../README.md`](../README.md) for what does not exist yet |
| Setting it up for your own community | [`CONFIGURATION.md`](CONFIGURATION.md), starting at the worked example and reading upward |
| Trying to understand the payout arithmetic | [`../README.md`](../README.md), then [`../hi/reserve.md`](../hi/reserve.md), then [`../specs/reserve/`](../specs/reserve/) |
| About to write code | [`../AGENTS.md`](../AGENTS.md), then the `hi/` family you are touching, then that module's spec |
| About to open a pull request | [`../CONTRIBUTING.md`](../CONTRIBUTING.md) |

## The rules that keep it honest

1. **One fact, one owner.** If you find yourself writing a sentence that
   already exists somewhere else, link to it instead. A copy is a future
   contradiction.
2. **A variable's meaning is owned here in `CONFIGURATION.md`.** Two other
   places may mention a variable and neither restates what it does:
   `WHAT-IT-TALKS-TO.md` lists it to disclose whether it is a secret and where
   its value goes, and a module spec names it in an error case. Adding,
   renaming or changing the default of a variable edits `CONFIGURATION.md` in
   the same pull request as the code.
3. **A new outbound call, host, dependency or secret edits
   `WHAT-IT-TALKS-TO.md` in the same pull request**, and is named in the
   changelog under the release it ships in.
4. **A module's spec changes with its code, never after.** The gate refuses a
   source directory without a contract, and `specsync check --strict` refuses a
   contract that has drifted from the exports.
5. **Intent before either.** A change to what a person gets, a threshold, a
   default, or what happens when we cannot answer, is a change to `hi/` first.
   A bug fix is not.
6. **A number in prose comes from something that runs.** The test count is what
   `swift test` printed. The example configuration is loaded by a test that
   reads it out of the document, so the document cannot quietly stop being
   true. Prefer a claim a reader can re-run over a claim they have to believe.
7. **Say what is not true yet.** This repository is early, and several
   documents describe a shape that is only partly built. Every one of them
   marks what does not exist rather than reading as though it does. A short
   true document beats a long plausible one.
