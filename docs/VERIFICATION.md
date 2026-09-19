# Verification

How a member proves that an Algorand account is theirs without handing anybody
a key, written so that you can build the other half of it from this document
and nothing else.

That is criterion [VERIFY-1](../hi/verify.md), and the reason it needs a
document rather than a paragraph is
[VERIFY-5.a](../hi/verify.md): if proving an account takes a second piece an
operator has to run, they should find that out here rather than from the first
member whose command failed.

**Half of this is implemented in this repository, and it is the half nobody
can reach.** The `Verify` library target now decides whether an account is
controlled by whoever presented a proof of it, in this process, with no second
service: it mints the challenge, keeps the session, reads the signed
transaction a wallet sends back and applies fifteen ordered refusals to it.
`specs/verify/verify.spec.md` is its contract. What is still missing is the
path from a member to it: the `/verify` command, the callback listener and
the adapter that would carry them are written, in `Surface` and
`SurfaceDiscord`, and the executable links neither — so nothing below runs
today, and nobody can verify anybody from a clone of this repository. `Store` has a place to record
that an account belongs to a member (`AccountStore.prove`) and nothing that
puts one there.

What this document is: the contract a working implementation of this flow has
been running against, read out of that implementation's source and corrected
against it. Where that implementation departs from the contract, the
departures are listed at the end rather than quietly adopted.

## Two routes, and the bot half is the same either way

Whether this bot needs a separate web service is recorded in
[`decisions/0001-verification-portal.md`](decisions/0001-verification-portal.md).
What reading the code settled is narrower than that question and worth stating
here, because it changes which parts of this document apply.

**A second deployable that checks the proof is not needed.** Proving ownership
is three moves and only one of them was ever a service. Minting something to
sign needs nothing a bot does not already have. Checking the signature is
thirty lines, because an Algorand address **is** an Ed25519 public key. What
genuinely needs a browser is the return channel in between: a wallet will not
reply to a process it has no session with.

So there are two routes, and they differ in one thing:

| | Who checks the signature | What the bot ends up holding |
|---|---|---|
| **In process** | This bot, in `Verify` | A proof it checked itself |
| **Portal** | The other service | That service's word, believed because it presented the shared secret |

On the portal route the shared secret is the whole trust boundary, and the
software says so rather than leaving an operator to work it out: the two
routes do not share a producer, and the value the portal route yields is named
for the fact that nothing here checked it.

A page served **anywhere** that posts the signed blob back to this bot's own
submit route is the first row, not the second. The page moving is not the same
thing as the proof moving.

**What `Verify` enforces, which this contract's ordered checks do not yet
carry.** Somebody writing their own page needs all of it, or they will build
something this refuses:

- Exactly one accepted shape: type `pay`, sender equal to receiver, amount
  zero, fee **at most one thousand microAlgos**, no lease, no group, and a
  note that is the session's challenge bytes exactly.
- **The fee is bounded at the network minimum, not pinned at zero.** The page
  should still ask for zero, because a wallet showing a fee on something
  described as free is a member who cancels. The checker accepts a wallet that
  raises it, because nobody has measured which wallets override a fee they
  were handed, and a checker pinned at zero turns an untested wallet behaviour
  into a member who cannot verify and cannot act on the refusal. It is bounded
  at all because a self payment whose fee is the member's whole balance is a
  thing this bot would otherwise bless as proof of ownership while the page
  keeps the blob. At the minimum a leaked blob costs a member a fraction of a
  cent instead of their balance.
- **`rekey`, `close`, `aclose`, `lx` and `grp` are each refused**, whether or
  not the signature is good. The bot never submits, so it cannot be the
  attacker; refusing means it never holds or blesses a signed instrument that
  could empty or reassign an account if it leaked. The wire name for a rekey
  is `rekey`, which is what a canonical encoder emits, and not the name the
  field carries on a transaction type.
- **Fifteen ordered refusals**, and a later one is never returned while an
  earlier one holds: session state, session expiry, blob decode, transaction
  parse, missing fields, transaction type, pinned address, sender, receiver,
  amount, fee, forbidden fields, subject, note, signature.
- **A duplicate key at any depth and any byte after the envelope are
  refused.** The page supplies the unsigned bytes, so it chooses the
  encoding, and a transaction map carrying `amt` twice is one document a
  wallet can display one way and a checker read the other way. The **order**
  of the keys is not held to anything: unique keys say one thing in any
  order, and the envelope this reader's ancestor was patched to accept,
  after a live flow on a phone was refused, carries its signer key after its
  transaction.
