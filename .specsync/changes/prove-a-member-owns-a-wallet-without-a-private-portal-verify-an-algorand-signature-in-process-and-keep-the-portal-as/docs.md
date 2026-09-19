---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: docs
---

# Docs

This change turns the largest written down and unbuilt thing in the repository
into code, and it does **not** finish the job: `requirements.md` keeps
REQ-verify-023 to REQ-verify-029, REQ-verify-035 to REQ-verify-040 and
REQ-verify-042 to REQ-verify-043, fifteen requirements, for a host that does
not exist yet, so after this lands a stranger who clones the repository still
cannot verify a member.
What goes away is the need for a *second* service. What remains is the need for
a first one.

Getting that distinction into the documents is most of the work here. The
tempting sentence, and the wrong one, is that verification now works. Nine
files currently state in counted terms that it does not exist, and the honest
edit changes each of them to say what is built and what is still only written
down, which is `hi/build.md` BUILD-4 and rule 7 of `docs/README.md`.

## The decision record moves first

**`docs/decisions/0001-verification-portal.md`: Proposed becomes Accepted.**

It has to, and not as a formality. `AGENTS.md` says in its own table that a
record marked proposed has not been decided and is not licence to build it, so
this change cannot land while the record still says Proposed. Writing the code
first and flipping the status afterwards would be the record describing a
decision rather than recording one, which is the failure the directory exists
to prevent.

Two things follow, and the second is the uncomfortable one.

- The record's first line says the decision is **not the author's to decide**.
  So the status flips when the person who decides says so, and this change's
  approval is where that happens. Nobody preparing this change may record it.
- The basis has to be written down rather than assumed. It is the section the
  record already calls "The one fact that decides it": verification needs a
  browser page and a small amount of signature checking, and the signature
  checking is already done in process elsewhere, with no web application, to
  sign administrators in. A separate service therefore buys no capability. It
  buys a second thing to deploy, a shared secret that can drift, a boot order
  that takes the bot down when the other half is down, a webhook with a fixed
  size read and a status code that has to be `201`, and every one of those is a
  documented failure mode in `docs/VERIFICATION.md` that exists **only**
  because the page is served by something other than the bot.

What the record gains when the status changes:

| Section | What it must say |
|---|---|
| **Status** | Accepted, with the date and who accepted it. The options stay exactly as written. An accepted record does not get to retouch the case against the option that lost. |
| **Decision** | **The proof is checked in the bot's own process.** B and C are declined. A stays alongside it: the contract stays published, so an operator who wants the page elsewhere can have that, and an existing separate deployment keeps working against a bot built from this repository. |
| **Scope of the decision** | It settles **where the proof is checked**. It does **not** settle where the page is served from, and it does **not** deliver the page. Both sentences have to be in the record. This artifact originally wrote the decision as "D1, the bot serves the page", and `plan.md` and `tasks.md` wrote the opposite; `research.md` supports the narrower reading, because it finds a hostname with TLS required identically under B, C and D1 and therefore not a thing that chooses between them. `context.md` records the reconciliation. The bot serving the page is the intended default, argued for and decided with the executable. |
| **Consequences** | What an operator now needs: an origin a wallet connection will run on. What the project now carries: the wallet connection libraries, at their cadence, forever. What the project did not take on: a second public repository, and an identity provider published in order to ship a signature check. |
| **D, expanded** | The record's option D lists three shapes. A fourth was considered during this change and rejected, and the record is the right place for it: the bot speaking a wallet connection protocol **itself**, with a pairing code posted in chat and no page at all. It is rejected because it does not remove the second thing, it renames it: it would need a relay operated by somebody else and an identifier issued by them, which is a new host and a new secret in `docs/WHAT-IT-TALKS-TO.md`. Write that reason and stop there. Do **not** write that no client library exists for a Swift process — nothing read for this change establishes it, `plan.md` marks the same claim **(external)** and unverified, and a decision record is the last place to put a sentence somebody could disprove with one search. |
| **Why a plain deep link is not an option** | Worth one line in the record because it is the first thing anyone proposes. A wallet deep link of the kind that exists today is a one way instruction to the wallet. It has no path by which a signature comes back, which is why the page is doing more than looking pretty: it is the only thing in the chain that can receive the signed bytes. |
| **What would change this** | The existing three stay. Add a fourth, because it is the risk this work is taking: chat clients open links in their own in app browser, and **whether that browser can complete a wallet hand-off is not known here** — nothing in either implementation read for this handles it or records it, which is an absence of evidence rather than evidence of failure. If it turns out to break for most members rather than some, where the page lives is worth revisiting. Write it as the open question it is (`tasks.md`, open question 5), not as a reported fact. |

