# Contributing

Thanks for looking. This repository is early: four library targets, built in
the open, with the Discord surface still to come. Small, well-argued pull
requests are very welcome. So is an issue that says a rule here is wrong.

## Intent first

Intent is written down before code. `hi/` holds what somebody wants, as plain
sentences with ids that never move and are never reused. `hi/reserve.md` is the
engine's 52 criteria, and the tests cite them by id.

Before you build a feature:

1. Read `hi/` so you know what has already been said. `hi ls` is the whole list.
2. Draft the criteria for what you are about to build, as sentences about what
   somebody wants rather than about what the code will do.
3. Open an issue with them and get them agreed. Nothing lands that nobody agreed
   to.
4. Then write the spec, then the code, then the tests.

A bug fix does not need new criteria. A change to what a person gets, a
threshold, a default, or what happens when we cannot answer, does.

If a criterion turns out to be wrong, the criterion is the fix as much as the
code is. Retire it with a reason and replace it. A criterion nobody can check is
worse than none.

## The change lifecycle

Every meaningful change is defined before it is built, approved before it is
implemented, and reviewed against its own definition before it merges. That is
not ceremony: this repository pays real people in tokens they cannot get back,
and the interview asks the questions somebody would otherwise answer to
themselves halfway through.

`specsync change new` opens a workspace and hands you a deterministic
interview. Answer it, fill the artifacts it selected, and get the definition
approved by the person whose call it is. Then build, with the contract and the
tests in the same change. Then `check`, then `review`, then `finalize`, and
only then merge.

The policy lives in `.specsync/sdd.json`. Its verification command is the same
`fledge lanes run verify` lane the Trust gate runs in CI, so there is one
definition of passing rather than two that can drift.

You cannot approve your own change, and you cannot record a review you did not
perform. A ledger holding one invented approval is worth less than no ledger.

## Specs

`specs/<module>/` is a module's contract, one per target. It changes in the
same pull request as the code it describes. `specsync check --strict` fails
when the spec and the exported API have drifted apart, and it runs in CI.

## Branches

```
<type>/<description>
```

Types: `feature`, `fix`, `refactor`, `doc`, `test`, `chore`. No author prefix:
GitHub already attributes the branch and its commits.

Examples: `feature/reserve-quarterly-periods`, `fix/residue-off-by-one`,
`doc/contributing`.

## Commits

One of these five prefixes, then a sentence in the imperative:

```
Add: new feature
Fix: bug description
Update: existing feature
Remove: deleted functionality
Refactor: code restructuring
```

Write the body for somebody reading it in a year with no memory of the issue.
Say why, not just what.

## Running the gate

```bash
fledge lanes run verify   # swift build, then swift test
specsync check --strict   # the spec and the code still agree
```

Run both before you open a pull request. Plain `swift build` and `swift test`
work too if you do not have fledge installed, but the lane is what CI runs.

## Pull requests

Fill in the template: a Summary in bullets and a Test Plan with the commands you
ran and what they said. If you changed a rule about money, say in the
description which criterion it comes from.

Every change arrives through a pull request, including ours.

## Releases

Nothing has been released yet: there are no tags, and the first one should not
be cut until there is something a person can run. This section exists so that
when it is cut, it is cut the same way every time.

### How a version is chosen

Four library products, one version number, because a tag names a repository
and not a product. A change to any of the four moves the number for all of
them.

While the major is `0`, the package makes no promise across a minor bump, and
that is the rule to apply rather than the one to feel bad about:

- **Minor** (`0.4.0` to `0.5.0`) for anything somebody could have depended on:
  a changed or removed public symbol, a changed default, a changed threshold, a
  new required environment variable, a new outside service contacted, or a
  behaviour change in what gets paid or which role is granted.
- **Patch** (`0.4.0` to `0.4.1`) for a bug fix, a documentation change, a new
  test, or a purely additive public symbol.

We ask the same of our own dependency, which is why it is pinned
`.upToNextMinor` rather than `from:`. Asking a rule of somebody else and not
keeping it is the kind of thing this repository is trying not to do.

`1.0.0` is for when the public API has stopped moving and there is a bot to
run: a host, persistence and a Discord surface. It is not a way of saying we
are pleased with it.

### Cutting one

1. Be on `main`, with the commit you intend to tag, and with both CI jobs
   green on it. The gate is `swift build`, `swift test` and
   `specsync check --strict` on macOS and on Linux.
2. Check `Package.resolved` is committed and current. `swift package resolve`
   must leave the working tree clean: a release cut against an unresolved or
   dirty lock is a release nobody can reproduce.
3. Check `docs/WHAT-IT-TALKS-TO.md` still matches the code. If the release
   reaches something new, asks for a new secret, or adds a dependency, that
   belongs in the changelog entry as well, because it is the diff between two
   versions that TRUST-1.b promises somebody.
4. In `CHANGELOG.md`, turn `## [Unreleased]` into
   `## [x.y.z] - YYYY-MM-DD` and open a fresh empty `## [Unreleased]` above it.
   Anything still unfinished stays in the new `Unreleased`, not in the release.
5. Commit it as `Update: release x.y.z`, which is one of the five prefixes
   above rather than a sixth invented for the occasion.
6. Tag that commit `x.y.z`, with no leading `v`, and push the tag.
7. Publish a GitHub release on the tag whose notes are that changelog section,
   unedited. Two places saying different things about one release is worse than
   one place saying it.

A tag never moves, is never deleted and is never reused, including for a
release we regret. A release that turns out to be broken is withdrawn by
releasing another one that says what was wrong with it.

### A release that fixes a vulnerability

Somebody running an old version has to be able to tell from the release
whether the hole they read about is still in what they are running
(TRUST-3.a). So:

- The changelog section gets a `### Security` heading naming the advisory, the
  versions affected and the first version that is not.
- If the hole could lose money, whether by paying twice, paying somebody
  ineligible, paying past a limit, or exposing key material, the entry says so
  in those words and the release notes open with it. An operator has to be able
  to tell it apart from a release they can take next month (TRUST-3.b).
- The version is chosen by what changed, not by how urgent it is. A security
  fix that changes no API is still a patch, and saying it is urgent is the
  changelog's job rather than the number's.

Report one privately first. See [SECURITY.md](SECURITY.md).

## Code style

Swift 6 with strict concurrency. Four-space indentation, 120 columns, opening
brace on the same line. Explicit `public`, `internal` or `private` on every
declaration. No force unwrap, no `try!`, no `as!`. Descriptive generic parameter
names such as `Value` or `Output`, never `T`. Document every public symbol.

Money is integer arithmetic in the asset's smallest unit. Nothing near an amount
touches a `Double` or a locale.

## Reporting a vulnerability

Not here, and not in a public issue. See [SECURITY.md](SECURITY.md).
