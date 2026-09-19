---
spec: runtime.spec.md
---

## Requirements

Each one is answerable by looking at the tree. The criteria in brackets are
`hi/` ids and are what the requirement exists for.

### The program

1. One library target holding the composition root and one executable product
   named `bot`, so `swift run` does something (ADOPT-4, BUILD-4).
2. The executable takes `run` as its default and also `check`, `rehearse` and
   `help`. An unrecognised argument exits 64 and prints the four (ADOPT-4,
   BUILD-1).
3. `check` loads the settings, prints the report a start would, and opens no
   socket, no store file and no network connection. With nothing set it prints
   the whole catalogue marked set or unset together with the first refusal and
   exits 78 (RUN-9, RUN-9.b).
4. `rehearse` runs the role rules over members and holdings it invents,
   against the operator's own configuration, and opens nothing (BUILD-1.b,
   ADOPT-6.a).

### Settings

5. The process environment is read in one place, in the executable. The
   composition root has no way to reach it (BUILD-2, BUILD-2.a).
6. Every variable this build reads is described in the catalogue exactly once,
   with the name taken from the constant that owns it. Numbered families are
   described as families (TRUST-1, ADOPT-9).
7. A key a loader read that the catalogue does not describe stops the boot with
   70 (TRUST-1).
8. A variable inside a prefix this build owns that nothing read is reported,
   with the entry it is one edit from, and never stops the boot (ADOPT-9.a).
9. A variable inside a prefix reserved for a part this build does not have
   stops the boot with 78, naming it (RUN-9.a, SEE-1.a).

### The boot

10. The gates run in one fixed order that no setting can change: banner,
    configuration, store, budget, bind, chain, chat, loops (RUN-9.a, SEE-11).
11. Nothing can identify to a chat service before the listener has bound, and
    that is enforced by the types rather than by two statements' order
    (RUN-7, RUN-7.a, RUN-3).
12. The store's lease is taken before any socket is bound. `STORE_PATH` is
    required and must be absolute. A store another process holds stops this
    one with 69 and says the other copy keeps serving (RUN-7.a, SEE-8).
13. The day's request count is restored into one shared governor before the
    first request of the process, and an unreadable count stops the boot rather
    than granting a second day (RUN-8, RUN-8.b, RUN-10.a).
14. The chain gate refuses only on an answer that contradicts the
    configuration. Anything else leaves the component unreached, the instance
    up, and a retry backing off from five seconds to fifteen minutes through
    the same governor (ADOPT-12.a, SEE-10.a, RUN-3).
15. On `SIGINT` or `SIGTERM` the listener stops, the store closes, which
    releases the lease, and the process exits 0. A second signal exits at once
    (RUN-7.a, SEE-8). `SIGPIPE` is ignored before anything else the process
    does, so a write to a peer that has gone is an error rather than a way to
    kill the bot from one TCP exchange. A listener that dies on its own
    unwinds the same way and exits 70 (RUN-7.a).
16. Exit codes are distinct and documented: 0, 64, 69, 70, 78 (RUN-3, SEE-11).

### The endpoint

17. `GET /health` and nothing else. 200 when every enabled component has been
    reached, 503 otherwise, the same body either way, and the body is
    `Chain`'s rather than a second spelling of it (SEE-1, SEE-1.a, RUN-3).
18. A part that is off contributes no component and is listed in the startup
    report instead. An instance with nothing to wait for reads as `ok`
    (BUILD-1.a, ADOPT-10, ADOPT-10.a, SEE-10). The components are built from
    the configuration rather than from a constant, so a boot check the
    operator turned off is not a component marked reached by a gate that
    asked nothing.
19. Answering costs no chain request and still answers when the day's budget
    is spent or the governor is paused (SEE-1.b, SEE-10.a). The provider
    proof is probed once at the start and thereafter only when an answer has
    been given since the last probe, so an instance nobody checks costs one
    request for its whole life and no loop of its own spends a provider's
    quota outside the request governor's sight (TRUST-1).
20. `HEALTH_PORT` is required, `HEALTH_ADDRESS` defaults to loopback, port zero
    is accepted, and the report prints the port actually obtained (HOST-6,
    ADOPT-2).

### The report

21. A report is written at every start, including one that then refuses, and no
    setting can suppress it (ADOPT-9, BUILD-3.b, SEE-12, SEE-8). Each section
    reaches standard output as the gate that produced it finishes, so a start
    killed part way through has still printed what it got to, including
    whether it created the store.
22. It states what the build made of the settings: every rung with its
    threshold in whole tokens and in smallest units, every collection, every
    pool, the admin allowlist in full, the node's host, and the variable each
    numbered list stopped at (ADOPT-9.a, ADOPT-12.b, CATALOG-7).
23. It never contains the value of a secret, in any form, and never the path or
    query of a URL (CATALOG-6.a, TRUST-1).

### Spending

24. Whether this build can spend is a parameter of the composition and never a
    reading of the settings (BUILD-3, BUILD-3.a, HOST-7, SPEND-6.c).
25. The banner is the first line of every start and says which of the two this
    build is (BUILD-3.b, HOST-7.a).
26. The catalogue contains no variable whose effect is to stop money moving,
    and no `TEST_MODE`, `DRY_RUN` or `SAFE_MODE` exists (BUILD-3.a).

### The obligations

27. Every one of these is exercised by a test that needs no chat service, no
    chain, no wallet and no database anybody installed (BUILD-2, BUILD-2.a,
    BUILD-2.b).
28. The disclosure document says the package now listens on a socket, which
    address and port, what the answer contains, and that it can carry provider
    proof headers (TRUST-1, TRUST-1.b).