Do **not** rewrite the analysis to match the outcome. The value of the record
is that somebody in a year can see C was rejected for reasons unrelated to
whether it would have worked.

## The contract stops describing something absent

**`docs/VERIFICATION.md`** is the biggest edit, and the danger is that it turns
into two documents pretending to be one. It has to stay readable top to bottom
by two different people: an operator running the ordinary setup, who should
never have to learn the callback protocol, and somebody writing their own page,
who needs all of it.

| Where | What must change |
|---|---|
| "None of this is implemented in this repository" | Rewritten, not deleted. What is built is the checker: the challenge, the session, the reader and the ordered check. What is not built is the page, the route and the command. Say both, in that order, in the first paragraph, because this is the document somebody reads to find out whether they can use this. |
| The paragraph pointing at the open question | Replaced by a pointer to the accepted record. It must not restate the reasoning: rule 1 of `docs/README.md` is one fact, one owner, and the reasoning belongs to the record. |
| "The shape of it" | Rewritten around the ordinary case. The bot serves the page, one process, nothing between the halves because there are not two halves. The four calls out and one back become the second shape, not the shape. |
| A new section near the front | The flow end to end from the member's side, written out below once, owned here. |
| A new, third shape | The page served elsewhere, posting the signed blob to the bot's own submit route. The proof stays in process; only the page moves. This costs nothing extra, because it is the same endpoint, and it is strictly better than the assertion webhook because the bot still checks the signature. It is also the answer to the one thing the decision record says would change its mind, so it belongs in the contract rather than in a comment. |
| Everything about the seam | Moved under one clearly marked heading meaning "if a separate service is going to assert the result": the shared secret, the header, the callback, the single read of at most 8192 bytes, the chunking and continue rules, `201` rather than `200`, the retry rules and the boot time reachability ping. All of it stays true. None of it applies to the ordinary case, and a reader should be able to see that from the heading rather than after reading it. |
| "What a member actually proves by signing" | Keeps its ordered checks, which this change implements as written, including that an absent amount is zero. The list grows to fifteen: it gains the transaction type, a fee bounded at the **network minimum** rather than at zero (an absent fee reading as zero for the same reason an absent amount does, which the bound makes load bearing rather than incidental), five forbidden fields rather than three, `rekey`, `close`, `aclose`, `lx` and `grp`, each refused whether or not the signature is good, a pinned address check before the sender for a session minted with a wallet argument, and a subject check sitting immediately before the note, which reads the subject line out of the **submitted** note and compares it against the session's own subject. Write down why the fee bound is the minimum and not zero: nobody has measured which wallets override a fee they were handed, a checker pinned at zero refuses every wallet that does, and at the minimum a leaked blob costs a member a fraction of a cent instead of their balance. A page author who reads only the number will pin their page at zero and wonder why a wallet fails. Say where that one sits and why, because behind a byte-exact note comparison a subject reason placed after the note can never be returned, and a contract that lists it last teaches the next implementer to write it where it cannot fire. Write the wire name `rekey`, not `rekeyto`: the second is the field's name on the dependency's transaction type and never appears on the wire, and a contract that prints the wrong one teaches the next implementer the bug. It also gains the note that a wallet is expected to refuse a transaction built for a different network, so the page must build against the operator's own. |
| A new section, "What the bot never accepts as a proof" | The **eight** host obligations, five from the security review of this change, one from the repair pass after it and two from the owner's decisions, because they are contract rather than implementation detail and somebody writing their own page has to know them. This row said four and then listed five, which is the kind of drift the rest of this document exists to catch. The session id is a bearer credential: it reaches the page in a URL fragment or a request body, never a query string, is never logged, and the page carries a `no-referrer` referrer policy (`REQ-verify-036`). Adoption needs a confirmation in the chat client, so a link alone binds nothing; the checked proof waits in a pending record keyed by the **subject** rather than by the session id, which is consumed by then, with an expiry of its own, and an unconfirmed proof binds nothing at all (`REQ-verify-035`). An authorising key is read from the chain by the bot, for that exact account, at most once per session, and never taken from the submission (`REQ-verify-037`). The command and the submit route are rate limited by the host, not by something assumed in front of it (`REQ-verify-038`). An address bound to the wrong member is releasable by an operator (`REQ-verify-039`). The operator's challenge label is checked at boot, and one carrying a line break or over the bound stops the boot naming the variable, because otherwise the challenge is six lines and the line the subject check reads by index moves (`REQ-verify-040`). The verification command takes an optional wallet argument, which pins the session to one address, and which may be a name the host resolves through a naming service that nothing at boot depends on and whose failure asks the member for the raw address rather than stranding them (`REQ-verify-042`). The page and the reply name the chat account the session belongs to and warn that nobody should ever send a member this link (`REQ-verify-043`), and the document says **why the page rather than the signed bytes**: in a relay the victim is on the operator's real page, which cannot be made to lie about whose session it is, so the display is sufficient for that attack, while naming the member inside the bytes would defend a counterfeit page instead and would cost the rule against a person-derived identifier below the chat boundary. Somebody writing their own page has to carry the name and the warning or the relay defence is not there at all. And, as a tightening of an obligation the contract already carries rather than a seventh one, the duplicate-address check is bound to the session: asked once, about the address the member connected, with a second differing address refused without an answer, so it cannot be walked against the public holder lists (`REQ-verify-028`). |
| The challenge | Five lines, and two departures, both deliberate, both to be written in rather than left for a reader to notice. The subject **is** in the challenge, because the bytes have to say which member the proof will be adopted for: without that line, somebody can run the command and hand their own link to another member, whose genuine signature over a genuine looking prompt then binds their wallet to the sender of the link. What is not in the challenge is the chat account id: the line carries the instance's own minted member key, so nothing that came from a person sits below the chat boundary, and the rule in `AGENTS.md` still holds. A six character code sits beside it, shown in the chat reply and in the wallet. And the nonce is a hundred and twenty eight bits rather than the thirty two the reference takes from a UUID prefix. Write down that the subject is the **third** of the five lines and that the count is enforced rather than assumed: no value rendered into a line may carry a line break and the operator's label is bounded, or a two line label makes a six line challenge and the checker reads the wrong line. An earlier draft of this table said the subject was absent and that the session already provided the binding; that argument answers a different attack and the record of why is in `context.md`. What the challenge does **not** carry, and the page does, is the member's own account name: that is `REQ-verify-043` and the row above, and the two are kept together rather than one replacing the other. |
| "Where the reference departs from this contract" | Stays, and gains rows for the narrow nonce and for the challenge that names no instance. The table is what keeps a reader from mistaking the contract for a description of anything running. |
| "The test mode bypass, said plainly" | Stays word for word in force, and gains one sentence saying what this repository does instead: the suite signs with a generated key, so the checked path runs unchanged and there is nothing to switch off. That section is the clearest statement of BUILD-3 anywhere here and it is aimed at whoever writes the next portal. |
| ~~A new additive paragraph on the callback~~ | **Cut.** This artifact proposed extending the callback so a portal *may* send the signed blob and the challenge alongside the five required fields, with the bot then checking the signature itself. It is a good idea and it is a new protocol feature: nothing in the acceptance criteria asks for it, no requirement defines it, no task builds it and no test covers it. A change that grows a wire format in a documentation artifact is an approval nobody gave. It belongs in its own change, against the third route this design already names, where somebody can weigh it. |

