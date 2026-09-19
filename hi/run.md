---
hi: 1
families: [RUN]
---

# Run

## Intent

The person running this did not write it. They picked it up because their community wanted a role beside a name that matches what somebody holds, and now they own a thing that has to keep working while they are asleep, on a machine they would rather not think about.

Almost everything they will want to change is something they think of at the moment they need it: which channel, how often, the wording of an announcement, a number that turned out to be wrong. If changing any of that means waiting on a release, it does not get changed. So the settings a person reaches for have to be reachable from where they already are, and the few that genuinely cannot be have to say so at the moment of changing them rather than sit there looking like they took.

The other half is the update. A version that comes up broken must not be allowed to replace the one that was working, and a second copy started by accident must not be able to push the working one aside. Somebody who has not read the source cannot be expected to know which of those is survivable, so the software has to know. The same goes for a machine that restarts the bot in a loop: the loop is the operator's problem to find, but each restart must not cost them the work, or the allowance, that the last one already spent.

And when the bot speaks on somebody's behalf, the record has to say who asked for it. A message from a bot carries no author. Without a line written down before it goes out there is no answer at all to "who told it to say that", and nobody asks that on a good day.

Whether it is really working, and what it did last night, belong to SEE. What can be configured at all belongs to ADOPT, and the page an admin changes a setting on belongs to CATALOG. This family is the deploy, the moment of changing a setting, and the things the bot says out loud.

## Criteria

- **RUN-2**  I can change how it behaves without shipping new code for it
- **RUN-3**  A version that comes up broken does not replace the one that worked
- **RUN-4**  I can put an announcement in a channel as the bot without shipping code for it
- **RUN-5**  Anything the bot said on somebody's behalf can be traced back to who asked for it
- **RUN-6**  I can tell which of my settings take effect the moment I change them and which are waiting on a restart
  - **RUN-6.a**  A change that will not take until I restart says so when I make it, rather than looking like it took
- **RUN-7**  Starting a second copy by accident is a mistake I can undo, not one that takes the working bot down with it
  - **RUN-7.a**  The copy already serving my server is the one that keeps serving it, and the extra one is the one that stops
- **RUN-8**  A bot that restarts over and over does not keep redoing the work the last start already finished
  - **RUN-8.a**  A restart does not spend the day's allowance for reading the chain again on a sweep that has only just run
- **RUN-9**  A new version tells me what has to change before I take it, rather than once it is the only copy running
  - **RUN-9.a**  A version that needs a setting I do not have refuses to start and names the setting, instead of starting and quietly behaving differently
  - **RUN-9.b**  Nothing a new version needs of me is discovered at the first sweep, or at the first payment

## Retired

- **RUN-1**  If the bot is not really working, I find out from a check and not from a member complaining
        retired: a stranger reading the intent found this and SEE-1 were nearly the same sentence, and both files re-told the same outage. SEE owns health; RUN keeps deploy and runtime config
  - **RUN-1.a**  A version that comes up broken does not replace the one that worked
        retired: went with its parent, which is the right default but wrong here. This one is about deploys, not health. Recaptured as RUN-3
