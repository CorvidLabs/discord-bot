---
hi: 1
families: [SEE]
---

# See

## Intent

The bot flapped for three hours and the first anybody knew was a member asking whether it was down. Nothing was broken in a way anyone could see: the process was alive, the port answered, the health check said ok. All of that was true and none of it was useful.

So the feeling to aim at is that the check tells me what a member would tell me, only sooner. Not that a process exists somewhere: that the thing is doing its job. And when it is not, I want to find that out while I still have the option of fixing it quietly.

The second half is memory. Most of what an operator needs is not live, it is yesterday: did the sweep finish, was that person held back on purpose, how much of the allowance went before it stopped. A bot that cannot answer questions about its own last few hours makes every incident start with archaeology.

The third half exists only because somebody else runs this now. The operator did not write it and cannot read it, and the pieces it leans on are pieces they chose: their own chain provider, their own place for proving wallets, their own server. So when one of those is down, saying that something is wrong is not enough; the check has to say which one, or the operator spends the outage restarting the wrong thing. And a problem kept to read later has to be written in terms of something they could change, because a sentence naming what failed inside the code is a sentence they can do nothing with.

What the bot made of my settings at startup belongs to ADOPT, and reading the settings back belongs to CATALOG. A member's own way of telling whether the bot is awake before believing an answer from it is LEARN's. This family is the operator's: what is true right now and what was true a few hours ago.

## Criteria

- **SEE-1**  I can tell whether the bot is really working from one check, without opening Discord to find out
  - **SEE-1.a**  A check that comes back fine never means only that a process is alive somewhere
- **SEE-2**  I can tell whether the last sweep of everyone's roles finished, and when
  - **SEE-2.a**  When someone's roles did not change I can tell whether we held them on purpose or simply missed them
- **SEE-4**  If Discord keeps refusing a role I am told once and it stops being retried forever
- **SEE-5**  A problem that started overnight is still there to read in the morning
- **SEE-6**  I can follow one sweep from start to finish without guessing which lines belong to it
- **SEE-7**  If the part that proves a wallet goes down, I lose verification and nothing else
- **SEE-8**  If this machine died I could bring the bot back with everyone's wallets intact
  - **SEE-8.a**  I find out a backup is unreadable before I need it rather than when I need it
- **SEE-9**  I can see how much of today's budget for reading the chain is gone while there is still time to act on it
- **SEE-10**  When something the bot leans on is down I am told which one, so I am not guessing between the chain, the part that proves wallets, and Discord
  - **SEE-10.a**  The check names the pieces I chose, so an outage at whoever I read the chain through reads as theirs and not as mine
- **SEE-11**  A problem I read afterwards names something I could change: a setting, a permission, an account, rather than the code that gave up
- **SEE-12**  I can tell which version is running, and whether it is the one I meant to put there

## Retired

- **SEE-3**  I can see how much of today's allowance is gone while there is still time to act on it
        retired: 'today's allowance' collided with SPEND-2's weekly spend cap. The same word for the daily budget of chain reads and the weekly ceiling on what can be sent was read as one thing by a stranger, who called it the ambiguity most likely to cause a wrong implementation
