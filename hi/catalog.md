---
hi: 1
families: [CATALOG]
---

# Catalog

## Intent

Deciding which Discord role a tier grants is a community decision, made by whoever runs the community, usually at the moment they think of it. If that decision lives in a file on a server, a role change is a deploy, and a deploy needs somebody who knows how to do one. Most communities do not have that person, and the ones that do should not have to interrupt them to rename a rung.

So the catalog is a page, and the sign-in is a wallet. Not a password, because a password is a thing people share and then nobody knows who did what. A wallet proves who is asking, and every change is written down against the one that made it.

Which wallets may sign in is the operator's list and nothing else. A bot that arrives with somebody already on that list has handed a stranger permanent authority over a community's roles, and the stranger never had to ask for it. An empty list closes the page; it does not quietly open it to whoever the code was written for.

The thing the catalog must never do is let someone build a rule that silently does nothing. A role the bot cannot grant, a role sitting above the bot in the list, a role somebody deleted in Discord yesterday: all of those look fine in a database and grant nobody anything. Better to refuse the mapping than to accept it and let a tier stop working with nobody noticing for a month.

And the page belongs to the community looking at it. Its name, its colours, and the message a wallet is asked to sign are all a statement of whose bot this is, because an admin who signs a message naming somebody they have never heard of is an admin learning not to read them.

## Criteria

- **CATALOG-1**  I can change which Discord role a tier grants without editing a file on the server
  - **CATALOG-1.a**  A change I make takes effect on the next sweep without restarting anything
- **CATALOG-2**  I sign in with the wallet that proves I run this, not a password that can be passed around
- **CATALOG-3**  I can see which rules point at a role Discord will not let the bot grant, before I rely on one
- **CATALOG-4**  I cannot delete a role while something still depends on it
- **CATALOG-5**  Every change is recorded against the wallet that made it
- **CATALOG-6**  I can see what the server is actually running without opening a shell on it
  - **CATALOG-6.a**  Looking at the settings never shows me a secret
- **CATALOG-7**  The wallets that can sign in are the ones I named, and nobody is on that list when I install it
  - **CATALOG-7.a**  I can take any wallet off the list, including the first one I put on it
  - **CATALOG-7.b**  With nobody on the list the page lets nobody in, rather than falling back to some other wallet
- **CATALOG-8**  Every rule that decides a role is editable here, not only the holder ladder: a collection, a count rung, a pool share
  - **CATALOG-8.a**  A mapping I set by hand survives a restart; nothing re-seeds over the top of it
- **CATALOG-9**  The page my admins open is my community's, down to the message their wallet asks them to sign
  - **CATALOG-9.a**  Nothing on it names or advertises whoever wrote the bot
- **CATALOG-10**  When a setting I typed on the page and a setting in the environment disagree, the page tells me which one the bot is using
