---
hi: 1
families: [TRUST]
---

# Trust

## Intent

This is the moment before anything is installed. Somebody with a community and a token is reading a repository they did not write, deciding whether to put it between their members and an account that can send. They cannot run it to find out, because running it is the decision.

What they are afraid of is not a bug. It is the thing nobody disclosed: a call home that was never mentioned, an address that turns out to be somebody's analytics, a secret asked for one job and used for another, a repository with nobody's name on it, so there is nobody to ask and nobody who is answerable when it goes wrong.

So everything that decision needs has to be readable from the repository itself, without installing it and without taking anybody's word. Every outside service it will reach and every secret it will ask for, in one place, before the first command is run. A licence that is a file. Somebody answerable, also a file, because a maintainer named in a paragraph of a README is a maintainer who can be edited away in a fork and never missed.

The claim most worth being suspicious of is that it does not phone home, because that is the one that costs nothing to say. It has to be checkable instead of asserted: the list of what it talks to is short enough for a person to read, and a running instance can be asked what it has actually been reaching rather than only promising.

The last of it is what happens when somebody finds a way to steal from an instance that is already running. If there is no private way to say so, the finder either says nothing, which leaves every operator exposed, or says it in the open, where the people who would use it read first. And an operator who hears a fix exists needs to be able to tell, from a release, whether the version they are running still has the hole.

HOST is about somebody else running this and what they can reach. ADOPT begins once the decision is made and the settings are being written. This family is the reading somebody does before either.

## Criteria

- **TRUST-1**  Before I install it I can see, in one place, every outside service it will talk to and every secret it will ask me for
  - **TRUST-1.a**  Nothing it ships reports anything back to whoever wrote it, and that is something I can check rather than something I am told
  - **TRUST-1.b**  Something new it wants to reach is a change I can see between two versions, rather than something that appears quietly in one
- **TRUST-2**  The licence and the person answerable for this are files in the repository, not a line in a README
  - **TRUST-2.a**  I can tell whether anybody is still looking after it before I hand it my members, rather than afterwards
- **TRUST-3**  I can report a way to steal from a running instance privately, rather than in the open where the people who would use it read first
  - **TRUST-3.a**  From a release I can tell whether the version I am running still has a hole somebody found
  - **TRUST-3.b**  A fix for something that could lose money is named as one, so I can tell it apart from a release I can take next month
- **TRUST-4**  I can see what else comes with it, and a build made from this repository is made of what the repository says
  - **TRUST-4.a**  Nothing it needs arrives at startup from somewhere nobody named, so what my bot is cannot change without a version changing
