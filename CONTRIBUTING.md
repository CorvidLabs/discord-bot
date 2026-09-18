# Contributing

Thanks for looking. This repository is early: one library target, built in the
open, with the Discord surface still to come. Small, well-argued pull requests
are very welcome. So is an issue that says a rule here is wrong.

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

## Specs

`specs/reserve/` is the module contract. It changes in the same pull request as
the code it describes. `specsync check --strict` fails when the spec and the
exported API have drifted apart, and it runs in CI.

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

## Code style

Swift 6 with strict concurrency. Four-space indentation, 120 columns, opening
brace on the same line. Explicit `public`, `internal` or `private` on every
declaration. No force unwrap, no `try!`, no `as!`. Descriptive generic parameter
names such as `Value` or `Output`, never `T`. Document every public symbol.

Money is integer arithmetic in the asset's smallest unit. Nothing near an amount
touches a `Double` or a locale.

## Reporting a vulnerability

Not here, and not in a public issue. See [SECURITY.md](SECURITY.md).
