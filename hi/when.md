---
hi: 1
families: [WHEN]
---

# When

## Intent

A server spread across timezones spends a surprising amount of its attention on arithmetic. Somebody says "8pm", four people work out what that means for them, one of them gets it wrong and misses the thing.

Discord already solved this: a time written as `<t:unix:F>` renders in every reader's own clock. The catch is that the shortcut for producing it only exists on desktop, so the people most likely to be reading on a phone are the ones who cannot write it. The feature exists and half the server is locked out of it.

So this is not a clever feature, it is a typing aid for something Discord already does. The measure of it is that somebody on a phone can say a time once and nobody has to do arithmetic.

Knowing where somebody is is worth remembering rather than asking for every time, but it is also the only personal thing anywhere in here. It is theirs to set, theirs to change and theirs to take back, and it is worth nothing to anybody else, which matters more in a server run by somebody they have never met.

The other half of it is refusing. A bot handed to strangers has no idea where its members are and no home clock to fall back on, so when it does not know, or when what somebody typed honestly means two different times, saying so is the only honest answer. A guess here is silent: it produces a perfectly formatted timestamp for the wrong moment, and the first anyone knows is an empty channel at the wrong hour.

## Criteria

- **WHEN-1**  When I give people a time, everyone reads it in their own clock
  - **WHEN-1.a**  I can do that from my phone, where Discord's own shortcut does not exist
- **WHEN-2**  I tell it where I am once, not every time I mention a time
- **WHEN-3**  Where I am is mine: I can change it or take it away, and nothing but my own times ever reads it
- **WHEN-4**  It never quietly picks a time for me
  - **WHEN-4.a**  If it does not know where I am it tells me how to say so, rather than answering in some default clock
  - **WHEN-4.b**  A time that could honestly mean two different moments is handed back to me rather than guessed at
