---
spec: gating.spec.md
---

## Automated Testing

`swift test` runs the whole package: 236 tests in 17 suites, all offline. 131
of those, in 10 suites, are this module's.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `AdminAllowlistTests.swift` | Unit | The list starting empty, nobody added at boot, every entry removable including the last, exact comparison, and a list past the scan limit refused. |
| `CollectionConfigurationTests.swift` | Unit | Any number of collections, the required creator, the configurable supply ceiling, the match rules, stacked count rungs, and every refusal a collection can raise. |
| `GatingConfigurationTests.swift` | Unit | The whole environment read in one pass, the token read before the ladder, one asset id copied into every pool, a server that gates on a balance alone, and the full set of roles the bot may ever touch. |
| `GatingFormattingTests.swift` | Unit | Amounts keeping every digit at any precision, including precisions no divisor could hold, grouping that does not move between machines, the lossy short form, and the Discord payload bounds. |
| `LiquidityConfigurationTests.swift` | Unit | Any number of pools, both sides of a pool required, one gated asset id per pool, duplicate ids and LP assets refused, and the two questions a position answers. |
| `ReadingTests.swift` | Unit | Unknown against a read zero, the throwing accessor, combined balances needing both halves, saturating sums, and adding a member's accounts up without demoting them for owning two. |
| `RoleRulesTests.swift` | Unit | The decision end to end: the ladder, pooled holdings, collections, badges two facts share, unread facts holding roles, the verified badge following what the caller stated, unmanaged roles untouched, the orphan sweep guard, and the one-line summary. |
| `TierConfigurationTests.swift` | Unit | No default ladder, the first gap ending it, every refusal with the variable it names, thresholds compared after conversion and reported at the amount they collided on, and a rung with no role staying nameable. |
| `TierLadderTests.swift` | Unit | Which rung a balance reaches, the three ways of not being on one, stacking, an empty ladder, a stored row that named a rung by its display name, and the two hand-built ladders the leniency refuses to guess at. |
| `TokenProfileTests.swift` | Unit | The precision deciding every threshold, absurd decimals refused, saturating conversion, required variables named when missing, and the operator's own branding and links. |
| `GatingFixtures.swift` | Fixture | The worked server the other suites decide against: three rungs, two collections, two pools, a verified role and one administrator. |

### Requirements to tests

