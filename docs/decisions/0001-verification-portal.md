# 0001. How a member proves an account is theirs

- **Status:** Proposed. Not decided, and not the author's to decide.
- **Date:** 2026-09-18
- **Affects:** [VERIFY](../../hi/verify.md), [ADOPT](../../hi/adopt.md),
  [HOST](../../hi/host.md), [BUILD](../../hi/build.md)
- **Contract:** [`docs/VERIFICATION.md`](../VERIFICATION.md)

## The problem

The thing this product exists for is that holding something on chain means
something in a server, and the first step of that is a member proving an
account is theirs without handing anybody a key. Everything else in the
repository is downstream of that one moment: `Gating` decides nothing until a
member has a proved account, `Reserve` pays nobody, and the six libraries add
up to a thing that cannot do its job. In the implementation this was read out
of, that proof happens in a **separate web application, in a separate private
repository**, which the bot hands the member off to and then hears back from
over a webhook. The bot refuses to start if that application is not answering.
So a stranger who clones this repository next week and follows the README
cannot verify a single member, and the feature the product exists for returns
an error. That is a direct failure of [ADOPT-4](../../hi/adopt.md), getting
from a clean machine to a running bot by following the README alone, and of
[VERIFY-5](../../hi/verify.md), offering verification in your own server
without asking your members to trust anybody but you. Nothing in this
repository currently says any of that out loud, which is separately a failure
of [VERIFY-5.a](../../hi/verify.md).

## What is actually needed

Worth separating before costing anything, because the four options differ far
less than they look.

A wallet will not talk to a Discord bot. Wallets talk to browsers, over
WalletConnect and deep links. So proving an account needs exactly two things:

1. **A page a wallet will talk to.** This is the hard part. It means browser
   JavaScript, a wallet connection library per wallet family, and a build step.
   It is hard because those libraries change on their own schedule and a break
   in one of them is a break in verification.
2. **Checking an Ed25519 signature.** This is not hard. It is about forty
   lines against the platform's crypto library, and the implementation this was
   read out of **already does it in process**, with no web application
   involved, to sign administrators in. What is genuinely fiddly next to it is
   decoding what a mobile wallet actually posts, which took a tolerant msgpack
   decoder of around 380 lines because one popular wallet sends four different
   shapes depending on the phone.

Neither of those needs a second service. A second service is a choice about
where the page is served from, not about what has to exist.

## The options

### A. Publish the contract. Operators bring their own portal.

Write down every endpoint, every status code, every validation and every
security property, and let an operator point the bot at whatever satisfies it.
That document now exists: [`VERIFICATION.md`](../VERIFICATION.md).

- **To build:** done. No code.
- **Commits us to:** keeping one document true as the bot's side changes. One
  file, in the gate. The cheapest commitment on this page by a wide margin.
- **The stranger next week:** still stuck. They now know precisely what they
  are missing, which is a real improvement over finding out from a member, and
  they still have to find or write a web application and deploy it with TLS
  before a single person can verify. [ADOPT-4](../../hi/adopt.md) fails.
  [HOST-1](../../hi/host.md), having this run for your server without operating
  a server, fails twice over.
- **Independence:** total, and vacuous. There is nothing to depend on because
  there is nothing.

This option is not really in competition with the others. Every other option
needs this document too, because even a page served by the bot itself has to
do everything in it. The question is only whether this is *all* we do.

### B. Ship a minimal reference portal in this repository.

A second executable target in this repository: a small HTTP server, a session
store, the challenge, the signature check, and a page.

- **To build:** the biggest piece of new work on this page. An HTTP server
  where today there is none, which means either writing one or taking the
  first dependency with a real graph behind it. Session storage, which `Store`
  can already hold. The signature check, which is small. The blob decoder,
  which is not, and which has to be ported and then re-tested against real
  wallets on real phones rather than against fixtures we wrote. And the page,
  with a JavaScript bundler in a Swift repository and a release process that
  now has two artifacts in two languages.
- **Commits us to:** the wallet libraries, forever, at their cadence and not
  ours. This is the recurring cost and it is the one that matters. Everything
  else here is written once.
- **The stranger next week:** it works, and they deploy two processes and
  terminate TLS on one of them.
- **Independence:** total. Everything they run comes from one clone.

### C. Open source the existing portal.

- **To build:** an audit, not a feature. The existing service is not a
  verification portal. It is an identity provider that also does verification:
  authorization codes, JWT signing with key rotation and a published key set,
  refresh tokens, email verification, password reset, a users table, a
  redirect allowlist, an asset registry with a scheduled job, and the wallet
  flow. Publishing it means scrubbing all of that of one project's assets,
  addresses and copy the way this repository was scrubbed, and removing the
  test mode bypass described in the contract, which is an identity bypass
  behind a flag.
- **Commits us to:** a second public repository with its own gate, its own
  releases and its own security reporting surface, in a different shape from
  this one, of which verification is a minority. Password reset and email
  delivery are things people report vulnerabilities about, and
  [TRUST-3](../../hi/trust.md) says we answer those privately and promptly.
  That is a standing obligation taken on for code most operators will not want.
