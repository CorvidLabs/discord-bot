---
hi: 1
families: [HOST]
---

# Host

## Intent

Most people who would want this do not want a server, and should not have to learn one to give their community a role that matches what they hold. So somebody will offer to run it for them, and that offer has to be honest about where the line is.

The thing that would kill it is a community coming to believe the host holds their money. This bot signs Algorand transactions from a hot wallet, so "we run it for you" is one careless sentence away from "we are your custodian". The honest shape is that each community runs on its own instance, with its own key, holding its own data, and that leaving is easy and boring: a file they can take with them and run themselves that afternoon.

Being open source is what turns the sentence into a fact. A host can be asked what it can reach, and the answer can be read rather than believed. Anything a host can only promise is a thing a community is being asked to assume, and that is the assumption this family exists to remove.

Whether an instance can move money at all is the operator's decision and nobody else's. A community that wants roles and nothing else has no paying account, so there is nothing for a host to be custodian of and nothing anybody has to be trusted with. Most communities will want exactly that, and it should be the boring answer rather than a special case.

Leaving has two meanings and carrying a file to your own machine is only the weaker one. That is still this software, and a community that can move between machines but not away has not really been given the option. So what comes out has to be readable by something that is not this: a community that is done with it should be able to walk off with their members, their settings and the record of what was paid, and open all of it somewhere this project never hears about.

If a host cannot say plainly what it can and cannot reach, nobody should buy it. That is the whole family: a person being able to see the boundary, rather than being asked to assume one.

Watching whether an instance is healthy already has a home in SEE. That want does not change because somebody else is paying for the machine.

## Criteria

- **HOST-1**  I can have this running for my server without operating a server
- **HOST-2**  My members' data is only ever mine
- **HOST-3**  Nobody hosting this for me can move my project's funds
  - **HOST-3.a**  I can tell exactly what the people hosting it can reach
- **HOST-4**  If I stop paying I leave with my data and can keep running it myself
- **HOST-5**  I can read the code that is running for me, so what it can reach is something I check rather than something I am told
  - **HOST-5.a**  The instance states for itself what it has been talking to, rather than only a document about it saying so
- **HOST-6**  My instance is mine alone: nothing I configure and nobody I verify is shared with another community running the same bot
  - **HOST-6.a**  A mistake in my settings cannot reach another community's members
- **HOST-7**  Whether my instance can move money at all is mine to decide, and a host cannot turn it on
  - **HOST-7.a**  With no paying account there is nothing for a host to be custodian of, and I can say so plainly to my members
- **HOST-8**  Moving between running it myself and having somebody run it costs my members nothing
  - **HOST-8.a**  Nobody proves their wallet again because the machine changed hands
- **HOST-9**  I can take everything out in a form another tool can read, so leaving means moving on rather than only moving machines
  - **HOST-9.a**  What comes out is all of it: my members and their wallets, my settings, and the record of what was paid
  - **HOST-9.b**  I can take it out myself, whenever I want it, rather than asking whoever hosts me to prepare it
- **HOST-10**  My instance serves the one server I set it up for and no other
  - **HOST-10.a**  Added to a second server it says it does not serve there, rather than answering with another community's data