- **The duplicate-address check is bound to the session.** A session records
  the address it was connected to the first time one is presented and refuses
  a second differing one without answering anything about it. Asked freely,
  "does this address already belong to a member here?" is an enumeration
  oracle over a public holder list.
- **One call at a time per session.** A session is claimed for the length of
  a call and a second call on a claimed one is refused saying nothing. The
  coordinator is an actor, which bounds one uninterrupted run rather than one
  method: every hop into the store releases it, so without the claim two
  submissions posted together both read a live session, both check a
  signature, and the single use, the attempt bounds and the one authorising
  key retry are all advisory.

**Two departures from the challenge this document describes**, both
deliberate. The challenge is **five** lines rather than four: an operator
supplied label, an identity for this instance, the subject, a six character
code, and a nonce. The subject is the instance's own minted member key rather
than the member's chat account id, because nothing that came from a person may
cross below the chat boundary; the code is what a member compares against what
their chat client just showed them. And the nonce is a hundred and twenty
eight bits from the system generator rather than thirty two taken from the
front of a UUID.

**Eight obligations a host carries**, which are contract rather than
implementation detail and which `Verify` cannot hold up on its own:

1. Exactly one prover route named explicitly in configuration. Naming none,
   like naming both, stops the boot naming both variables. **No route is
   defaulted**, because an operator who meant to run the portal and mistyped
   the variable must not get a bot that quietly verifies members another way.
2. The session id is a bearer credential: delivered only in the reply the
   member alone can see, carried to the page in a fragment or a request body
   and never in a query string, never written to a log, an access log, an
   error report or a crash report, and the page served under a referrer
   policy of `no-referrer`.
3. Adoption needs a confirmation by the member after the proof has been
   checked. The checked proof waits in a pending record keyed by the subject
   rather than by the session id, with an expiry of its own, binding nothing
   at all until it is confirmed.
4. An authorising key passed to `Verify` comes only from the host's own chain
   read of that exact account's authorising address field, attempted at most
   once per session and only on the signature refusal that reports a retry as
   available.
5. The command and the submit route are both rate limited, per member and per
   source, by the host rather than by something assumed in front of it.
6. An address bound to the wrong member is releasable by an operator, with an
   audit line naming who released it and from whom. A lock with no key is not
   a safety property.
7. The operator's challenge label is validated at boot, stopping the boot and
   naming the variable, so an operator does not learn of it from a member
   whose wallet showed them six lines.
8. The page names the chat account the session belongs to, in the display name
   that member's own client would show, with a warning beside it: only
   continue if that account is yours, and nobody should ever send you this
   link. The reply carries the same warning.

**Why the named account is on the page rather than in the signed bytes**, and
not only that it is. In a relayed prompt, where somebody runs the command
themselves and sends the link to a member, the victim is standing on the
operator's **real** page, on the real origin: the attacker's whole
contribution is a link, so the page cannot be made to lie about whose session
it is, and a name on it is the only form of this defence a first-time verifier
can use, because they have no value to recognise. Carrying the same name
inside the signed bytes would additionally defend a **counterfeit** page,
which is a different attack with a different answer, and it would put an
identifier that came from a person below the chat boundary. The opaque subject
line stays in the bytes beside it rather than being replaced by it: that is
what stops a proof being moved between sessions, which no page can do.

What is left over after all of that is a first-time verifier who does not read
the warning. The attack needs somebody to take a link from a stranger and sign
what it shows them, which the rules an operator already publishes cover and
every wallet warns about. It is real and it is largely user error, and saying
so is not the same as dismissing it.