- **The stranger next week:** better than A. They deploy two services and a
  database and inherit an identity provider they did not ask for, most of
  which they must then configure or disable.
- **Independence:** they depend on two artifacts of ours instead of one, and on
  our willingness to keep maintaining the larger one.

### D. No portal at all

Worth taking seriously rather than dismissing, because the second thing
verification needs is already done in process and the first thing is not a
service, it is a page. Three shapes:

**D1. The bot serves the page itself.** One process. The bot binds an HTTP
listener anyway, for its own health endpoint. Put the verification page and
the submit endpoint on it.

- **To build:** the same page and the same decoder as B, and **none** of the
  protocol. No shared secret, no `X-API-Key`, no webhook, no single fixed-size
  read, no `201`-not-`200`, no boot-order dependency on a second service, and
  no way for the two halves to disagree about anything, because there is one
  half. Read the contract document and notice how much of it is about the
  seam: authentication, the transport constraint, the retry rules, three of
  the five security properties, four of the eight departures, and six of the
  nine failure modes. All of that is the cost of the split, and it is paid by
  every operator, forever, in order to keep two processes agreeing about a
  string.
- **Commits us to:** the wallet libraries, exactly as B does. That cost does
  not move.
- **The stranger next week:** one clone, one build, one process, one port,
  verification works. [ADOPT-4](../../hi/adopt.md) is answerable for the first
  time.
- **Independence:** total, and the cheapest to host, which is what would make
  [HOST-1](../../hi/host.md) offerable later.
- **Against it:** a bot that serves browser JavaScript is a larger attack
  surface than a bot that does not, and the page is now reachable on the same
  process that holds a signing key for payouts. That is a real argument and it
  is answered by process boundaries in the deployment, not by a second
  repository. Note also that the contract still gets published, because an
  operator who wants the page somewhere else should be able to have it.

**D2. Prove it on chain, with no browser.** The bot gives the member a code.
The member sends a zero-amount transaction to a stated address with the code
in the note, from any wallet, on their phone, with no page involved. The bot
finds the transaction and the sender is the proof.

- **Genuinely no web application**, and it works from every wallet without a
  connection library, which kills the recurring cost that B and D1 both carry.
- **It needs an indexer.** `Chain` reads an algod node, and algod cannot look
  up an arbitrary past transaction by note or by id. An indexer is a new host,
  possibly a new secret, a new row in
  [`WHAT-IT-TALKS-TO.md`](../WHAT-IT-TALKS-TO.md), a new quota to budget
  against, and a new provider to depend on.
- **It costs the member a fee**, and requires them to hold ALGO. Small, and
  not nothing, and it breaks the promise that walking away mid-way costs them
  nothing.
- **It is slow**, by the length of a round plus whatever the indexer lags, and
  the member watches a spinner.
- Worth keeping as a **fallback path** for a member whose wallet will not
  connect, which is a real and recurring support problem, rather than as the
  main road.

**D3. Paste a signature into a Discord modal.** Zero infrastructure and no
page. Rejected: a normal holder has no way to sign an arbitrary message without
a command line or a website that asks them to do something that looks exactly
like phishing. [VERIFY](../../hi/verify.md) says that if it feels like a
phishing flow we have lost them and we should have. This is that.

## Recommendation

**Publish the contract now, and build D1: the bot serves the page.** Keep the
contract as the interface D1 implements, so that an operator who wants the page
elsewhere can substitute their own, and so that the existing separate
deployment keeps working unchanged against a bot built from this repository.

Not C, unless the audit is wanted for its own sake. It is the largest standing
obligation for the least benefit to an operator, and it publishes an identity
provider in order to ship forty lines of signature checking.

Not B as distinct from D1. If we are writing the page anyway, putting it behind
a second process, a shared secret and a webhook adds no capability and adds
most of the contract document.

D2 afterwards, as the fallback for a member whose wallet will not connect, and
only once there is a reason to add an indexer.

## The one fact that decides it

**Verification needs a browser page and about forty lines of Ed25519 checking,
and the implementation this contract was read out of already does the second
one in process, with no web application, to sign administrators in.**

So a separate service buys no capability. It buys a second thing to deploy, a
shared secret that can drift, a boot order that takes the bot down when the
other half is down, a webhook with a fixed-size read, and a status code that
has to be `201`. Every one of those is a documented failure mode in
[`VERIFICATION.md`](../VERIFICATION.md), and every one of them exists only
because the page is served by something other than the bot.

The page has to be written either way. Where it is served from is the whole
decision.

## What would change this

- **If the page turns out to need a hostname and a certificate the bot cannot
  have.** Wallet connection generally requires a secure context, and if an
  operator's bot has no public hostname the page has to live somewhere that
  does. If that is the common case rather than the exception, D1 collapses into
  B and B is the answer.
- **If someone wants to run one portal for several communities.** Nothing in
  [HOST-6](../../hi/host.md) permits sharing a portal across instances, so this
  is likelier a reason to say no than a reason to change the decision, but it
  should be said out loud rather than discovered.
- **If the audit for C is wanted anyway** for a reason unrelated to this bot.
  Then C is nearly free and this decision is only about which page the bot
  points at.
