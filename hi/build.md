---
hi: 1
families: [BUILD]
---

# Build

## Intent

Somebody wants to help with this, and what they have is a laptop. No community of their own, no server full of members to experiment on, no wallet with anything in it, and nothing running anywhere that can prove a wallet belongs to whoever is holding it.

The first hour decides whether they stay. If the first hour goes on registering an application, collecting keys and waiting for somebody who has to trust them first, then the only people who can fix a typo are the people who already run it, and the project has quietly made itself into a thing with one maintainer.

So absent has to be a state the software understands. Not configured is not the same as broken: the parts a contributor has no keys for should say plainly that they are switched off and let everything else run, and the tests should need nothing at all, not a network, not a signing key, not a database somebody had to create first.

The other half is the opposite fear, and it is about money. A contributor is the person most likely to have this pointed at something real by accident, because they are the one running it in ten different shapes in an afternoon, half of them with settings copied from a file they did not read. So whether a build can move money has to be loud, and it has to be the software saying it. A setting that only quietens the output, or only writes somewhere else, must never be able to read as one that stops money moving. If a project has to carry a note somewhere warning that some particular flag is not a money switch, the software has already failed to say so itself, and the note is only load-bearing until somebody new does not read it.

What an operator can configure is ADOPT's. What somebody can check before they ever install this is TRUST's. This family is the person changing the code.

## Criteria

- **BUILD-1**  I can run the whole thing on my own machine with no production server, no funded wallet and nowhere live to prove a wallet
  - **BUILD-1.a**  A part I have no credentials for behaves as absent and says so, rather than as broken
  - **BUILD-1.b**  I can put made-up members, wallets and holdings in front of it, so I can watch a change work without holding anything real
- **BUILD-2**  The tests run with no network, no signing key and no database I had to set up
  - **BUILD-2.a**  Nothing in them can reach a real chain, a real server or a real account, whatever is configured on my machine
  - **BUILD-2.b**  My first contribution does not begin with somebody having to trust me with a secret
- **BUILD-3**  A build that cannot spend is unmistakably different from one that can, and the software is what tells me which I am running
  - **BUILD-3.a**  No setting that only quietens the output, or only points somewhere else, can be mistaken for one that stops money moving
  - **BUILD-3.b**  A build that can sign says so every time it starts, so I never learn it from a transaction
- **BUILD-4**  I can tell which parts are built and which are only written down, before I build on one
- **BUILD-5**  A check that passes on my machine passes in the project's own checks, and one that fails names the thing to change
- **BUILD-6**  I can tell what this project will ask of a change before I write it: which want it serves, and what has to be true before it lands
