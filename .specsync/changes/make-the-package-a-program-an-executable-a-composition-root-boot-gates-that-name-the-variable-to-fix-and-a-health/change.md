---
id: make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health
state: draft
type: feature
base_commit: b848c0ea12f88511c6da86562bf793b407526d35
---

# Make the package a program: an executable, a composition root, boot gates that name the variable to fix, and a health listener bound before anything identifies to Discord

## Intent

Make the package a program: an executable, a composition root, boot gates that name the variable to fix, and a health listener bound before anything identifies to Discord

## Affected Canonical Specs

- None

## Acceptance Criteria

- swift run on a clean machine with no configuration exits non-zero and names the first variable to set, rather than starting and failing later. With a valid configuration it starts, prints a startup report saying what it made of the settings and never a secret, binds its listener, and answers a health request. The health body says starting until the parts that must be up are up, so a bound socket alone never reads as ready. A build that cannot sign says so at every start, structurally rather than by reading a flag. Every one of these is exercised by a test with no Discord, no chain, no wallet and no database anybody installed.

## No-spec Rationale

A new Runtime target arrives with its own contract under specs/runtime/, which is an addition rather than a change to any existing canonical spec. No merged module's contract text changes.