| Requirement | Test file | Test names |
|-------------|-----------|------------|
| REQ-gating-001 | `TierConfigurationTests.swift`, `CollectionConfigurationTests.swift`, `TokenProfileTests.swift`, `AdminAllowlistTests.swift` | "A server that configured no rungs is told to configure one (ADOPT-1.a)"; "A collection with no minting account is refused, because there is no default creator"; "The operator's logo, colour and links are theirs, and nothing is there by default"; "A fresh deployment has no administrators except the ones its operator named (HOST-3)" |
| REQ-gating-002 | `GatingConfigurationTests.swift`, `TierConfigurationTests.swift`, `CollectionConfigurationTests.swift`, `LiquidityConfigurationTests.swift` | "A server that gates on a balance alone needs no collections and no pools"; "A ladder is as long or as short as the operator wants"; "A third collection needs no code, only a third set of variables"; "A server brings its own pools, and adding one is a set of variables rather than a release" |
| REQ-gating-003 | `TierConfigurationTests.swift`, `CollectionConfigurationTests.swift`, `TokenProfileTests.swift`, `AdminAllowlistTests.swift` | "A mistyped rung number drops that rung and the ones above it, rather than renumbering"; "A rung written with nothing in it is the same as a rung not written"; "A mistyped count rung number drops it and the ones above it"; "Links are numbered from one and the first gap ends the list"; "An allowlist longer than this module reads is refused, not quietly cut short" |
| REQ-gating-004 | `ReadingTests.swift`, `RoleRulesTests.swift` | "Nothing read and nothing held are different answers to different questions"; "A member whose balance nobody could read keeps the rung they had"; "A member who was read and holds nothing does lose the rung"; "A collection nobody could count holds its own roles and lets the rest be decided"; "A badge two collections grant is not taken away because only one of them was counted"; "A read fact still grants a badge it shares with one nobody could read"; "A sweep that read nothing about somebody takes nothing away from them"; "The verified badge follows what the caller said, and there is nothing else it could follow" |
| REQ-gating-005 | `RoleRulesTests.swift`, `ReadingTests.swift` | "What I have parked in a pool counts toward my rung the same as what sits in my wallet"; "Pooled holdings add up across every pool"; "A server that counts no pools decides the ladder from the balance alone"; "A server that does count pools still waits for them"; "A combined balance needs both halves before it is a number at all" |
| REQ-gating-006 | `RoleRulesTests.swift`, `CollectionConfigurationTests.swift` | "Holding one piece earns that collection's badge"; "Holding more pieces of a collection earns more of its roles, and keeps the earlier ones"; "One collection's roles do not follow from another's"; "Holding more pieces earns more roles, and keeps the ones underneath" |
| REQ-gating-007 | `CollectionConfigurationTests.swift` | "A piece belongs to the collection whose rules it satisfies, and to no other"; "A creator's fungible token is not one of their pieces, however much of it somebody holds"; "A collection minted as editions is configuration, not a collection that matches nothing"; "Match rules ignore case, because an operator types a prefix the way they say it" |
| REQ-gating-008 | `RoleRulesTests.swift`, `GatingConfigurationTests.swift` | "A badge a moderator handed out by hand survives every sweep"; "Only roles the operator configured are ever taken away"; "Every role the bot may ever touch is knowable before it touches one" |
| REQ-gating-009 | `RoleRulesTests.swift` | "A sweep against a database that lost its members refuses rather than stripping the server"; "A refused sweep hands back no baseline, so the guard cannot be lowered to the wrong count"; "An odd baseline is halved the way the rule reads, not the way integers divide" |
| REQ-gating-010 | `ReadingTests.swift` | "Linking an empty second account does not demote somebody for owning two wallets"; "Verifying an account again uses the figure just read, not the one stored beside it"; "Every account a member has is added up, wallet side and pool side separately"; "No account read is not a member who holds nothing" |
| REQ-gating-011 | `TierLadderTests.swift`, `TierConfigurationTests.swift`, `GatingConfigurationTests.swift` | "A row that stored the rung's display name still finds the rung (ROLE-1.c)"; "A rung named after the no-rung label is refused, because a stored row could not tell them apart"; "A ladder built by hand with two rungs of one name resolves a stored row to neither"; "A hand-built rung named after the no-rung label does not answer to the label"; "A rung's id is a slug of its name unless the operator gives it one"; "A rung's role is found by the rung's id, so renaming a rung keeps its role" |
| REQ-gating-012 | `TokenProfileTests.swift`, `GatingFormattingTests.swift`, `TierConfigurationTests.swift` | "The same whole-token threshold is a different amount on a different asset"; "A ladder built on one asset's decimals refuses to be read on another's"; "An amount keeps every digit, at whatever precision the asset has"; "A precision no divisor could hold is still written out exactly"; "An amount keeps its grouping on the whole side and every digit on the fraction side"; "Grouping is the same on every machine, because it is not a formatter"; "The short form is for a glance and never for money"; "A refusal over two saturating thresholds prints both numbers and the one they met at" |
| REQ-gating-013 | `TokenProfileTests.swift` | "The operator's logo, colour and links are theirs, and nothing is there by default"; "A logo Discord could not render is refused at load, not on the card"; "A colour that is not a colour is refused, whichever way it is written"; "A link with a label and nowhere to go is refused, naming the URL variable" |
| REQ-gating-014 | `GatingFormattingTests.swift` | "Text too long for Discord is cut and says it was cut"; "A list that will not fit loses whole lines and counts them, rather than being cut mid-word"; "A single line longer than the whole limit is clamped rather than dropped" |
| REQ-gating-015 | `AdminAllowlistTests.swift` | "The allowlist is exactly the accounts the operator numbered"; "Every entry can be taken off, including the last one"; "Adding an account already on the list changes nothing"; "An account is compared exactly, because this layer does not know the alphabet" |
| REQ-gating-016 | whole suite | Every test above runs with no network, no chain, no store and no Discord; `GatingFixtures.swift` is the only setup any of them needs. |

