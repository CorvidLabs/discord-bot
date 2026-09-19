---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: docs
---

# Documentation

Three documents change, and the disclosure is the one that matters.

`docs/WHAT-IT-TALKS-TO.md` is the file a stranger reads before installing
anything, so a wrong row in it is worse than a missing one. Adding a target
that binds a socket and serves a page to a wallet falsifies three of its
claims: the target count, the number of files that call `socket(`, and the row
that said this package does not serve a page. All three change here rather
than in a follow-up, and the socket row now names all three files and says
which one the program actually binds.

`README.md` gains a `VerifyHTTP` row and its verification bullet stops saying
the page is missing.

`docs/VERIFICATION.md` stops saying there is no listener. Both halves now
exist; what is missing is the link, and it says that instead.