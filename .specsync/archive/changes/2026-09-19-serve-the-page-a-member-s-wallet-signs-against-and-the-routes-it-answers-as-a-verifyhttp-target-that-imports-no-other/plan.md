---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: plan
---

# Plan

1. The value types first: request, response, route, limits. Pure, no socket.
2. The page and its script, as constants, with the headers set on every
   response.
3. The rate limiter, keyed so that a reverse proxy collapsing every client to
   one address cannot lock the portal out for everybody.
4. The service: routing, and the handoff to `Verify`.
5. The listener last, because it is the only part that cannot be tested
   without a socket, and everything above it can.
6. The shape test, written to fail against a deliberately added import before
   being trusted.

## Deliberately not in this change

Assembling the target into the executable. `BotMain` does not link it, the
program binds no listener of its, and `/verify` stays unregistered. The chat
surface landed before its wiring in #27 for the same reason: a page that
serves a signing flow is easier to review when it cannot yet be reached, and
the wiring change is then about wiring rather than about both at once.