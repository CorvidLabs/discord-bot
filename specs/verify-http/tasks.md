---
spec: verify-http.spec.md
---

## Tasks

- [x] Serve a page a member's wallet signs against, as a static asset with no
      build step, no bundler and no resource bundle that can be missing.
- [x] Take the signed blob on a route of its own and hand it to the
      coordinator, adding no check of its own.
- [x] Carry the session id to the page in a fragment, and refuse any request
      that carries a query string at all.
- [x] Put `Referrer-Policy: no-referrer` on every answer, including refusals,
      and remove the fragment from the address bar in the page's first lines.
- [x] Name the chat account the session belongs to, with the warning beside
      it, and refuse rather than serve a page that cannot name it.
- [x] Write the name as a text node, never as markup, and interpolate nothing
      into the page.
- [x] Rate limit every route per source, and every route carrying a session
      id per session as well, keyed by a handle rather than by the id.
- [x] Refuse with a sentence, a non-reversible handle and whether trying
      again could help, and never with the session id.
- [x] Bind the address to the session before asking whether another member
      holds it.
- [x] Take the one authorising key retry, from the host's own read and
      nowhere else, and let the refusal stand when there is no reader.
- [x] Hand a checked proof to the host, tell the member to confirm where they
      started, and say plainly when it could not be held.
- [x] Bind a socket, read a request whose body arrives after its headers, and
      give the port back on stop.
- [x] Prove, over a whole flow, that no byte written and no line logged
      carries the session id.
- [x] Refuse a request carrying a query string before any budget is spent
      on it, and size the per-source budgets for an instance rather than
      for a member, because behind a proxy they are the same number.
- [x] Let the host say it could not tell whether an address is claimed, and
      refuse rather than read that as "nobody holds it"; ask again before a
      checked proof is handed over.
- [x] Bound a peer's whole request rather than one read of it, bound how
      many connections may be being read at once, and answer a request that
      can never parse when that is known.

## Left for the program

- [ ] Mint a session from the chat command, deliver the link where only the
      member can see it, and rate limit the command per member.
- [ ] Hold the pending proof keyed by the subject, with an expiry of its own,
      and adopt it only on the member's confirmation.
- [ ] Name a subject from the program's own record, and answer whether an
      address is already bound to another member.
- [ ] Read an account's authorising address when the retry is offered, if the
      operator wants rekeyed accounts to be able to verify.
- [ ] Let an operator release an address bound to the wrong member, with an
      audit line naming who released it and from whom.
- [ ] Decide the bind address and port, and put a TLS terminator in front.

## Manual, and not automatable here

- [ ] A real handset, a real wallet and a real in-app browser, on both
      platforms, with an operator's own adapter loaded.
- [ ] A relayed link handed to somebody who was not told what to look for.
