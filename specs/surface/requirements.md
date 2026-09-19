---
spec: surface.spec.md
---

## User Stories

- As a member, I want to prove an account is mine without handing anybody a
  key, and I want the role beside my name to follow (VERIFY-1, ROLE-1).
- As a member, I want to read what this server will keep about me, who runs
  it and what other members will see, before I sign anything (VERIFY-6).
- As a member, I want to unlink and stop being tracked (VERIFY-3, VERIFY-7).
- As a member, I want to find out from inside Discord whether the bot is
  awake and what it can do here (LEARN-3, LEARN-4, LEARN-8).
- As somebody running this, I want a second copy started by accident to die
  without taking the working bot with it (RUN-7, RUN-7.a).
- As somebody running this, I want a command Discord would reject to fail a
  test and fail a boot, not crash-loop a deploy (ADOPT-2).
- As somebody running this, I want to be told the exact permissions this bot
  needs and the invite that grants them (ADOPT-11, ADOPT-11.a, ADOPT-11.b).
- As somebody running this, I want one check that tells me whether the bot is
  really working, without it costing me the thing I am checking on (SEE-1,
  SEE-1.a, SEE-1.b, SEE-10).
- As somebody running this, I want to run only the parts I want (ADOPT-10,
  ADOPT-10.b).
- As a contributor, I want the tests to need no token, no network and no
  guild (BUILD-2, BUILD-2.a, BUILD-2.b).

## Acceptance Criteria

### REQ-surface-001

The chat library SHALL be reachable from one target only. No engine target
SHALL import it or list it. (BUILD-2, TRUST-4)

### REQ-surface-002

A member's chat account id SHALL enter `Store` only as a `String`. No
snowflake type SHALL appear outside the adapter. (VERIFY-4, VERIFY-7)

### REQ-surface-003

Boot SHALL take the store lease, then bind every port this process owns, then
identify. Identify SHALL NOT be reached if the lease or a bind failed.
Registration over HTTP MAY happen between the binds and identify. (RUN-7,
RUN-7.a)

### REQ-surface-004

The health listener SHALL bind before identify and SHALL answer `503` until
the gateway is ready. A `200` SHALL name Discord, the store and the
verification half separately, and SHALL spend no chain request. (SEE-1,
SEE-1.a, SEE-1.b, SEE-10)

### REQ-surface-005

Every command this process registers SHALL be a value in a catalogue, and
registration SHALL map that catalogue. (BUILD-2)

### REQ-surface-006

A validator SHALL refuse, offline, a catalogue Discord would refuse: a
required option after an optional one in the same array, an empty or
over-long name or description counted in UTF-16, a name outside Discord's
character set, duplicate names, more than twenty-five entries in one array,
and illegal nesting. A refused catalogue SHALL fail a test and SHALL fail a
boot. (ADOPT-2)

### REQ-surface-007

This instance SHALL serve one server. An interaction from any other SHALL be
refused ephemerally and SHALL read and write nothing. Commands SHALL be
registered as guild commands. (HOST-6, HOST-10, HOST-10.a)

### REQ-surface-008

Every inbound interaction SHALL be answered, including an unknown command and
an unrouted component id.

### REQ-surface-009

Each command SHALL declare its acknowledge policy, and the router SHALL
enforce it. Autocomplete SHALL never defer.

### REQ-surface-010

A command that can outlive a fifteen-minute token SHALL report through a
mailbox that writes the outcome before attempting delivery, and SHALL reach
the invoker another way once the token has expired. (RAIN-13, RAIN-13.a,
RAIN-13.b)

### REQ-surface-011

Every outbound payload SHALL be bounded in UTF-16 code units. A payload whose
truncated form would still read as complete SHALL be refused rather than
truncated. An over-long payload SHALL fail in this layer. (RAIN-1.d)

### REQ-surface-012

Every message edit SHALL carry an `attachments` array, empty when there is no
file.

### REQ-surface-013

A card SHALL be a `Sendable`, `Equatable` value with no chat-library type on
it. (BUILD-2)

### REQ-surface-014

A button that does work SHALL carry a namespaced id, not a closure. A link
button SHALL NOT be routed. (BUILD-2)

### REQ-surface-015

Exactly four commands SHALL be registered: `ping`, `help`, `verify`,
`unlink`. (LEARN-3, LEARN-4, VERIFY-1, VERIFY-3)

### REQ-surface-016

`/help` SHALL be ephemeral, SHALL need no account, and SHALL list only
member commands present in the catalogue. (LEARN-4, LEARN-8, LEARN-8.a,
ADOPT-1.c)

### REQ-surface-017

`/verify` SHALL be ephemeral, SHALL never ask for a key, a seed phrase or a
pasted signature, and SHALL say what this server keeps, who runs it and what
other members see, from this instance's configuration. (VERIFY-1, VERIFY-5,
VERIFY-6)

### REQ-surface-018

`/unlink` with no account SHALL list, bounded, and change nothing. With an
account it SHALL remove that one and re-decide roles. Removing the last
account SHALL forget the member, and only then. A member leaving the served
server SHALL be forgotten. (VERIFY-3, VERIFY-7)

### REQ-surface-019

The verification callback SHALL, in order: refuse a foreign server and a
malformed id, admit the member, prove the account, read the chain, build
holdings with unknown rather than zero where a read failed, decide, and apply
only the managed set in one call. An unread fact SHALL NOT revoke the roles it
decides. (ROLE-1, ROLE-1.a, ROLE-5, VERIFY-2, VERIFY-2.a)

### REQ-surface-020

Authorisation for an operator command SHALL be a pure function over
permission bits and role id strings. Registration metadata SHALL NOT be
trusted alone. (SPEND-6.a)

### REQ-surface-021

The catalogue SHALL be built from configuration, and a command needing a part
the operator switched off SHALL NOT be registered. A community that only
wants roles SHALL still boot. (ADOPT-10, ADOPT-10.b, PLAY-9, SPEND-6.c)

### REQ-surface-022

The test suite SHALL run with no network, no token, no guild and no key, and
SHALL NOT be pointable at a live host by anything configured on the machine
running it. (BUILD-2, BUILD-2.a, BUILD-2.b)

### REQ-surface-024

The bot token and the served server SHALL be required with no default, and a
placeholder SHALL refuse the boot. Boot SHALL print what it made of the
settings, the permissions in Discord's own words, and the invite that grants
them. (ADOPT-2, ADOPT-7.a, ADOPT-9, ADOPT-11, ADOPT-11.a, ADOPT-11.b,
RUN-9.a)

### REQ-surface-025

When a portal is configured, boot SHALL detect that the two halves hold
different secrets and SHALL refuse to start. One secret, not two.
(VERIFY-5.b)

### REQ-surface-026

No string a member can read SHALL carry a name, a collection, a ticker, a URL
or a threshold from the project this was ported from. (ADOPT-1.c, ADOPT-1.f,
ADOPT-6, ADOPT-6.a)

### REQ-surface-027

`/ping` SHALL say the bot is awake, SHALL read no chain and SHALL spend no
request budget. (LEARN-3, RUN-11, SEE-1.b)

## Not In This Version

- REQ-surface-023, the disclosure documents, is satisfied outside this spec
  by `docs/WHAT-IT-TALKS-TO.md` and `CHANGELOG.md`.
- The role sweep, every money command, every game command, every operator
  command, and the holdings browser.