### The paragraph this document owns and nowhere else repeats

The member's experience, on a phone:

1. They run the verification command in the chat client. They may name the
   wallet they mean, by address or by a name the bot resolves for them; if
   they do, the session is pinned to that one address and the resolved
   address is shown back to them before anything is signed. If the naming
   service cannot be reached they are asked for the raw address instead, and
   nothing else about the bot is affected.
2. The reply is theirs alone and, before any button, says who runs this server,
   what will be kept about them and which of it other members can see. That is
   VERIFY-6, and it is plain text rather than an embed so it can be copied on a
   phone.
3. The reply carries a six character code and the expiry, and a link as text as
   well as a button. It also names their own chat account and warns that only
   they should ever open this link, because a link somebody else sent them is
   the one attack the bot cannot refuse for them.
4. The page opens and, before the wallets, says whose session this is, by the
   account name they know, with the same warning. In a relay they are on this
   real page, so what it says about whose session it is cannot have been
   faked; it is the one moment in the flow at which a first-time verifier can
   see that the link was not theirs. Then the page offers the wallets it
   supports. Tapping one hands off to the wallet application. If the chat client's own browser will not make that hand-off,
   the page offers the system browser or a scannable code instead, because that
   failure is common enough to design for rather than to apologise for.
5. The wallet shows five lines: the community's label, the server, the member
   the proof is for, the six character code the member just read in chat, and a
   nonce. The code and the member line are the parts they can check with their
   own eyes, which is what makes this different from a page that merely looks
   official, and from a link somebody else sent them.
