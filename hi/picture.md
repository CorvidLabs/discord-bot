---
hi: 1
families: [PICTURE]
---

# Picture

## Intent

People do not hold these for the asset id. The picture is the thing, and a card without one is worse than no card at all: it reads as "your NFT is broken" when the truth is only that a file could not be fetched this minute.

The pipeline exists so that nobody has to think about it. A new piece is minted and it simply appears. The operator imports nothing and the member refreshes nothing.

The failure to design against is the quiet one. A metadata host that answers slowly, a gateway that goes away, a collection that cannot be read this morning: none of those should cost a picture that was already in hand. Keeping the last good picture is always better than replacing it with nothing, because the picture is the product and the fetch is only plumbing.

Two things change once the collections belong to whoever is running this rather than to us. The gateway the pictures come through is theirs to name, because a default pointing at somebody else's paid account is a default with none of their art behind it. And a piece has to be recognised as theirs by rules they wrote down, because the alternative is guessing, and a guess means a stranger's asset turning up on a card wearing their collection's name, counted toward a role somebody did not earn.

## Criteria

- **PICTURE-1**  The picture on my card is the picture of my NFT, not a stand-in
- **PICTURE-2**  A newly minted piece shows up on members' cards without me doing anything
  - **PICTURE-2.a**  If one collection cannot be read the others still refresh
  - **PICTURE-2.b**  A refresh that comes back with nothing does not erase the pictures I already had
- **PICTURE-3**  I can tell how many pieces are missing a picture without going and looking in Discord
- **PICTURE-4**  A picture that is slow the first time is quick every time after
- **PICTURE-5**  The gateway my members' pictures are fetched through is one I choose, not somebody else's paid account
- **PICTURE-6**  An asset from outside my collections is never shown as though it were one of mine
  - **PICTURE-6.a**  I say what makes a piece mine, and a piece matching nothing I described is left uncatalogued rather than guessed at
