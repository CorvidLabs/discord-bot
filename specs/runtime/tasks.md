---
spec: runtime.spec.md
---

## Tasks

- [x] Add a `Runtime` target depending on `Gating`, `Chain` and `Store` and on
      nothing else, and a `BotMain` executable depending on `Runtime` and
      `StoreSQLite`.
- [x] Add exactly one executable product, `bot`, and no library product for
      `Runtime`.
- [x] Add no package dependency, and declare the chat seam over Foundation
      types with a role and a member both `String`.
- [x] Read the process environment once, in the executable, and nowhere else.
- [x] Describe every variable this build reads in one catalogue, taking each
      name from the constant that owns it.
- [x] Record every key a loader asked for, so an undescribed variable stops the
      boot and an unread owned variable is reported.
- [x] Refuse a variable inside a prefix reserved for a part this build has not
      got, naming it.
- [x] Run the eight gates in a fixed order, and record which ran so a test can
      assert the order that happened.
- [x] Return `ListenerBound` from a completed bind, with an internal
      initialiser, and require one on the chat seam's connect call.
- [x] Open the store before any socket, refuse a relative `STORE_PATH`, and
      stop a second instance with 69.
- [x] Restore the day's request count into one shared governor before the first
      request, and refuse when a count on record cannot be read.
- [x] Classify the chain gate's answers, asking whether a 403 is the provider's
      own quota refusal before treating it as a credential.
- [x] Back the chain retry off from five seconds to a fifteen minute ceiling
      through the same governor.
- [x] Answer `GET /health` and nothing else, from state already in memory, with
      the body `Chain` renders.
- [x] Never set the socket option that would let a duplicate bind, and say why
      in a comment.
- [x] Write the report at every start, including one that refuses, and let no
      setting suppress it.
- [x] Keep every secret out of the report by construction, and filter refusals
      on their way to standard error.
- [x] Take the spending capability as a parameter, with no path from the
      settings to it.
- [x] Parse the four verbs by hand and map every outcome to 0, 64, 69, 70 or
      78.
- [x] Stop the listener, close the store and exit 0 on a signal; exit at once
      on a second.
- [x] Write each section of the report as the gate that produced it finishes,
      so a start killed part way through has still printed what it got to.
- [x] Build the health components from the configuration, so a check the
      operator turned off contributes no component rather than one marked
      reached by a gate that asked nothing.
- [x] Probe the provider proof once at the start and thereafter only when an
      answer has been given, never on a timer and never on the request path.
- [x] Read a request on a thread of the connection's own, so one client that
      sends nothing costs one connection rather than the endpoint.
- [x] Carry a reason out of the accept loop, stop the instance on it, and
      ignore `SIGPIPE` before the process writes anything.
- [x] Treat a variable set to nothing as unset in the audit, the way every
      loader in the package already does.
- [x] Mark the first rung of the ladder required in the catalogue, because the
      loaders refuse without it.
- [x] Name `bot check` in a refusal that blames a variable, and say what the
      day's request count was restored to.
- [ ] Say in the report, when the node is not probed at start, what a sweep
      will do about it. It says the check is off and why; it does not yet say
      what the first sweep will cost.
- [ ] Hold the report as a value a surface could read later. It is lines on
      standard output today, and nobody has decided whether a machine-readable
      form is wanted.