6. They sign a zero amount payment from themselves to themselves, with the fee
   set to zero and accepted up to the network minimum, so a wallet that
   insists on the minimum still works. It is never submitted. It moves
   nothing, costs at most one minimum fee if anybody ever did submit it, and
   leaves no trace.
7. The page posts the signed blob back to the origin it was served from. No
   shared secret, no second process, nothing to configure between halves.
8. The bot checks it and asks the member, in the reply that started all this,
   to confirm. A proof says somebody controls that address; the confirmation is
   the member saying the proof is theirs, and it is why a link somebody else
   got hold of is no use to them. If their phone killed the chat client during
   the hand-off, the proof is still waiting for them when they come back: it is
   held against the member rather than against the session, which is gone by
   then, and it expires on its own if nobody confirms it. Until they do, it has
   bound nothing.
9. On confirmation the bot records the account, assigns roles, and the member
   finds the original reply naming the account they proved.

## What an operator sets, and why the answer is nothing yet

**`docs/CONFIGURATION.md`** owns every variable, and the rule is that a change
adding one edits this file in the same change. This change adds none.

`design.md` lists a route variable, the operator's label, the wallet list and
the session lifetime as edits here. That is right about what those variables
will be and wrong about when they arrive, and the difference matters:
`requirements.md` REQ-verify-002 and REQ-verify-017 say `Verify` reads no
environment variable at all, and REQ-verify-023, which is where the route
variable actually lives, is a host obligation verified when the host lands.
Documenting a variable nothing reads would be this document describing a
setting an operator cannot set, which is rule 7 in the other direction.

So the edits here are small, and the section arrives with the host:

- Line 18 says "There is no executable yet. This package is six libraries".
  The count changes. The sentence about there being no executable stays true
  and should stay.
- The list of loaders that read configuration is unchanged. `Verify` joins
  `Reserve`, `Store`, `StoreSQLite` and `Games` in the sentence naming the
  targets that read no environment variable at all, which is worth stating
  positively rather than by omission, because for this target it is a security
  property rather than a happenstance.

If somebody wants the variables written down before the code reads them, the
place for that is the module contract in `specs/verify/` naming them in its
error cases, or the host's own change. Not here. That includes whatever the
naming service behind the wallet argument eventually needs: it is a host
variable, `REQ-verify-042` is a host obligation, and nothing in this change
reads it. Its **host**, on the other hand, goes into
`docs/WHAT-IT-TALKS-TO.md` now, because that document answers a question
somebody asks before installing rather than while configuring.

## What it talks to

**`docs/WHAT-IT-TALKS-TO.md`** changes exactly as REQ-verify-022 requires, and
less than a reader might expect, because this change adds no host, no secret
and no listener.

- **`swift-crypto` moves from arriving with the Algorand package to being
  declared here.** It is already in `Package.resolved`, so nothing new is
  downloaded and no resolved version moves. TRUST-1.b is that something new is
  a diff somebody reads rather than something that appears quietly, and a
  direct dependency line is that diff.
