---
hi: 1
families: [GIFT]
---

# Gift

## Intent

Giving something away should feel like a gift, not an airdrop. The person is named, the thing is shown, and it is theirs to come and take.

The hard case is somebody who is not set up to receive it yet. The tempting thing is to skip them and move on, and that is exactly wrong: it turns a present into a near-miss they find out about later. It waits, and it tells them how to get ready. Equally: a thing set aside for one person cannot be taken by whoever clicks fastest, and a prize draw has to be something you can believe was fair without trusting whoever ran it.

The fear that only appears in a bot other people run is the bot speaking for a community it knows nothing about. A member reading a claim card sees the name of a collection somebody else minted, is told to install a wallet app nobody here uses, and is sent to an explorer the operator never chose. None of that is a cosmetic problem. It is the difference between a gift from this server and a notification from a stranger's product, and it reads as the second one.

The same goes for what can be given away at all. A prize is whatever the operator holds: something from a collection they declared, or a one-off asset somebody sent them, and neither of those is the special case. A draw runs over their collections, and the only accounts kept out of it are the accounts they named. Nothing arrives already excluded, already favoured, or already assumed.

## Criteria

- **GIFT-1**  If someone sets an NFT aside for me, I hear about it
  - **GIFT-1.a**  If my wallet is not ready to receive it, it waits for me instead of going to someone else
  - **GIFT-1.b**  Nobody else can take something that was meant for me
- **GIFT-3**  If I never come and get it, it goes back in the pot rather than sitting there forever
- **GIFT-6**  When a prize is drawn I can check the count it was drawn from and where my ticket fell, without taking anyone's word for it
- **GIFT-7**  Everything I read when a gift arrives belongs to this server, not to whoever wrote the bot
  - **GIFT-7.a**  Nothing tells me to install one particular wallet app, or sends me to a site the people running this server did not pick
  - **GIFT-7.b**  When something stops me receiving a gift, I am told what I can do about it, in words meant for me rather than words meant for whoever runs the bot
  - **GIFT-7.c**  The thing I am being given is named the way this server names it, rather than by a bare id or by a collection nobody here has heard of
- **GIFT-8**  I can give away what this server actually has
  - **GIFT-8.a**  A prize can be an NFT from any collection I declared, or a one-off asset somebody sent me, and neither is a special case
  - **GIFT-8.b**  I can draw over any collection I declared, not only the ones the bot happened to be written for first
  - **GIFT-8.c**  The accounts I run are kept out of the draw, and they are the accounts I named rather than any the bot brought with it

## Retired

- **GIFT-2**  once I have taken it, the message says so instead of still offering it
        retired: written about the card rather than the core gift want; GIFT-1.b is exclusivity (nobody else takes what was meant for me), not post-claim card state. A clearer card-state criterion could be recaptured later
- **GIFT-4**  I can be picked at random for a prize, and see that the draw was fair
        retired: "fair" is not something a member can check, so it asserted nothing; GIFT-5 says what fair actually means here
  - **GIFT-4.a**  The house wallets are not in the draw competing with me
    retired: went with its parent GIFT-4; the house-wallet exclusion is part of what GIFT-5 now makes checkable
- **GIFT-5**  When a prize is drawn I can see the whole list it was drawn from, and my own name in it
        retired: written an hour earlier without checking: a draw posts the winner, weight mode, ticket count and index, but never the entrant list, so a member cannot see the list they were drawn from
