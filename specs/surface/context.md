---
spec: surface.spec.md
---

## Key Decisions

- **Two targets rather than one.** The definition asked for a single
  `Surface` target that is the only one depending on the chat library. It is
  split into `Surface` and `SurfaceDiscord`, published as one library
  product, and the reason is that the split is then the compiler's to enforce
  rather than a reviewer's: `Surface` does not list the chat library, so an
  import of it there is a missing module. It also means the whole rule set
  builds and tests in about four seconds without the chat library's own
  graph, which is what a contributor actually runs.
- **The router answers in values, not in calls.** `SurfaceRouter.route`
  returns `[RouterAction]` and never touches a client. The acknowledgement
  contract is then an array a test compares, so "a deferred command's first
  action is a defer" is a test rather than a convention. In the original
  every handler called the client itself, and the one that forgot to defer
  left members watching a spinner.
- **The handler does not get to choose how its answer is sent.** A command's
  `AcknowledgePolicy` is on its definition, the router emits the defer before
  the handler runs, and whatever case the handler returns is coerced to what
  the policy already committed to. A handler that returns `.immediate` after
  a defer would otherwise be a Discord error and a stuck spinner.
- **`ReplyLimits` counts UTF-16 and nothing else may.**
  `GatingFormatting.clamp` counts `Character`s and says so about itself; it
  is kept for what it is good at and is explicitly not sufficient at this
  boundary. Clamping appends characters whole rather than cutting at a UTF-16
  index, because a cut index splits a surrogate pair and sends an invalid
  message rather than a shorter one.
- **`attachments` is not optional on `VisibleMessage`.** The type makes the
  mistake unrepresentable rather than documenting it. Editing a message
  replaces its attachment list, and omitting the key is how a card appears to
  freeze while the handler is working.
- **The HTTP parsing and the callback rules live in `Surface`, the socket in
  `SurfaceDiscord`.** Every rule the listener enforces, in the order it
  enforces them, is a unit test with no socket: the route table, the rate
  limit, the constant-time secret compare, and the payload validation that
  happens before `200`.
- **The chain read in the callback covers every account the member has**, not
  only the one that just signed. The original read one and summed stored
  figures for the rest; this reads them, because `MemberHoldings.fromChain`
  already says that one wallet short makes the whole member unknown, and
  passing it one reading plus some stored numbers would quietly defeat that.
- **The portal health check happens after the binds**, following the design
  rather than the sentence in `docs/VERIFICATION.md` that says it is made
  before the bot has bound anything. The binds are what protect a live copy
  of the bot from a doomed second one, and a pointless HTTP call from a
  process that is about to exit costs nobody anything. This is a departure
  and is listed as one.
- **`DisclosureSettings` is required configuration when verification is on.**
  Who runs a server and what other members can see are not facts this package
  can know, and a shipped sentence about either would be a sentence about
  somebody else's server.
- **No default for either port and no default store path.** A port is
  somebody's firewall rule and a database is a file somebody has to back up.
  The listen address does default, to loopback, because the alternative
  default is every interface on a process that may one day hold a key.
- **`JobMailbox` ships with no production caller.** The first command that
  needs it will need it under time pressure, and inheriting a tested seam is
  better than inventing a worse one then. The record is written before the
  delivery is attempted, so a report nobody could send is still readable.

## What Was Considered and Rejected

- **One `Bot` actor that builds every service and switches on a command
  name**, as the original has. A router table plus per-command handlers
  instead: the switch was eleven hundred lines and every handler took a chat
  client, which is why none of them could be tested.
- **A chat client in a handler signature.** Handlers take an
  `InteractionRequest` and return a `SurfaceReply`. Nothing they need is a
  client.
- **Cards as chat-library values.** In the original a card *was* a library
  type, so checking what a command would show meant building a gateway.
- **Closures on buttons.** A button with a closure cannot be compared, cannot
  be stored and cannot be recognised a version later.
- **Two shared secrets, one per direction.** The original has them, and an
  operator who sets one and forgets the other gets a bot that starts cleanly,
  passes its own health gate, and fails every `/verify` with a `401` nobody
  sees.
- **The `guildMessages` intent.** Reading every message in a server is a
  permission this bot has no use for. It is also how a feature nobody asked
  for got into the original.
- **A presence naming a token.** This package does not know what the token
  is called until an operator says so, and a shipped one would be somebody
  else's.
- **Vendoring an HTTP server.** The listener is the platform's own sockets
  and about two hundred and fifty lines, which adds no entry to
  `Package.resolved`, and the parsing it does is in a target with no sockets
  in it.

## Departures From the Reference

- The callback reads every account the member has, rather than one.
- The portal health check sits after the port binds rather than before them.
- `/verify` does not adopt an account the portal already has on record. The
  original synced one on the spot; here the callback is the only path that
  proves an account, so there is one path to test and one place a role
  decision is made.
- There is one shared secret rather than two.
- There is no `TEST_MODE`. A build that cannot spend is a build with no key.
