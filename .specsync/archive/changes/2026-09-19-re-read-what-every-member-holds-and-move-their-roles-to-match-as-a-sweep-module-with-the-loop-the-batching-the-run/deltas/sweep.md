---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
module: sweep
---

# Semantic delta: sweep

## Modified

### REQUIREMENT REQ-sweep-001

A sweep SHALL visit every member on record and SHALL apply the decision the rules return.

Acceptance Criteria
- Traced to ROLE-1 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-002

A fact that could not be read SHALL hold the roles it decides, and nothing SHALL be taken away for want of it.

Acceptance Criteria
- Traced to ROLE-1.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-003

An account absent from the batch SHALL be read as unread, and SHALL NOT be dropped from the member's total.

Acceptance Criteria
- Traced to ROLE-1.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-004

A liquidity reading that came back short SHALL hold the ladder, and SHALL NOT demote the provider.

Acceptance Criteria
- Traced to ROLE-1.a, ROLE-2 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-005

A collection whose catalogue did not answer SHALL hold only that collection's roles; every other role SHALL still be decided.

Acceptance Criteria
- Traced to ROLE-4.b and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-006

Only roles the operator configured SHALL be added or removed. Every other role SHALL survive, including through the orphan pass.

Acceptance Criteria
- Traced to ROLE-5 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-007

The orphan pass SHALL refuse when nobody is on record, and SHALL refuse when more than half the members have gone since the last pass that ran.

Acceptance Criteria
- Traced to ROLE-5.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-008

The orphan pass SHALL record a baseline only when its guard passes, and a refusal SHALL leave the previous baseline in place.

Acceptance Criteria
- Traced to ROLE-5.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-009

A baseline that cannot be read SHALL refuse the pass, and SHALL NOT be read as a first run.

Acceptance Criteria
- Traced to ROLE-5.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-010

A run record SHALL be written before the work and again after it, so that an unfinished sweep never reads as a finished one.

Acceptance Criteria
- Traced to SEE-2 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-011

A sweep that threw SHALL read as finished with a reason, which SHALL be distinguishable from abandoned.

Acceptance Criteria
- Traced to SEE-2 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-012

Members whose roles did not change SHALL be split into held on purpose and missed, each with a named reason.

Acceptance Criteria
- Traced to SEE-2.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-013

Every line one sweep writes SHALL carry that sweep's run id.

Acceptance Criteria
- Traced to SEE-6 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-014

Problems SHALL be kept where a restart cannot take them, newest first, and SHALL be capped by count rather than by age.

Acceptance Criteria
- Traced to SEE-5 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-015

Every problem SHALL name something an operator could change, rather than the code that gave up.

Acceptance Criteria
- Traced to SEE-11 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-016

Chain reads made by a sweep SHALL be the instance's own work and SHALL carry no member share. A share exists to bound a person, and a sweep is not one.

Acceptance Criteria
- Traced to RUN-11 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-017

Every account SHALL be read in one batch, deduplicated, so that a pool's reserves are read once per pass.

Acceptance Criteria
- Traced to SEE-9 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-018

A restart inside the interval SHALL wait out the remainder, and SHALL NOT read every wallet again, so that a restart loop cannot multiply the day's spend.

Acceptance Criteria
- Traced to SEE-9 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-019

Two passes SHALL never overlap; a second pass SHALL do nothing and SHALL write nothing.

Acceptance Criteria
- Traced to SEE-2 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-020

Only a complete reading SHALL be written back to the store.

Acceptance Criteria
- Traced to ROLE-1.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-021

A member's accounts SHALL be read again immediately before their roles are written, and a list that has emptied since the batch read SHALL hold the write rather than applying it.

Acceptance Criteria
- Traced to ROLE-1.a, ROLE-5 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-022

The orphan pass SHALL read the records again immediately before deciding who is an orphan, and SHALL treat as known anybody present in either reading.

Acceptance Criteria
- Traced to ROLE-1.a, ROLE-5.a and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-023

Stopping the loop SHALL leave a pass in flight to finish, so that no member is recorded as missed for a shutdown.

Acceptance Criteria
- Traced to SEE-2, SEE-5 and covered by the suites named in this change's
  `testing.md`.

### REQUIREMENT REQ-sweep-024

The same address listed twice for one member SHALL be one balance, not two.

Acceptance Criteria
- Traced to ROLE-1, SEE-9 and covered by the suites named in this change's
  `testing.md`.