- **`Verify` is listed in the target table as opening no connection.** The
  document is careful that "it only imports Foundation" is not a guarantee on
  its own, and answers it with a grep. The same grep answers it here, and
  `TargetShapeTests.swift` turns that grep into a test, which is stronger than
  the document has been able to claim for anything so far and is worth saying.
- **One new outbound host, written down now and reached later: the naming
  service.** The wallet argument may be a name, and resolving one is a call to
  a service this package does not talk to today (`REQ-verify-042`). The row
  goes in with this change, flagged as not yet true in the same way as the
  line below about what a member's browser will reach, because TRUST-1 is a
  list somebody reads before they install and a disclosure that waits for the
  call is a disclosure that arrives late. The row says it is optional,
  reached only when a member types a name rather than an address, that
  nothing at boot depends on it, that a failure asks the member for the raw
  address, and that `Verify` is not the target that calls it.
- **No inbound section yet.** Nothing in this change binds a socket. When the
  host does, this document gains a direction it has never had, and that is the
  host's change to make. Adding the section now would describe a listener that
  does not exist.
- **What the member's browser will reach, when there is a page.** Worth a
  forward looking line now, flagged as not yet true, because it is the single
  thing about this design an operator would most want to know before they
  install: the bot process talks to nobody new, and the member's browser talks
  to their wallet's own infrastructure. When the page lands, every script and
  style it loads must come from the operator's own origin, or that origin's
  owner sees every member who verifies.
- Line 14 says "The package is four offline libraries". That was wrong before
  this change, at six, and is wrong differently after it. Fix it to the real
  count.
- Line 142 says there is no executable target and therefore no moment at which
  it could fetch anything. Still true. Leave it, and leave it deliberately
  rather than by not noticing.

## The counted claims that become false

Specific sentences with numbers in them, found by grepping for what they
assert. Each is checkable and each is wrong the moment the target lands.

| File and line | Says now | Must say |
|---|---|---|
| `README.md:14` | no gateway, no slash commands, no executable target, nothing you can deploy | unchanged and still true. Resist editing it |
| `README.md:15` | six library targets | seven, with a row in the table for `Verify` |
| `README.md:28` | `swift test # 635 tests in 47 suites` | the figure `swift test` prints, quoted from the run and nowhere else, per rule 6 |
| `README.md:55` | "**No wallet verification.** Nothing signs a challenge." | rewritten, not removed. Something now checks a signature; nothing yet asks for one. This entry is the clearest statement in the repository of the gap between the two, and it should stay clear rather than become optimistic |
| `README.md:67` | `Package.swift` declares six libraries and no binary | seven and no binary |
| `README.md:81` | the ordering sentence: the Discord surface, the wallet verification flow and a host come next | half of the middle item is now done. Reword so a reader can see which half |
| `AGENTS.md:17` | six library targets and no bot | seven |
| `AGENTS.md:24` | no gateway, no slash command and no executable | unchanged and still true |
| `AGENTS.md:82` | 635 tests in 47 suites, six targets | the figures from the run, seven targets |
| `AGENTS.md`, "Where things live" | no row for `Sources/Verify` | a row, saying it holds the proof of ownership and depends on no chat client, no database and no clock |
| `AGENTS.md`, the `docs/VERIFICATION.md` row | "Written before the code, so it is a contract to build to rather than a description of anything here" | half of it is now a description. Say which half |
| `AGENTS.md`, "Rules that bite" | no rule about identity | one more: nothing in this repository accepts a proof of ownership that is not a checked signature, whatever is configured and whatever the build. It sits naturally beside the money rules and it is the rule this change exists to make structural |
| `CONTRIBUTING.md:3` | four library targets | already wrong before this change, at six. Fix it to seven while it is being read |
| `INTENT.md:30` | what exists today is four libraries | the same pre existing drift, same fix |
| `docs/CONFIGURATION.md:18` | six libraries | seven. Keep the sentence about there being no executable |
| `docs/WHAT-IT-TALKS-TO.md:14` | four offline libraries | the real count |
| `SECURITY.md:16` | verifies wallet ownership over a webhook | verifies wallet ownership by checking a signature, and optionally accepts another service's assertion over a webhook |
| `SECURITY.md:26` | the verification webhook bullet | widened to the check itself, the challenge, the session and the reader, not only the callback. Anything that could let somebody claim a wallet they do not control, replay a challenge or forge an authenticated request. The reader is hand written binary parsing and belongs in this list by name |
| `SECURITY.md:54` | the engine here has no network access, no key material and no persistence of its own | still true after this change, because `Verify` opens nothing. It stops being true when the host lands. Leave it, and let the host's change own it |

