---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: research
---

# Research

## The prior art

The private bot this is ported from served the same flow from a separate
service. Two things about that shape are worth carrying and one is worth
dropping.

Carry: the page never held a key, and the signature was checked by the bot
rather than by the page. Carry: the challenge is short-lived and one-shot.

Drop: **the second service**. `docs/decisions/0001-verification-portal.md`
records the open question of whether verification should stay a separate
process at all. `Verify` landing in-process in #23 answered half of it; this
target answers the other half, and the answer is that neither half needs a
second deployment. An operator who wants one can still put this behind a
reverse proxy.

## What a page that a wallet signs against gets wrong

Three failure modes were looked for specifically, because they are the ones
that turn a verification page into a phishing surface.

1. **Markup injection through a member's own name.** A chat account name is
   attacker-controlled. Any server-side templating of it into HTML is one
   missed escape from script execution on a page whose whole job is to ask
   somebody to sign something.
2. **A third-party script on the signing page.** A wallet connector loaded
   from a CDN can change under the operator without a diff, on the one page
   where that matters most.
3. **A resource bundle that is not there.** `Bundle.module` traps rather than
   returning nil. The bot this was ported from took the process down the first
   time somebody loaded the page, on a deployment where the bundle was not
   beside the binary.

Each of the three is answered by construction below rather than by care.