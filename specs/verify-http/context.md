---
spec: verify-http.spec.md
---

## Key Decisions

### Four routes, not two

Two of them are the obligation: a page, and somewhere to post the signed
blob. The other four follow from where the session id travels.

The id reaches the page in the **fragment** of the link, and a browser never
sends a fragment to a server. So the server cannot know, on the page load,
which session it is serving, and cannot render the member's name into the
page. The page has to ask, with the id in a request body, which is the card
route. And the coordinator records a connected address as a step of its own,
before anybody signs, which is the whole value of naming a wallet up front:
the mismatch costs the member a retyped command rather than a signature. That
is the connect route.

The script and the stylesheet are routes rather than text inside the page so
that the content security policy can name no source but this origin. An
inline script needs `unsafe-inline`, and `unsafe-inline` is every injected
script anybody ever manages to land on the page.

### A query string is refused, not ignored

The health endpoint in this package drops the query and matches the route, so
a monitoring tool's cache buster works. This surface does the opposite, and
the difference is what travels: the one thing that must never be in a query
string is the session id, and a surface that serves a request carrying a
query has already taught somebody a shape in which it could be. The cost is
that a link with a tracking parameter appended would be refused. That is a
sentence a member can act on, and it is the smaller failure.

### A second request parser

`Surface` already has one, with the same job. Sharing it would mean this
target depending on `Surface`, and through it on `Store`, `Chain` and
`Gating`, which is exactly the reach `Verify` gave up in order to be able to
say it reads nothing.

They also answer different questions. The callback listener performs a single
read and never looks at `Content-Length`, which is the documented contract a
portal builds against and is right for one cooperating service. This one
talks to browsers, which are free to put the headers in one segment and the
body in the next, so it reads until the declared body has arrived. A surface
that loses one submission in twenty is a surface nobody can debug.

### Its own port, and its own listener

The health endpoint must answer while everything else is broken, and it is
deliberately not rate limited. This surface talks to browsers and is rate
limited on every route. Sharing a port would mean one of those properties
bending to the other.

The listener is the health endpoint's shape: a hand written accept loop over
the platform's sockets, woken by a pipe, with the blocking reads on a
dispatch queue rather than on the cooperative pool. An async networking
package for four routes would be a new pin and a new thing a reader of
TRUST-1 has to weigh.

### The name on the page, and what it does not defend

It answers a **relayed prompt**: somebody runs the command themselves and
sends the link to a member. The member is then on the operator's real page,
on the real origin, so the page cannot be made to lie about whose session it
is, and the name is the only form of this defence a first-time verifier can
use.

It does not defend a **counterfeit** page, which is a different attack with a
different answer. Carrying the name inside the signed bytes would, and it
would also put an identifier that came from a person below the chat
boundary, which is a line this package does not cross. What is left over is a
member who does not read the warning. That is real and it is largely user
error, and saying so is not the same as dismissing it.

### No wallet connector

Vendoring one would mean several hundred kilobytes of third party browser
code in a repository whose answer to "should I install this" is that you can
read what it depends on. So there is one documented extension point on
`window` and a fallback that works with no adapter at all: type the address,
paste the signed transaction. The fallback is honest and it is clumsy on a
phone, which is why it is written down as something an operator still has to
finish rather than presented as the flow.

### The per-source limit is the whole community's

Behind a reverse proxy every request arrives from the proxy, so one source is
every member at once. A forwarded-for header would get around that and is not
read, because a header a client sends is a value a client chooses and
honouring it turns the limit into a field an attacker fills in.

So the per-source numbers are sized for an instance rather than for a person.
The first draft read them as one member's allowance, which behind the
deployment this is written for meant ten page loads a minute and four
verifications a minute for the whole server, and a refusal saying "that is
faster than this page is answered" to a member who had not asked for
anything yet. The bound that holds a member is per session, against a handle
rather than the id; the page, the script and the stylesheet have no such
bound and cannot, because the id is in the fragment and the server never
sees it.

Two things follow from the same fact. A request this surface will not serve
whatever budget is left is counted against nobody: an unknown path, and a
request carrying a query string. Charging those would let a scanner, or
anybody appending a tracking parameter to the link, spend a budget that is
everybody's.

### A peer that does not talk is not a rate limit's problem

All three limiters are asked in `respond`, which is to say once a whole
request has been read. A peer that connects and says nothing, or sends one
byte every four seconds, never reaches them. Two bounds in the listener
answer that instead: the peer budget is the whole request's rather than one
read's, because `SO_RCVTIMEO` bounds a single `recv` and every byte restarts
it; and how many connections may be being read at once is counted before a
connection is handed to the queue, because a block queued on a concurrent
queue whose workers are all blocked never runs. Over the bound a connection
is closed at accept, which is worse for that peer and better for the member
behind it than a descriptor held open unanswered.

### Refusing rather than rendering an unnamed page

A live session whose chat account cannot be named is refused. The
accommodating version renders the page with an empty name when the chat
service is unreachable, and that page has the relayed-prompt mitigation
switched off with nothing on it saying so.

## Open Questions

- **Should the page carry the challenge text at all?** It does today, because
  the member's wallet will show it and an adapter needs the bytes. It is not
  a secret, and whoever can ask for it already holds the bearer credential.
  If a future adapter builds the note itself from the code and the subject,
  this could go.
- **Should `isServing` feed the health answer?** The program can ask, and
  nothing here decides for it. A listener that has died leaves a bot that
  looks healthy and cannot verify anybody, which is an argument for wiring
  it, and it is the program's argument to have.
- **One port or a path prefix on the operator's terminator?** The routes are
  fixed under `/verify`, so an operator can put this behind a path on a host
  they already serve. Nothing here depends on being at the root.