This document describes the portal contract either way: a page served by the
bot itself still has to do everything in
[What a conforming portal must do](#what-a-conforming-portal-must-do).

## The shape of it

The bot cannot ask a wallet for a signature. Wallets talk to browsers and to
each other over WalletConnect and deep links, and Discord is neither. So the
bot hands the member a link to something that runs in a browser, that thing
gets the signature, and it tells the bot the answer. The thing in the browser
is called **the portal** throughout.

Four calls go out from the bot. One comes back. That is the whole surface.

```
  member                     bot                          portal
    |                         |                             |
    |  /verify                |                             |
    |------------------------>|  GET  /api/v1/verification  |
    |                         |  (has this member a link?)  |
    |                         |---------------------------->|
    |                         |<----- 200 or 404 -----------|
    |                         |                             |
    |                         |  POST /api/v1/verification  |
    |                         |---------------------------->|
    |                         |<----- 201 {token,url} ------|
    |<--- a button to {url} --|                             |
    |                                                       |
    |  opens {url}, connects a wallet, signs a challenge    |
    |------------------------------------------------------>|
    |                         |                             |
    |                         | POST /webhook/verification  |
    |                         |<----------------------------|
    |                         |------ 200 {"success":true}->|
    |<-- roles follow --------|                             |
```

`GET /health` on the portal is the fifth call, made once at startup, and
`DELETE /api/v1/verification/{discordId}` is made when a member unlinks.

## Authentication

**One shared secret, held by both sides, sent as the HTTP header `X-API-Key`.**
Header names are compared without regard to case on both sides.

- The bot sends it on every call to the portal except the health check.
- The portal sends it on the callback.
- Each side compares the presented value against its own copy in constant time
  and answers `401` on a mismatch, with no detail about which part was wrong.

There is no OAuth in this contract, no request signing and no mutual TLS. The
secret is the whole trust boundary, so treat it accordingly: at least 32 random
bytes, never in source control, rotated on both sides in the same change.

**One secret, not two.** It is tempting to give the inbound direction and the
outbound direction separate variables, and the working implementation does
exactly that. It is a trap: an operator who sets the inbound one and forgets the
outbound one gets a bot that starts cleanly, passes its own health gate, and
fails every single `/verify` with a `401` nobody sees. See
[Where the reference departs from this contract](#where-the-reference-departs-from-this-contract).

Put TLS between the two services, or keep them on a network nothing else can
reach. The callback carries a member's chat account id and their wallet address
in clear text, and the bot's listener binds every interface and speaks plain
HTTP.

## What the bot calls on the portal

The base URL is configuration, with no trailing slash and no path component.
The bot appends the paths below to it exactly as written.

### `GET {base}/health`

Called once during startup, before the bot has bound anything or spoken to
Discord.

| | |
|---|---|
| Authentication | none |
| Request body | none |
| Timeout | 5 seconds |
| Expected status | `200`. Any other status, a timeout, a refused connection or a TLS failure all count the same: unreachable. |
| Response body | ignored entirely, including when it is empty |

A failure here **aborts the boot**. The bot does not come up in a state where
`/verify` hands members a link into nothing. Make this endpoint cheap, make it
answer without touching your database, and do not put it behind
authentication: it is also what your own deploy gate will poll.

Note what this does **not** check. The health call carries no `X-API-Key`, so a
portal that is reachable with the wrong secret configured passes the gate.
[VERIFY-5.b](../hi/verify.md) asks for the opposite, and a portal that wants to
answer it can: see
[Answering VERIFY-5.b](#answering-verify-5b-at-startup).

### `POST {base}/api/v1/verification`

Creates a verification session. Called when a member runs `/verify`, and again
when a member who already has an account asks to add another.

| | |
|---|---|
| Headers | `Content-Type: application/json`, `X-API-Key: <secret>` |
| Expected status | **`201`, not `200`** |

Request body:

```json
{
  "discordId": "000000000000000001",
  "guildId": "000000000000000002"
}
```

Both are Discord snowflakes as decimal strings, never JSON numbers. A snowflake
does not fit in a double, and a portal that parses one as a number will corrupt
it on the way back out.

Response body, on `201`:

```json
{
  "token": "0123456789abcdef0123456789abcdef",
  "url": "https://verify.example.org/verify-app/?token=0123456789abcdef0123456789abcdef",
  "expiresAt": "2026-01-01T12:15:00Z"
}
```

**`201` is load-bearing.** The bot compares the status against `201` exactly.
A portal that answers `200` with a perfectly good body creates the session,
issues the challenge, and the member is told verification failed. Nothing in
the response distinguishes the two cases, which is why this is worth a line of
its own: it is the single most likely reason a new portal appears to work when
tested with curl and does not work from Discord.

All three fields are required. A response missing any one of them fails to
decode and the member sees an error even though the status was `201`.

| Field | What it is |
|-------|------------|
| `token` | The session identifier. **The bot decodes it and never uses it.** It is never sent back, never stored and never shown. It exists so that your portal can find the session behind the link. |
| `url` | What the member is given as a button. Absolute, and `https` in practice, because wallet connection libraries generally refuse to run otherwise. This is the only field the bot actually reads. |
| `expiresAt` | A timestamp string. ISO 8601 with a `Z` suffix. **Also decoded and never used.** |

**About the expiry.** The bot's reply to the member says the link expires in
fifteen minutes, in plain text, without reading `expiresAt`. If your portal
chooses a different lifetime, the member is being told something untrue. Use
fifteen minutes. That the bot requires a field it then ignores is a wart, not a
subtlety: send it anyway, because the decode is strict.

When a member already has a pending session, delete it and issue a new one, so
that a member who runs `/verify` twice does not leave two live challenges
behind them.

### `GET {base}/api/v1/verification/{discordId}?guildId={guildId}`

Asks whether the portal already has a verified account on record for this
member. Called at the start of `/verify`, so that a member who is already
verified is told so and offered a second account rather than sent round the
loop again.

| | |
|---|---|
| Path parameter | `discordId`, a decimal snowflake string |
| Query parameter | `guildId`, always sent, and you should require it |
| Headers | `X-API-Key: <secret>` |
| `200` | The member has an account. Body below. |
| `404` | The member has none. **Not an error.** The bot carries on and creates a session. |
| anything else | An error. Logged, and the member is told verification could not be checked. |

Response body on `200`:

```json
{
  "discordId": "000000000000000001",
  "walletAddress": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "balance": 1234567,
  "tier": "Silver",
  "isPublic": true
}
```

All five fields are required by the decoder, and only two of them are read.

| Field | Read? |
|-------|-------|
| `discordId` | No. The bot already knows who it asked about. |
| `walletAddress` | Yes. This is the account the bot adopts. |
| `balance` | As a starting value only, immediately replaced by a chain read when one succeeds. Unsigned integer, in the asset's **base units**, not whole tokens. |
| `tier` | No. Never. See [Your numbers are advisory](#your-numbers-are-advisory). |
| `isPublic` | No. Decoded and discarded; whether a member appears on public cards is the bot's own record. |

Omitting a field you think is unused still breaks the call, because the decode
is all or nothing.

### `DELETE {base}/api/v1/verification/{discordId}?guildId={guildId}`

Unlinks a member's account. Called when a member unlinks.

| | |
|---|---|
| Headers | `X-API-Key: <secret>` |
| Expected status | `200`. Anything else, **including `404`**, is a failure. |
| Response body | ignored |

Answer `200` when there was nothing to delete. An unlink of a member who is not
linked has already achieved what the caller wanted, and a `404` here turns a
member's request to leave into an error message.

Invalidate any session tokens and any refresh tokens you issued for that
account at the same moment. Deleting the link and leaving a live session is how
an unlinked member keeps whatever the session opened.

## What the bot exposes

The bot runs a small HTTP listener on one port, default `3001`, bound on every
interface, plain HTTP. It answers two routes and `404`s everything else.

Anything else the bot may listen on, such as an administrative interface, is on
a different port and is not part of this contract.

### `POST /webhook/verification`

The one call the portal makes, and the only route that is rate limited.

| | |
|---|---|
| Headers | `X-API-Key: <secret>`, `Content-Type: application/json` |
| Success | `200` with `{"success":true}` |

Request body:

```json
{
  "discordId": "000000000000000001",
  "guildId": "000000000000000002",
  "walletAddress": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "balance": 1234567,
  "tier": "Silver"
}
```

Those five are required; `balance` is an unsigned integer in base units.
Additional fields are ignored, so a portal may send a breakdown of direct and
pooled holdings alongside them without breaking anything.

#### Everything that happens, in order

1. **One read.** The socket is read exactly once. An empty read closes the
   connection with no response at all. See
   [The transport constraint](#the-transport-constraint).
2. **The bytes decode as UTF-8.** If they do not, what follows sees an empty
   string and the request fails at step 3.
3. **The request line parses.** A first line that cannot be split into at least
   a method and a path gets `400`.
4. **Headers are collected** up to the first empty line. Names are lowercased,
   values are trimmed. Everything after that empty line is the body.
5. **The route matches.** `GET /health` is answered here, before any rate
   limiting or authentication. `POST /webhook/verification` continues below.
   Anything else is `404` with `{"error":"Not Found"}`, and is **not** rate
   limited.
6. **Rate limit.** At most 10 requests per 60 seconds per source address, on
   this route alone. Over that is `429` with `{"error":"Too Many Requests"}`.
7. **API key.** The `x-api-key` header, compared in constant time. Missing or
   wrong is `401` with `{"error":"Unauthorized"}`. No detail about which.
8. **JSON decodes** into the five fields. Otherwise `400` with
   `{"error":"Invalid JSON"}`.
9. **The payload validates.** Otherwise `400` with `{"error":"<reason>"}`.
10. **The store is open.** In the window between the port binding and the
    boot finishing there is nowhere to put a verification yet, and the answer
    is `503` with `{"status":"starting"}`. Retry it: a `200` there would tell
    you to record a verification the bot threw away.
11. **Only then `200`**, and the work starts after the answer has been sent.

With no shared secret configured the bot is running with verification
switched off, and this route does not exist: every request to it, with a key
or without one, is `404`. An empty header and an unset secret would otherwise
compare equal, which would be an open door into somebody's roles.

Step 9 is the one worth understanding. The API key proves who sent the request,
not that the request makes sense. The bot refuses a bad payload **before** it
answers `200`, so that a portal which records a verification on a successful
callback never records one the bot threw away.

| Reason | When |
|--------|------|
| `Missing guildId` | `guildId` is the empty string |
| `Wrong guildId` | it is not the server this bot serves |
| `Invalid walletAddress` | the address does not parse as an Algorand address, checksum included |
| `Invalid discordId` | it is not between 1 and 20 ASCII digits |

The reason is echoed in the body and in the log. The payload itself is never
logged.

#### The transport constraint

The listener performs **a single `recv` of at most 8192 bytes** and never reads
that socket again. It never looks at `Content-Length`. Whatever arrived in that
one read is the whole request, and everything after the first empty line in it
is the body.

That is not a detail of an implementation you can ignore. It is the contract,
and it constrains what you may send:

- **The entire request must arrive in one read: request line, headers and body
  together, within 8192 bytes.** Headers count against the budget. Five short
  fields are a few hundred bytes, so this is generous, but it is a hard ceiling
  and not a buffer that grows.
- **Do not use `Transfer-Encoding: chunked`.** The chunk size lines land inside
  the body and the decode fails.
- **Do not send `Expect: 100-continue`.** The bot never sends `100 Continue`,
  so your client waits, the read contains headers and no body, and the decode
  fails.
- **Do not rely on connection reuse.** Every response carries
  `Connection: close` and the socket is closed after it.
- Send `Content-Length` anyway. The bot does not read it, but anything between
  you and it will.

A request truncated by any of the above comes back as `400`, and **which** `400`
is not a reliable clue: if the read cut the body you get
`{"error":"Invalid JSON"}`, if it cut a multi-byte UTF-8 sequence the whole
request decodes to nothing and you get `Bad Request`, and if no empty line
arrived at all the body index never moves and the request line itself is parsed
as JSON. All three are the same mistake. Get the transport right before
debugging anything else.

#### Retries and duplicates

The bot does no deduplication. A second delivery of the same payload re-runs
the chain read and the role assignment. That is wasteful rather than harmful:
both are idempotent in effect.

Retry on `5xx`, on a timeout and on a connection failure. Do **not** retry on
`400` or `401`. Neither will start working, and `401` in a loop is what an
attack looks like in somebody's log. Back off on `429`.

The callback is fire and forget as far as the answer goes: the bot replies
`200` and then does the work, so a `200` means the payload was accepted, not
that roles were assigned. If the chain read or the Discord call fails
afterwards, the member's roles arrive at the next sweep instead.

### `GET /health`

| | |
|---|---|
| Authentication | none |
| Rate limited | no, deliberately |
| `200` | `{"status":"ok"}`. Bound, and connected to Discord. |
| `503` | `{"status":"starting"}`. Bound, not yet connected to Discord. |

The body may carry an additional `algod` object holding the chain provider's
quota headers, and the response may carry a few provider headers of its own,
filtered so that neither a header name nor a value can inject a line break.
Ignore both unless you have a reason not to.

This route is exempt from the rate limit on purpose. Behind a reverse proxy
every request arrives from one address, so counting health polls against the
same budget as callbacks would let a monitoring system starve verification.

## What the bot does with the result

### Your numbers are advisory

On a valid callback the bot reads the account from the chain itself. One
account read gives it the token balance, every asset the account holds, and the
balance of any pool tokens. Each pool's reserves is a **further** chain read,
and which of those assets belong to a collection is a local lookup rather than
a chain read. It then works out the tier from its own ladder and assigns every
role in one Discord call.

The `balance` you send is used **only** when that chain read fails, for
instance when the bot has spent its daily request budget. The `tier` you send
is not used to assign a role at all, anywhere, ever.

This matters when implementing a portal: you do not need to know the
community's tier thresholds, and you should not try to. Send what you have and
let the bot be the single place where a balance becomes a role. If your portal
shows a tier to the member, treat it as a display value that may disagree with
Discord for up to one sweep interval.

### One account, one member

A member may verify several accounts, and everything they hold is added up
together ([VERIFY-2.a](../hi/verify.md)). An account, though, belongs to one
member: `AccountStore.prove` in `Store` refuses when a different member already
proved it, and the refusal changes nothing.

Enforce it on your side too, at connect time, with a `409`. Do not rely on the
bot's refusal to be the only one: the bot has already answered `200` by the
time it writes anything, so a rejected write is a log line the member never
sees. The check that produces a useful error message is yours.

## Security properties this design depends on

Five, and each is here because the obvious alternative fails in a specific way.

### The shared secret is compared in constant time

Byte by byte, accumulating differences, returning only at the end. On the
length-mismatch path the loop still runs, over the **presented** key rather
than the real one, so its cost depends on the attacker's own input and reveals
nothing about the secret.

A comparison that returns as soon as it finds a difference takes measurably
longer for a key that shares a longer prefix with the real one. Over enough
requests an attacker recovers the secret a byte at a time without ever guessing
it. The endpoint is reachable by anything that can route to it. Implement your
side the same way; most languages ship a function for this and using the
built-in one is better than writing the loop.

### The listener is bound before the gateway connects

Binding a port is how the process discovers that another copy of itself is
already running. `SO_REUSEADDR` allows a bind over a socket in `TIME_WAIT`; it
does not allow two live listeners on one port, so the second bind fails and the
second process dies.

If a second instance identified to Discord first and then died on the bind,
Discord would already have invalidated the live instance's session, because
that is how Discord resolves a duplicate identify. Under any supervisor that
restarts a failing process, that becomes a loop in which the healthy bot is
knocked offline every time the doomed one boots and neither keeps a session.
That is [RUN-7](../hi/run.md): starting a second copy by accident should be a
mistake you can undo, not one that takes the working bot down with it.

So the order is: check the portal, claim the local ports, register commands,
then identify to Discord.

The consequence for you is that **a bound socket is not evidence of health**.
That is why `/health` answers `503 {"status":"starting"}` until the gateway is
actually up, and why a deploy gate should wait for `200` rather than for the
port to open. Up means the gateway's own ready event has arrived: asking a
chat library to connect returns before the websocket is open, so that call
returning is not evidence either.

### The portal is reachable before boot completes

The bot pings the portal's health endpoint at startup and refuses to start if
it does not answer. Verification is not an optional feature: a bot running
without a portal accepts `/verify` from members and gives them nothing. Failing
at boot turns a silent product failure into a visible deployment failure, which
somebody will actually notice. That is [VERIFY-5.a](../hi/verify.md) enforced
by the software instead of by a note in a README.

The cost is a startup dependency, and it is a real one: bring the portal up
first, and if the portal is down when the bot restarts, the bot stays down.
That is the intended trade. Know that you are making it.

### Answering VERIFY-5.b at startup

The startup ping proves the portal is running. It does not prove the two halves
agree about the secret, because it carries no key. So the failure
[VERIFY-5.b](../hi/verify.md) names, learning from a member's refused command
that the secrets drifted apart, is still reachable.

A conforming portal can close it, and should. Expose one authenticated,
side-effect-free endpoint the bot can call at startup with its key, or accept
the key on the health call and report the mismatch in the body without failing
the call. Either way an operator with two different secrets learns at boot
rather than at the first `/verify`. The reference does neither.

### What a member actually proves by signing

The portal issues a **challenge** bound to the session. Make it four lines: a
fixed label, the member's chat account id, a unix timestamp and a random nonce.
Unique per session, and containing something the member cannot choose.

The member's wallet signs a **zero-amount self-payment transaction** carrying
that challenge in its note field. The transaction is never submitted. It costs
nothing, leaves no trace on chain, and exists only as a signature to check.

Verify, in this order:

1. The blob decodes and parses into a 64-byte signature and a transaction map.
2. The transaction has a sender, a receiver and a note.
3. The sender equals the address the member connected with.
4. The receiver equals the same address, so it is a self-payment.
5. The amount is zero. **An absent amount is zero**: Algorand's canonical
   encoding omits zero-valued fields, so rejecting a transaction with no `amt`
   key rejects every correctly formed proof.
6. The note equals the challenge bytes exactly.
7. The Ed25519 signature is valid over the bytes `TX` followed by the encoded
   transaction, checked against the public key that **is** the address.

Report the field failures before the signature failure. A member with the wrong
account selected in their wallet should be told that, not told their signature
is bad, because the first is something they can fix and the second is not.

Two things that bite:

- **Verify over the transaction bytes exactly as they arrived**, sliced out of
  the blob. Never re-encode the parsed fields and verify over that: a
  re-encoding that differs by one byte fails a perfectly good signature, and
  you will not find out why quickly.
- **Decoding the blob is the hard part, not the cryptography.** A popular
  mobile wallet may send standard base64 or URL-safe base64, with or without
  padding, and the payload may be a bare signed-transaction map, that map
  wrapped in a one-element array, or a map carrying an extra signer field. A
  conforming portal needs a tolerant decoder for all of those. In the reference
  that decoder is around 380 lines and every branch of it exists because a real
  wallet on a real phone sent that shape.

If the signature does not verify against the address itself, look the account
up on chain and retry against its authorising address, so a rekeyed account can
still prove ownership. Note that this costs a chain read on a failed signature,
which is worth rate limiting.

**What this proves:** at this moment, somebody holding the private key for that
address, or for the key it is rekeyed to, answered a challenge naming this
member and this session, and the session had not expired.

**What it does not prove**, and you should not let anyone believe otherwise:

- That the member still holds anything a minute later. Holdings are read fresh
  on every sweep for exactly this reason.
- That the member is the only person with that key. A shared or custodial
  wallet verifies perfectly well.
- Anything about any other address. One signature, one address.

A one-off signed message can be used instead of a transaction, with the
wallet's arbitrary-data prefix applied before verification. It is simpler and
cheaper to check, and support for it across wallets is patchier, which is why
the self-payment form is the main path.

## What a conforming portal must do

- Serve `GET /health` with `200`, cheaply, without authentication.
- Accept `POST /api/v1/verification` with the shared secret, create a session,
  and answer **`201`** with `token`, `url` and `expiresAt`.
- Generate a challenge **unique per session**, containing the member's chat
  account id, something time-varying and something random. A fixed challenge,
  or one derived only from the wallet address, is replayable.
- Expire sessions in fifteen minutes, because that is the number the bot tells
  the member.
- Accept each session's signature **once**. Mark it used, or delete it.
- Check every field of what was signed, not only that the signature verifies.
- Refuse at connect time, with `409`, an account another member already proved
  in this server.
- Call `POST /webhook/verification` with the shared secret and the five
  required fields, in one write, without chunking, and treat any status other
  than `200` as a failure of the whole verification.
- Persist the verification **only after** the bot answers `200`. Notify first,
  save second, so the two sides cannot disagree about whether a member is
  linked.
- Serve `GET` and `DELETE /api/v1/verification/{discordId}` so the bot can ask
  about a link and remove one.
- Compare the shared secret in constant time.
- Run over HTTPS. Wallet connection libraries require it, and so does the
  member's privacy.
- Refuse to start when the shared secret is unset. Never carry a default one.

## What a conforming portal must never do

- **Never ask for, accept, store or transmit a private key, a mnemonic or a
  seed phrase.** No step in this contract needs one. A portal that asks for one
  is indistinguishable from a phishing page, and members are right to treat it
  as one. This is the whole of [VERIFY-1](../hi/verify.md) and there is no
  version of this product that survives getting it wrong.
- **Never have a mode in which a fixed string is accepted as proof.** See
  below. This one has a section of its own because the reference has one.
- **Never report a verification for an address that did not sign.** Not from a
  form field, not from a query parameter, not from whatever a wallet extension
  claims is connected with no signature behind it. The address in the callback
  is the address whose key produced the signature you just checked, or the
  callback does not go.
- Never accept a signature over a challenge you did not issue for that session.
- Never accept the same signature twice.
- Never send the callback before the signature has verified. There is no
  provisional state worth the risk.
- **Never save the verification when the callback did not go.** A portal with
  no callback URL configured, or one that swallows a delivery failure, records
  a member as verified in a server whose bot has never heard of them. Failing
  loudly is the correct behaviour.
- Never submit the signed transaction to the network. It is proof, not a
  payment, and submitting it costs the member a fee for nothing.
- Never log the signature, the full callback body, or the secret. Log the
  session token and the outcome.
- Never trust the server id from the member's browser. It comes from the bot
  when the session is created, and the bot checks it again on the callback.
- Never reuse one secret across deployments. One bot, one portal, one secret.
  [HOST-6](../hi/host.md) is that an instance is one community's alone, and a
  shared secret is the shortest path to breaking it.

### The test mode bypass, said plainly

The reference portal has a mode in which the literal string `test-transaction`,
posted in place of a signed transaction, is accepted as proof that the member
owns the connected address. A second literal does the same for the legacy
signed-message path. It is behind an environment flag, it is off by default and
it is documented.

**It is still an identity bypass behind a flag, and a conforming portal must
not have one.** With that flag on, anyone who can reach the submit endpoint can
claim any address they can type, take the roles that address earns, and be paid
whatever a holder of that address is owed. There is no signature and therefore
nothing to get wrong: the check is skipped, not weakened.

[BUILD-3](../hi/build.md) exists because of exactly this shape. A build that
cannot spend must be unmistakably different from one that can, and no setting
that only points somewhere else or quietens the output may be mistaken for one
that changes what the software will do with money. A flag whose name says
"test" and whose effect is "accept anyone's claim to anyone's wallet" is the
worst case of that: it reads as a convenience and it is an authentication
switch. The moment a project has to carry a note somewhere saying that some
particular flag is not a money switch, the software has already failed to say
so itself, and the note is load-bearing only until somebody new does not read
it.

If you need to test without a wallet, the honest shapes are:

- A **fake signer** in your own test suite that produces a real signature over
  the real challenge with a throwaway key. The verification path runs
  unchanged, which is the point: a test that skips the code under test is not a
  test of it.
- A **development-only build** that is a different artifact, announces at every
  startup that it cannot be trusted with an identity, and cannot be configured
  into existence at runtime by setting a variable in production
  ([BUILD-3.b](../hi/build.md)).

Neither of these is a runtime flag on the production binary, and that is the
distinction that matters.

## Where the reference departs from this contract

The working implementation is not fully conforming. These are its departures,
listed so that nobody reads this document as a description of it.

| Departure | Why it matters |
|-----------|----------------|
| The portal compares the `X-API-Key` with an ordinary string equality, not in constant time. Only the bot's side is constant time. | The timing side channel this contract calls out is open on the portal, which is the side reachable from the public internet. |
| The bot uses **two** variables for the one secret: one for the callback it receives and one for the calls it makes, the second falling back to the first. Only the first is required at boot, and the outbound one falls back to a built-in default when unset. | An operator who sets only the required one boots cleanly and sends a hard-coded default secret to their portal on every call. Every `/verify` fails with a `401` nobody is looking at. This is the failure [VERIFY-5.b](../hi/verify.md) names, and it is also [ADOPT-6](../hi/adopt.md): nothing should fall back to a value somebody else chose. |
| The bot **moves** an account already proved by another member to the new member, rather than refusing. | One account, one member is enforced only by the portal's `409` at connect time. `Store` in this repository refuses, which is the behaviour to keep. |
| The portal skips the callback entirely when no callback URL is configured, and then saves the verification anyway. | The member is verified on the portal and unknown to the bot. Save only after a `200`. |
| The `503` from `/health` is sent with the reason phrase `Unknown`, because 503 is missing from the status-text table. | Harmless to a client that reads the code; confusing in a log. |
| A malformed request line is answered with the body `Bad Request` under `Content-Type: application/json`. | A portal parsing the error body as JSON gets a parse failure on top of the original one. |
| The portal has the test mode bypass described above. | See [The test mode bypass, said plainly](#the-test-mode-bypass-said-plainly). |
| The bot requires `token` and `expiresAt` in the create response and then uses neither. | Send them anyway. The decode is strict. |

## Failure modes worth testing before you go live

| Symptom | Usual cause |
|---------|-------------|
| The bot exits at boot saying the portal is not reachable | The portal URL does not resolve from inside the bot's container or network namespace, or the health endpoint is behind authentication. |
| The member signs, the portal shows success, no role appears | The two copies of the secret differ and the callback is getting `401`. Check the bot's log for the rejection, and check that the bot is sending the secret you think it is. |
| Every `/verify` fails immediately, and the portal's log shows `401` | Same cause, other direction. The outbound secret is not the one you set. |
| The callback returns `400 Wrong guildId` | The portal is sending the server id from a stale session, or one portal serves two Discord servers and this bot serves one. |
| The callback returns `400 Invalid JSON` on a body that is valid JSON | The request exceeded the single read, or was sent chunked, or waited on `100 Continue`. |
| The callback returns `Bad Request` with no JSON | The read was cut mid-character. Same cause as the row above. |
| The callback returns `429` under ordinary load | Everything arrives from one proxy address. Raise the limit, or spread retries out. |
| `/verify` reports an error although the portal created the session | The portal answered `200` instead of `201`, or omitted one of the three response fields. |
| A member's roles move for some members and not others | Not a portal problem. A bot cannot grant a Discord role positioned above its own. |
