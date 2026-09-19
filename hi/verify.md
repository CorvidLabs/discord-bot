---
hi: 1
families: [VERIFY]
---

# Verify

## Intent

Holding the token should be enough. Nobody should have to ask a human to be let in, and nobody should ever be asked for a key or a seed phrase to prove what they hold: the whole point of a wallet is that you can prove ownership without surrendering it.

This is also the one moment where a stranger decides whether the whole thing is trustworthy. If it feels like a phishing flow, we have lost them, and we should have. So: one signature, nothing custodial, and if they walk away mid-way nothing about them has changed.

The stranger is now deciding about a community somebody else runs. That changes who is being trusted and it changes what a mistake costs. A member proving a wallet in one server has told that server something, and nowhere else, ever. And the person running the server is the one who has to be able to stand verification up at all: if it takes a second piece they must run, they need to know that before their members do, and they must never be left signing members in against a placeholder secret that looked fine at startup.

Before the signature there is a decision, and it is being made about a server run by somebody the member has never met. What will be kept about them, who is keeping it, and which of it the rest of the room will see are things to read before signing rather than discover afterwards.

Unlinking is the small version of leaving. The larger one is walking away from the server, or asking outright to be forgotten, and that has to take everything with it rather than the wallet alone: what was cached about what they hold, what the games remember of them, the timezone they typed in once. The one exception is the record of money that actually moved, which cannot be unwritten without breaking the count it feeds, and even that should name a person no more than it has to.

## Criteria

- **VERIFY-1**  I can prove a wallet is mine without handing anyone a key
- **VERIFY-2**  I only have to do this once and it remembers me
  - **VERIFY-2.a**  If I link a second wallet, everything I hold is counted together
- **VERIFY-3**  If I want out, I can unlink and stop being tracked
- **VERIFY-4**  What I proved in one community stays in that community and tells no other one anything about me
- **VERIFY-5**  I can offer verification in my own server without asking my members to trust anybody but me
  - **VERIFY-5.a**  If proving a wallet needs a second piece I have to run, I find that out from the README rather than from a member's first failed attempt
  - **VERIFY-5.b**  I learn at startup that the two halves disagree about the shared secret, instead of learning it from a member whose command refused
- **VERIFY-6**  Before I sign anything I can read what this server's bot will keep about me, who runs it, and which of it other members will see
- **VERIFY-7**  If I leave the server, or ask to be forgotten, everything kept about me goes: my wallets, what was cached about what I hold, my record in the games, the timezone I saved
  - **VERIFY-7.a**  I can see everything held about me before I decide, so it is a forgetting I can check rather than one I have to believe
  - **VERIFY-7.b**  Whatever the record of money moved has to keep names me no more than it has to

## Retired

- **VERIFY-1.a**  if I change my mind halfway through, nothing about my account has changed
        retired: folded into VERIFY-1: proving ownership without surrendering it already implies abandoning costs nothing