`CHANGELOG.md:113` sits under a released heading and records what was true
then. Leave it. `Unreleased` gains the new target, the accepted decision with a
link to the record, `swift-crypto` named as a new direct dependency with the
note that no resolved version moved, and one line stating that no build in this
repository accepts a claim of ownership without a checked signature, so a
reader can tell this shape apart from the one `docs/VERIFICATION.md` warns
about.

## The map, which is missing two of its own entries

**`docs/README.md`** is the map of which document owns which fact, and its
table lists neither `docs/VERIFICATION.md` nor `docs/decisions/`, although
`AGENTS.md` lists both. That is pre existing drift in the one file whose whole
job is preventing it, and this is the right change to fix it in, because it is
the change that makes both of them load bearing.

- `docs/VERIFICATION.md` owns the flow by which a member proves an account:
  every check, all three shapes, and what a conforming page must and must never
  do. It does not own what an operator sets, which is `CONFIGURATION.md`, and
  it does not own why the shape was chosen, which is the decision record.
- `docs/decisions/` owns why the product has the shape it has, permanently. It
  does not own how anything works, and no other document restates its
  reasoning. A record marked proposed is not licence to build.

## The module contract

A new target arrives, so `specs/verify/` is added with the seven sections
`.specsync/config.toml` requires, and `Sources/Verify` is added to
`source_dirs` in the same change. The gate refuses a source directory without a
contract, which makes this a build failure rather than a review comment.

`change.md` records that no merged module's canonical spec text changes, and
that holds: this is an addition. The one place to check before relying on it is
`specs/store/store.spec.md`, which lists what the store does not yet hold. This
change does not add a table, because the session store is a protocol with an
in-memory conformer and the durable one belongs to the host, so that list is
unchanged. Say so in the contract rather than leaving a reader to infer it.

## What does not change

- **`hi/`.** Nothing here is a new want. VERIFY-1 already says a member proves
  a wallet without handing anybody a key. VERIFY-4 already says what is proved
  in one community tells no other one anything. VERIFY-5 already says an
  operator can offer verification without asking their members to trust anybody
  but them, and this change is a step toward that rather than the arrival of
  it. BUILD-3 is unchanged and becomes enforced by a test rather than by a
  paragraph. A change that alters what somebody gets edits `hi/` first; this
  one builds what `hi/` already says.
- **The contract's security properties.** Constant time comparison, binding a
  port before the gateway connects, and what a signature does and does not
  prove are all still correct. The first applies only where there is a shared
  secret, the second to any listener, the third everywhere.

## The one thing worth arguing about, and how it was settled

Whether `docs/CONFIGURATION.md` gains its verification section now or with the
host. This document said with the host, on the grounds that nothing reads
those variables yet and that a configuration document describing unreadable
settings is worse than one that is short. `design.md` said now, and `tasks.md`
followed `design.md`, so the artifact somebody executes was on the side that
loses the criterion.

**Settled with the host**, and all three artifacts now say so.
`requirements.md` decides it rather than a preference: `REQ-verify-002` and
`REQ-verify-017` leave nothing in this change that reads an environment
variable, and the route variable is `REQ-verify-023`, a host obligation
verified when the host lands. Documenting a setting an operator cannot set is
rule 7 of `docs/README.md` in the other direction, and the loser would have
been an operator following a document that does not work.

Still worth a reviewer's attention rather than settled: **open question 4 in
`tasks.md`**, what the instance value in the challenge actually is.
`REQ-verify-005` requires one inside the signed bytes and nothing yet says
where it comes from. A minted value needs somewhere to persist it and `Verify`
does not depend on `Store`; the chat server id is to hand and is public and
guessable. That one is genuinely open and it blocks section 4 of `tasks.md`
rather than the change as a whole.