## Manual Testing

- [ ] Write a server's variables from scratch, following only the examples in
      the loader documentation, and confirm every refusal names a variable you
      recognise rather than one you never wrote.
- [ ] Take a working configuration, mistype one rung number, and confirm the
      ladder loses that rung and the ones above it rather than renumbering.
- [ ] Read `hi/role.md` and `hi/adopt.md` and confirm each criterion is either
      cited by a test name or named in `requirements.md`.
- [ ] Check `LoadedTiers.rungsWithoutRoles` against a configuration with a
      deliberately mistyped `TIER_n_ROLE_ID`, and confirm it is the only place
      the mistake appears.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| A data provider that answers for the balance but not the positions | The ladder is held, `unknowns` names the positions, and nothing is revoked. |
| A member read as holding nothing | The rungs are revoked. A read zero and an unread balance must differ, or nobody is ever demoted or everybody is. |
| A caller that forgets a collection entirely | That collection's count is unknown, its roles are held, and every other collection is still decided. |
| One unread fact holding several roles | Reported once in `unknowns`, not once per role. |
| Two collections pointed at one badge, one of them unread | The badge is held rather than revoked, and the collection that was read can still grant it. |
| The provider badge pointed at a rung's role, balance unread | The role is held; the pool badge that was decided is still revoked. |
| A server with no pools and positions never read | The ladder is decided from the direct balance. Waiting for both halves would freeze every ladder for ever. |
| A server with no ladder at all | Every balance is `unranked`, no tier role is managed, and the collections and pools still decide. |
| Balances that overflow when added | Saturate at `UInt64.max`, putting the member on the top rung rather than on none. |
| A whole-token threshold with too many zeros | Saturates to a rung nobody reaches, not a rung everybody reaches. |
| Two rungs whose thresholds both saturate | Refused as two rungs at one threshold, because the comparison is after conversion. |
| A rung renamed with its id kept | Keeps its role and every stored row. Renamed without an explicit id, rows naming the old name orphan until the next sweep. |
| A rung named after the no-rung label | Refused, because a stored row naming the label would resolve to the rung. |
| Zero verified members, or fewer than half a recorded baseline of ten or more | The sweep refuses and records nothing, so the baseline it was measured against survives. |
| A first sweep with no baseline, or a server under ten members | The zero floor alone applies; a small server shrinking is allowed. |
| An empty array handed to `CombinedBalance.across` | Unknown, never a total of nothing. |
| An account re-verified with a fresher figure | The figure just read replaces the stored one for that account, and the others are added on top. |
| A numbered list with a gap at entry three | Entries one and two, and nothing above the gap. |
| An unbroken numbered list continuing past entry 32 | Refused, naming entry 33. |
| Entries 1 to 32 and then 34 | Entries one to 32. The gap at 33 ends the list, the same as a gap at three does, and the refusal above does not reach past it: a loader is given a lookup and can only ask about the number the list would have carried on with. |
| An asset matching two collections' rules | The first configured collection wins, never dictionary order. |
| A collection minted as editions of 25 | Counted, when the operator set the ceiling. Left uncounted when they did not, and the creator's fungible token is never counted either way. |
| `GatingFormatting.amount` with 20 decimals, or 255 | The exact amount, with the point that many places along. There is no divisor, so there is nothing to overflow and no ceiling to answer wrongly at. |
| `GatingFormatting.amount` with no decimals at all | The smallest units, grouped: for a zero-decimal asset they are the whole units. |
| A ladder built in code with two rungs of one display name | A stored row naming it resolves to neither, rather than to whichever rung sorts lowest. |
| A ladder built in code with a rung named after the no-rung label | A stored row naming the label resolves to no rung, which is what the row means. |
| Two ladder rungs whose whole numbers both saturate | Refused, with both numbers written and the one amount they met at, because neither typed number is that amount. |
| A line longer than the whole payload limit | Clamped with an ellipsis rather than dropped. |
