---
module: surface
version: 1
status: active
files:
  - Sources/Surface/Boot/BootReport.swift
  - Sources/Surface/Boot/BootSequence.swift
  - Sources/Surface/Boot/SurfaceConfiguration.swift
  - Sources/Surface/Boot/SurfaceConfigurationError.swift
  - Sources/Surface/Boot/SurfaceHealth.swift
  - Sources/Surface/Cards/CardChrome.swift
  - Sources/Surface/Cards/SurfaceCard.swift
  - Sources/Surface/Catalog/CommandCatalog.swift
  - Sources/Surface/Catalog/CommandDefinition.swift
  - Sources/Surface/Catalog/CommandValidator.swift
  - Sources/Surface/Commands/HelpCommand.swift
  - Sources/Surface/Commands/PingCommand.swift
  - Sources/Surface/Commands/UnlinkCommand.swift
  - Sources/Surface/Commands/VerifyCommand.swift
  - Sources/Surface/Identity/DiscordUserId.swift
  - Sources/Surface/Reply/JobMailbox.swift
  - Sources/Surface/Reply/ReplyBounds.swift
  - Sources/Surface/Reply/ReplyLimits.swift
  - Sources/Surface/Reply/SurfaceReply.swift
  - Sources/Surface/Roles/RoleApplier.swift
  - Sources/Surface/Router/CommandAuth.swift
  - Sources/Surface/Router/InteractionRequest.swift
  - Sources/Surface/Router/SurfaceRouter.swift
  - Sources/Surface/Verify/AccountHoldingsReader.swift
  - Sources/Surface/Verify/CallbackRoute.swift
  - Sources/Surface/Verify/MemberDeparture.swift
  - Sources/Surface/Verify/VerificationCallback.swift
  - Sources/Surface/Verify/VerificationCallbackHandler.swift
  - Sources/Surface/Verify/VerificationClient.swift
  - Sources/SurfaceDiscord/CallbackResponder.swift
  - Sources/SurfaceDiscord/CardRendering.swift
  - Sources/SurfaceDiscord/ChainAccountReader.swift
  - Sources/SurfaceDiscord/CommandPayloadMapping.swift
  - Sources/SurfaceDiscord/DiscordBoot.swift
  - Sources/SurfaceDiscord/DiscordRoleApplier.swift
  - Sources/SurfaceDiscord/DiscordSurface.swift
  - Sources/SurfaceDiscord/HTTPVerificationClient.swift
  - Sources/SurfaceDiscord/InteractionDecoding.swift
  - Sources/SurfaceDiscord/PreopenedStore.swift
  - Sources/SurfaceDiscord/ReplySending.swift
  - Sources/SurfaceDiscord/SocketHTTPListener.swift

db_tables: []
depends_on: ["store", "gating", "chain"]
---

# Surface

## Purpose

What a member touches. Two targets, one contract.

- `Surface` holds the values and the rules: the command catalogue, the
  validator that refuses a catalogue Discord would refuse, the interaction
  router and its acknowledgement policy, the payload bounds, the cards, the
  boot sequence, the four command handlers and the verification seam. It
  declares no chat client, so `import DiscordBM` in it is a missing module
  rather than a review comment, and the whole of it is exercised with no
  token, no network and no guild (`BUILD-2`).
- `SurfaceDiscord` is the adapter, and the only target in this package that
  knows what a snowflake is. Everything in it is a mapping, plus the two
  sockets this process owns and the HTTP client for the other half of
  verification.

The executable `discord-bot` is wiring and holds no command logic.

**Four commands ship: `/ping`, `/help`, `/verify`, `/unlink`.** Everything
else from the project this was ported from is deliberately absent and waits
for work of its own: the role sweep, the money commands, the games, the
operator surfaces and the holdings browser. What is here is the surface they
will all be built on, and it was built first because the expensive failures
are boot and registration.

### The three failures this target exists to prevent

**A catalogue Discord refuses crash-loops a boot.** A required option after an
optional one on the same command is a `400` on the whole bulk registration,
the boot that was waiting on it fails, and under a supervisor that restarts
the process it fails again, for ever. ``CommandValidator`` refuses it offline,
in a unit test, before anything is sent, and ``BootSequence`` runs the
validator before the registration call.

**A second copy takes the live copy's session.** Discord answers a duplicate
identify by invalidating the session it collides with. A second copy that
identified before finding out its port was taken would knock the healthy bot
offline and then exit anyway, which under a supervisor is a reconnect storm
with no bottom. So the order is lease, bind, identify, and binding is how a
process discovers the other one (`RUN-7`, `RUN-7.a`).

**An over-long payload becomes a reply that never arrives.** Discord counts
UTF-16 code units and `String.count` counts grapheme clusters, so a card of
emoji passes a `count` check and is refused by the API. Because the handler
deferred first, that refusal reaches the member as a thinking indicator that
never resolves, with nothing anywhere they can read. ``ReplyLimits`` is the
only counter at the boundary and ``ReplyBounds`` refuses or clamps before the
send.

### What is deliberately not here

- The role sweep and `/resync`. First verification applies roles; staying true
  when somebody sells is the next change.
- Every money command, every game command and every operator command.
- A second HTTP interface for administration.
- The `guildMessages` intent and message content. This process asks for
  `guilds` and `guildMembers` and nothing else.
- Any default that belonged to another project: no default ladder, no default
  picture, no default presence, no default operator channel.

## Public API

Every exported symbol of `Surface` and `SurfaceDiscord`, alphabetically. A
name several types share is described once, and the other meanings are named
in the same line.

| Export | Description |
|--------|-------------|
| `accepted` | The callback passed every check. |
| `AcceptFailureAction` | What the accept loop should do about one failed `accept`. |
| `AcceptFailurePolicy` | How a failed `accept` is treated, counted and backed off. |
| `account` | The account the other half already has for this member, or nil. On `Chain`'s reader, one account read. |
| `accountBelongsToSomebodyElse` | Another member already proved this account. |
| `AccountHoldingsReader` | Reads one account off the chain, with how complete the reading was in the answer. |
| `acknowledge` | When the handler must have answered by. |
| `acknowledgeLater` | Tell Discord the handler is working. |
| `AcknowledgePolicy` | How long a command is allowed to take before it has said anything. |
| `address` | The account they proved. |
| `addressUnusable` | The address is not one this process can bind. |
| `administrator` | Administrator, bit three. The one permission that grants an operator command on its own. |
| `adminRoleId` | An extra operator role, or nil. |
| `adminRoleKey` | An extra role that may run operator commands. |
| `afterReply` | Work to start **after** the answer has gone out, or nil. |
| `agreed` | Both halves hold the same secret. |
| `allEntries` | Every command this package knows how to build, with what each needs. |
| `apiKeyHeader` | The header the shared secret travels in. |
| `applicationId` | The application id, when it is known, for the invite URL. |
| `applicationKey` | The application this bot is, for the invite URL. |
| `applied` | Whether the decision reached the chat client. |
| `apply` | Puts one decision into effect, touching only the managed set, in one call. |
| `attachFiles` | Attach Files, bit fifteen. |
| `attachmentName` | The name of a file sent with this card, or nil. |
| `attachments` | The files on this message **after** it is sent or edited. |
| `AttachmentSpec` | A file travelling with a message. |
| `autocomplete` | Whether the handler is asked for suggestions as the member types. |
| `AutocompleteChoice` | One option offered while somebody is still typing. |
| `AutocompleteHandler` | Something that suggests as a member types. |
| `badCharacters` | A name used something outside Discord's allowed character set. |
| `badNesting` | A subcommand group held something other than subcommands. |
| `balanceBaseUnits` | What the portal saw it holding, in base units. |
| `baseURL` | The base URL, with no trailing slash and no path. |
| `bind` | Claims one port, or throws. A bind failing is how this process learns another copy is running. |
| `body` | Everything after the first empty line. |
| `boolean` | True or false. |
| `booleanValue` | The flag, when it is one. |
| `BootError` | Why a boot stopped. |
| `BootReport` | What this bot prints when it starts. |
| `BootSequence` | Starting up, in the order that matters. |
| `BootStep` | One thing the boot did, in the order it did it. |
| `botName` | What the operator calls this bot. |
| `botNameKey` | What the operator calls this bot on its cards. |
| `botToken` | The bot's token. |
| `bound` | A port was claimed. |
| `BoundedMessage` | What enforcing the bounds did to a message. |
| `build` | The commands to register, given what is switched on. |
| `buttonLabel` | A button's label. |
| `buttons` | The buttons under it. |
| `ButtonSpec` | A button on a card. |
| `buttonsPerRow` | Buttons in one action row. |
| `ButtonStyle` | How a button looks, in Discord's own five styles. |
| `callbackPath` | The callback path, as `docs/VERIFICATION.md` writes it. |
| `callbackPort` | The callback listener's port. |
| `callbackPortKey` | The port the verification callback listener binds. |
| `CallbackRateLimiter` | How many callbacks one source may send. |
| `CallbackRefusal` | Why a callback was thrown away. |
| `CallbackResponder` | What answers on the port the other half calls back on. |
| `CallbackRoute` | What the listener should do about one request. |
| `CallbackRouting` | Every check a callback passes, in the order it passes them. |
| `CallbackValidation` | Checks a callback before anything acts on it. |
| `card` | The card, or nil for text alone. |
| `CardChrome` | The words and the colours on every card, as this operator set them. |
| `CardRendering` | Turns a card into the payload Discord draws. |
| `catalog` | The catalogue to register. |
| `CatalogEntry` | One command, and what has to be switched on for it to exist. |
| `ChainAccountReader` | Reads one account through the chain layer's brakes. |
| `channel` | A channel. |
| `check` | What one account holds, and what could not be read, with the gaps in the answer. |
| `choices` | Fixed values, when the member picks rather than types. |
| `clamp` | The text, shortened to fit and marked as shortened. |
| `clamped` | It did not fit and was shortened. |
| `color` | The colour a card is drawn in, or nil when the operator set none. |
| `command` | The command of this name, or nil. |
| `CommandAuth` | Who may run an operator command. |
| `CommandCatalog` | Every slash command this process will register, as a value. |
| `CommandCatalogInvalid` | Everything wrong with a catalogue, as one error a boot can print. |
| `CommandChoice` | One fixed value an option offers. |
| `CommandDefinition` | One slash command, as a value this package owns. |
| `CommandHandler` | Something that answers one slash command. |
| `commandName` | The command's name, for a command or an autocomplete. |
| `CommandOption` | One option on a command, a subcommand, or a subcommand group. |
| `CommandOptionType` | The kind of thing a slash-command option holds. |
| `CommandPayloadMapping` | Turns this package's command values into the payloads Discord accepts. |
| `CommandRegistrar` | Something that registers the catalogue with the chat client over HTTP. |
| `CommandRule` | A rule Discord enforces at registration, named so a failure says which one. |
| `commands` | The commands, in the order they were built. |
| `CommandValidator` | Refuses, offline, a catalogue Discord would refuse. |
| `component` | Somebody pressed a button or picked from a menu. |
| `ComponentHandler` | Something that answers a button or a menu. |
| `ComponentHealth` | How one thing this bot leans on is doing. |
| `components` | A card's buttons, in rows of five. |
| `configuration` | What the operator configured. |
| `constantTimeEquals` | Whether two secrets match, without leaking how far they matched. |
| `contact` | How to reach them, or nil. |
| `contactKey` | The variable naming how to reach whoever runs it. |
| `content` | Plain text above the card, or nil. |
| `createSession` | A fresh verification link for this member. |
| `currentRoleIds` | Every role a member holds now. A failure throws rather than answering with an empty set. |
| `customId` | A component's custom id. |
| `danger` | Something that takes a thing away. |
| `deadline` | When the token stops working. |
| `decision` | What the rules decided, or nil when the roles were held. |
| `defaultListenAddress` | Loopback. |
| `defaultMemberPermissions` | The permission bits Discord uses to hide it from ordinary members, or nil to show it to everybody. |
| `deferEphemeral` | Defers first, then follows up inside fifteen minutes. |
| `deferPublic` | Defers publicly, then follows up inside fifteen minutes. |
| `defersFirst` | Whether the router emits a defer before calling the handler. |
| `definition` | The command. |
| `deleteSession` | Forgets this member on the other half too, so an unlinked member keeps nothing a session opened. |
| `description` | The body under the heading. |
| `detail` | What to change. |
| `directMessage` | The token has expired; the invoker gets a direct message. |
| `directMessageToInvoker` | A direct message to whoever ran the command. |
| `disabled` | Whether it is greyed out. |
| `disagreed` | They do not. |
| `disclosureCard` | What a member reads before they sign. |
| `DisclosureSettings` | What a member is told before they sign anything. |
| `discord` | The gateway. |
| `DiscordCommandRegistrar` | Registers the catalogue with Discord over HTTP. |
| `DiscordGatewayConnection` | Identifies to the gateway. |
| `DiscordPermission` | Discord's permission bits, as the few this package actually reads. |
| `DiscordRoleApplier` | Applies a decision to a member in one Discord call. |
| `DiscordSurface` | One running bot. |
| `DiscordUserId` | A chat account id, checked, on its way to becoming a plain string. |
| `down` | Down. |
| `duplicateCommand` | Two commands in the catalogue had the same name. |
| `duplicateName` | Two options or subcommands in one array had the same name. |
| `edit` | A message as an edit of one already sent. |
| `ellipsis` | What a clamped string ends with. |
| `embed` | A card as an embed. |
| `embedDescription` | An embed description. |
| `embedFieldCount` | Fields on one embed. |
| `embedFieldName` | An embed field's name. |
| `embedFieldValue` | An embed field's value. |
| `embedFooter` | An embed footer. |
| `embedLinks` | Embed Links, bit fourteen. |
| `embedTitle` | An embed title. |
| `embedTotal` | Every embed on one message, added together. |
| `empty` | A name or description was empty. |
| `enabled` | The parts that are on. |
| `enforce` | The message, made to fit, or a refusal. |
| `ephemeral` | An ephemeral line of text. |
| `errorDescription` | The sentence an operator or a member reads, naming what to change. |
| `exact` | Exact values, compared without regard to case. |
| `expiresAt` | When the link stops working. |
| `externalId` | The id as digits. |
| `features` | Which parts this instance is running. |
| `fields` | Named lines. |
| `filename` | Its name, which is what `attachment://` markup refers to. |
| `finish` | Records what happened and says where to send it. |
| `fits` | Whether this text fits, in the unit that decides. |
| `flag` | Whether a flag option arrived true. |
| `focusedOption` | Which option the member is typing in, for an autocomplete. |
| `followUp` | The interaction is still live, so the report goes where it was asked for. |
| `footer` | The small line at the bottom. |
| `foreignGuild` | A server this instance does not serve (`HOST-6`, `HOST-10`). |
| `games` | The card table is open. |
| `GatewayConnection` | Something that identifies to the gateway. |
| `gating` | What the operator configured for the ladder. |
| `giveUp` | Stop accepting. The listener is not coming back on its own. |
| `guildId` | The one server this process serves. |
| `guildKey` | The one server this process serves. |
| `handle` | Answers one interaction, or runs one departure, or runs one callback, depending on the type it is on. |
| `has` | Whether this part is on. |
| `hasVerification` | Whether a member can prove an account at all. |
| `headers` | Header names lowercased, values trimmed. |
| `health` | Answer the health check. |
| `healthPath` | The health path. |
| `healthPort` | The health listener's port. |
| `healthPortKey` | The port the health listener binds. |
| `HealthState` | The health this process is currently reporting. |
| `help` | The name of the command that says what this bot does here. |
| `HelpCommand` | `/help`: what this bot can do **in this server**. |
| `HTTPListenerReply` | What a listener answers with, and what it does afterwards. |
| `HTTPRequestHead` | One HTTP request, parsed. |
| `HTTPVerificationClient` | The other half of verification, over HTTP. |
| `id` | What the router matches, namespaced with a prefix and a colon. |
| `identified` | This process identified to the gateway. |
| `identify` | Identifies to the gateway. Called once, and only once every bind has succeeded. |
| `imageURL` | A large picture under the body, under the same rule as the thumbnail. |
| `immediate` | Answer now. |
| `incidentLine` | What to report about a role write the chat client accepted and ignored, or nil. |
| `index` | Where this file sits in the message's file list. |
| `init` | - Parameters: - configuration: What the operator configured. |
| `initialBackoff` | The first wait after a failed accept. |
| `inline` | Whether it sits beside its neighbour rather than under it. |
| `integer` | A whole number. |
| `integerValue` | The whole number, when it is one. |
| `InteractionDecoding` | Turns what the gateway delivered into a value the rest of this package can take. |
| `interactionId` | Discord's id for this interaction. |
| `InteractionKind` | What kind of thing arrived. |
| `InteractionRequest` | One inbound interaction, as a value with no chat-client type on it. |
| `invalid` | A variable holds something that is not the shape it must be. |
| `inviteURL` | The invite that grants exactly the permissions this process needs. |
| `invokerExternalId` | Who asked for it. |
| `isContainer` | Whether this kind carries nested options rather than a value. |
| `isEphemeral` | Whether only the person who ran the command sees it. |
| `isLimited` | Records one request and says whether it is over the limit. |
| `isMemberFacing` | Whether `/help` lists it to an ordinary member. |
| `isOperator` | Whether this member may run an operator command. |
| `isOperatorOnly` | Whether this is an operator command, whatever Discord was told. |
| `isRoutable` | Whether the router should try to claim this button's id. |
| `issues` | Every issue found, in the order they were found. |
| `JobDelivery` | Where one report is actually being sent. |
| `JobFallback` | Where a report goes when the interaction that asked for it has expired. |
| `JobId` | A job whose report may outlive the interaction that started it. |
| `JobMailbox` | Work that can outlive the interaction that started it. |
| `JobRecord` | What is known about one long-running job. |
| `joinWithinLimit` | Joins lines, dropping whole ones rather than cutting through one, and saying how many went. |
| `jsonBody` | The body, as JSON, written by hand so the key order is the order a person reads it in. |
| `kind` | What kind of thing arrived. |
| `label` | What it says. |
| `length` | How long Discord thinks this text is. |
| `limit` | How many are allowed in one window. |
| `lines` | The whole report, one line at a time. |
| `link` | A link out. |
| `listCard` | The card that lists what a member has, and changes nothing. |
| `listenAddress` | What both listeners bind to. |
| `listenAddressKey` | What the listeners bind to. |
| `ListenerBinder` | Claims the ports this process owns, and serves them. |
| `ListenerError` | Why a listener could not start. |
| `listenFailed` | The socket bound and would not listen. |
| `load` | Reads the environment, or refuses naming the variable. |
| `longRunning` | Started something long. |
| `looksUnfinished` | Whether this looks like something nobody meant to leave in. |
| `malformedAddress` | The account is not a shape this chain uses. |
| `malformedMemberId` | The chat account id is not one to twenty digits. |
| `malformedResponse` | It answered the right status with a body that would not decode. |
| `managedRoleIds` | Every role this configuration governs. |
| `manageRoles` | Manage Roles, bit twenty-eight. The one that fails quietly when a managed role sits above the bot's own. |
| `maximumBackoff` | The longest wait between two accepts. |
| `maximumChoices` | Most choices on one option. |
| `maximumConsecutiveFailures` | How many failed accepts in a row mean the listener is dead. |
| `maximumDescriptionLength` | Longest a description may be. |
| `maximumDigits` | The widest a Discord snowflake gets, written out in decimal. |
| `maximumNameLength` | Longest a command or option name may be. |
| `maximumOptionsPerArray` | Most options, subcommands or groups in one array. |
| `maximumRequestBytes` | Most bytes read from one connection. |
| `maximumSuggestions` | Most suggestions Discord will show. |
| `MemberDeparture` | Somebody left the server. |
| `memberEntries` | The entries `/help` lists, given what is switched on. |
| `memberKey` | The member, as this instance names them. |
| `memberRoleIds` | Every role they hold, as plain strings. |
| `mention` | The markup that renders as a mention of this person. |
| `message` | The message to send, or nil when it was refused. |
| `messageContent` | A message body. |
| `method` | `GET`, `POST`, and so on. |
| `missing` | A required variable is unset or blank. |
| `missingGuild` | No server was named. |
| `mixedContainers` | A subcommand or a group sat beside a plain option in one array. |
| `name` | The field's name. |
| `names` | The names, in order. |
| `namespace` | The custom-id prefix a component handler claims, separator included. |
| `none` | Nowhere. |
| `notes` | Anything an operator should read, in the order it happened. |
| `notOffered` | This portal offers nothing to probe, so nothing is known either way. |
| `number` | A number with a fractional part. |
| `off` | Switched off by the operator, so not a fault. |
| `open` | Opens the store and takes its lease, or throws when another process holds it. |
| `openedStore` | The store opened and its lease was taken. |
| `operatorName` | Who runs this instance, in their own words. |
| `operatorNameKey` | The variable naming who runs this instance. |
| `options` | Nested options, for a subcommand or a group. |
| `OptionValue` | A value an option arrived with. |
| `parse` | One request as text, or nil when the first line is not a request line. |
| `path` | The path, query string included. |
| `payload` | One command, as Discord's create payload. |
| `payloads` | The whole catalogue, as create payloads. |
| `peerTimeoutSeconds` | How long a peer has to send its request, and to take its answer. |
| `perform` | Carries out every action, in order. |
| `permissionBits` | The permissions Discord computed for them here, or nil. |
| `ping` | The name of the command that says whether the bot is awake. |
| `PingCommand` | `/ping`: is the bot awake. |
| `placeholder` | A variable still holds a value copied out of an example file. |
| `PlaceholderValues` | Values that mean somebody copied the example file and did not finish. |
| `pools` | The pools an operator counts. |
| `port` | The port it binds. |
| `PortalAccount` | What the other half already has on record for a member. |
| `portalURL` | Where the other half lives, or nil when verification is off. |
| `portalURLKey` | Where the other half of verification lives. |
| `PortBinder` | Something that claims a local port. |
| `portInUse` | A port was already in use. |
| `portTaken` | The port is taken. |
| `PreopenedStore` | Hands the boot a store that is already open. |
| `primary` | The one action a card is mostly about. |
| `probedSharedSecret` | The keyed probe ran, and what it found. |
| `probeSharedSecret` | Whether both halves hold the same secret, asked at startup with the key. |
| `ready` | Health began reporting `200`. |
| `reason` | The sentence sent back, which the contract says is echoed in the body. |
| `receivedAt` | When it arrived, which is when the fifteen minutes start. |
| `record` | What is on record for a job, including a report nobody could deliver. |
| `recordFailure` | Records one failed accept and says what to do about it. |
| `recordSuccess` | Records one accepted connection, which forgives everything before it. |
| `refusal` | Nothing, or why this callback is refused. |
| `refuse` | Answer this status with this JSON body, and do nothing else. |
| `refused` | It did not pass `CallbackValidation`. |
| `register` | Replaces the served server's commands with this catalogue. Guild commands, never global. |
| `registeredCommands` | The catalogue was registered with the chat client. |
| `removedCard` | The card that says what was removed. |
| `reply` | Answer now. |
| `ReplyBounds` | The last thing between a handler and the chat client. |
| `ReplyLimits` | The lengths Discord refuses a payload for, and the only place this package is allowed to measure one. |
| `ReplySending` | Performs what the router decided. |
| `report` | What happened, once it has. |
| `request` | One interaction as a request, or nil when it carries nothing to route. |
| `required` | Whether the member must supply it. |
| `requiredAfterOptional` | A required option came after an optional one in the same array. |
| `requiredNames` | The same permissions in the words Discord's own interface uses for them, in the order above, so an operator can find each one in the list rather than translate from a bit (`ADOPT-11.b`). |
| `requires` | Every part that must be on. |
| `respond` | Answers one request on the callback port. |
| `response` | A message as an immediate interaction response. |
| `retry` | Wait this long and accept again. |
| `role` | A role. |
| `RoleApplier` | Puts a decision into effect in the chat client. |
| `rolesAboveBot` | Every managed role that sits above this bot's own, highest first. |
| `rolesAboveBotLine` | What to print when a configured role sits at or above this bot's own. |
| `rolesOnly` | A community that wants roles and nothing else (`SPEND-6.c`, `PLAY-9`). |
| `RoleWriteCheck` | What the chat client actually did with a role list it accepted. |
| `route` | The path with any query string taken off. |
| `RouterAction` | One thing the adapter should do with the chat client. |
| `rowsPerMessage` | Action rows on one message. |
| `rule` | Which rule it breaks. |
| `run` | Runs the boot, or throws at the first step that will not work. |
| `secondary` | Everything else. |
| `secretRejected` | It answered `401`. |
| `sendMessages` | Send Messages, bit eleven. |
| `servedGuildId` | The one server this process serves. |
| `setDiscord` | Records how the gateway is doing. |
| `setStore` | Records how the store is doing. |
| `setVerification` | Records how the verification half is doing. |
| `sharedSecret` | The one secret both halves hold, or nil when verification is off. |
| `sharedSecretKey` | The one secret both halves hold. |
| `sharedSecretMismatch` | The keyed probe found the two halves hold different secrets. |
| `SharedSecretProbe` | What a keyed probe at boot found out. |
| `shutdown` | Stops accepting, releases the ports and closes the store. |
| `silentlyIgnored` | Every role that was sent and is not on the member afterwards. |
| `snapshot` | What is reported now. |
| `SocketHTTPListener` | A very small HTTP listener, on the platform's own sockets. |
| `socketUnavailable` | The socket could not be created. |
| `spending` | The bot holds a key and can move value. |
| `start` | Records that a job has started, and until when it can answer normally. |
| `starting` | Not up yet. |
| `status` | One word for the whole thing. |
| `statusCode` | What the listener answers with. |
| `stop` | Releases every port this has claimed. |
| `store` | The store. |
| `storeHeld` | Another process holds the store. |
| `StoreOpener` | Something that opens this instance's store and takes its lease. |
| `string` | Text. |
| `stringValue` | The text, when it is text. |
| `style` | How it looks. |
| `subcommand` | A subcommand. |
| `subcommandGroup` | A group of subcommands. |
| `subcommandPath` | The subcommand group and subcommand, outermost first, when there is one. |
| `success` | A confirmation. |
| `suggest` | Offer these while the member types. |
| `suggestions` | Suggestions, as Discord's autocomplete payload. |
| `SurfaceCard` | A card, as a value. |
| `SurfaceConfiguration` | Everything this target reads from the environment. |
| `SurfaceConfigurationError` | Why this process will not start. |
| `SurfaceFeature` | A part of this bot an operator either switched on or did not. |
| `SurfaceFeatures` | Which parts this instance is running. |
| `SurfaceField` | One named line on a card. |
| `SurfaceHealth` | What the health listener answers. |
| `SurfaceReply` | What a handler answers with. |
| `SurfaceRouter` | Turns an interaction into the actions that answer it. |
| `thumbnailURL` | The picture beside a card's title, or nil. |
| `title` | The heading. |
| `token` | The portal's own identifier for the session. |
| `tokenKey` | The bot's token. |
| `tokenLifetime` | How long an interaction token stays usable. |
| `tooLong` | A name or description was longer than Discord allows, counted in UTF-16 code units. |
| `tooManyOptions` | More than twenty-five entries in one options array. |
| `track` | Remember a job whose report may outlive the interaction. |
| `truncation` | What to do when this does not fit. |
| `TruncationPolicy` | What happens to a payload that does not fit. |
| `type` | What kind of thing it holds. |
| `undeliverable` | The token has expired and there is nowhere configured. |
| `unexpectedStatus` | It answered something this contract does not allow. |
| `unlink` | The name of the command that removes an account. On `AccountStore`, the removal itself. |
| `unlinkAccountOption` | The option on `/unlink` naming which account to remove. |
| `UnlinkCommand` | `/unlink`: stop being tracked. |
| `unreachable` | It could not be reached at all: refused, timed out, or TLS failed. |
| `up` | Up. |
| `update` | A message as a replacement for the one a component sat on. |
| `updateMessage` | Replace the message a component sat on. |
| `url` | Where the member goes. |
| `user` | A member of the server. |
| `userExternalId` | Who ran it, as a plain string. |
| `userId` | The invoker's id, checked. |
| `validate` | Nothing, or a refusal naming every rule broken. |
| `validatedCatalog` | The catalogue passed the validator. |
| `ValidationIssue` | One thing wrong with a catalogue, and where. |
| `value` | The field's body. |
| `verification` | The half that proves accounts. |
| `VerificationCallback` | What the other half sends when a member has signed. |
| `VerificationCallbackError` | Why a callback did nothing. |
| `VerificationCallbackHandler` | The path a member actually takes into a role. |
| `VerificationClient` | The other half of verification, as a seam. |
| `VerificationError` | What can go wrong talking to the other half. |
| `VerificationOutcome` | What a callback did. |
| `verificationReachable` | The other half answered its health check. |
| `VerificationSession` | A link a member can follow to prove an account. |
| `verify` | The name of the command that proves an account. |
| `VerifyCommand` | `/verify`: prove an account is yours. |
| `visibilityKey` | The variable saying which of it other members can see. |
| `visibilityNote` | Which of it other members will see, in the operator's own words. |
| `VisibleMessage` | A message somebody will actually see. |
| `window` | How long the window is. |
| `within` | It fits, exactly as written. |

## Invariants

- **A member is a `String` below the chat boundary.** ``DiscordUserId`` is the
  only place a chat account id is checked, and what travels on is
  `externalId`. No snowflake type appears in `Surface`, which a test greps
  for, and `Store` declares no chat client at all, so the reverse is a missing
  module rather than a review comment.
- **Only `SurfaceDiscord` imports the chat client.** A test greps every file
  under `Sources/` for the import statement and allows one directory.
- **The catalogue is the single source of what exists.** Registration maps it
  and `/help` is generated from it, so a command that is not registered
  cannot be described (`LEARN-8`).
- **A catalogue is validated before it is registered**, and the validator
  needs no network.
- **Boot order: lease, bind, validate, register, identify, ready.** Identify
  is never reached if the lease or a bind failed.
- **Health answers `503` until the gateway is ready.** A bound socket is not
  health, and neither is a returned identify: asking for a websocket is not
  having one. The gateway's own ready event is the only thing that raises
  health, and the event stream ending lowers it again.
- **Nothing that blocks runs on the cooperative pool.** `accept`, `recv` and
  `send` each run on a thread of their own, and every accepted socket carries
  a receive and send timeout, so peers that connect and say nothing cost
  short-lived threads rather than the gateway, every command and the health
  snapshot.
- **A failed `accept` is retried, not treated as the end of the listener.**
  The wait doubles from a tenth of a second to five, and after fifty failures
  in a row the process exits so a supervisor starts a working one: a bound
  port nothing serves goes on passing a health check while every callback is
  lost.
- **Health costs nothing that could be gone.** The answer is built from values
  this process already holds, so it spends no chain request and still answers
  once the day's budget is spent (`SEE-1.b`).
- **The router answers every interaction.** An unknown command, an unrouted
  component id and an autocomplete with no handler each get an answer.
- **The router, not the handler, emits the defer.** A handler cannot forget.
- **Autocomplete never defers**, because Discord does not allow it.
- **One instance serves one guild.** An interaction from anywhere else is
  refused without reading or writing anything.
- **Every payload is bounded in UTF-16 code units** before it is sent, and
  under ``TruncationPolicy/refuse`` nothing is shortened, dropped or left off
  the end: not an over-long string, not the fields past twenty-five, not the
  buttons past twenty-five, and not the sections an over-long embed total
  would cost.
- **The callback rate limit counts the callback route and nothing else.**
  Behind a reverse proxy every request shares one address, so a scanner or a
  health poller counted there would answer the next real callback `429`.
- **No shared secret means no callback route.** Two empty strings compare
  equal, so an unset secret and an empty header would be a match; with
  verification off the route answers `404` to everything.
- **A callback that arrives before the store is open is refused**, never
  answered `200` and dropped. The other half records a verification whenever
  its callback succeeds.
- **A stored balance nobody has read is not a reading.** An account with no
  `balancesReadAt` makes the total unknown rather than adding zero to it, and
  accounts are added with a saturating sum rather than a wrapping one.
- **A role write is read back**, because the chat client answers `200` and
  silently drops an id it does not know. The difference is reported with the
  ids in it.
- **Every message edit carries an `attachments` array**, empty rather than
  absent.
- **Only ``Gating/RoleDecision/managed`` is touched, in one call**, and only
  when the member's current roles could be read. A failed read holds rather
  than applying against an empty set.
- **A card is a `Sendable`, `Equatable` value with no chat-client type on it**,
  and a button carries an id rather than a closure.
- **No string a member can read carries a name, a collection, a ticker, a URL
  or a threshold from the project this was ported from**, which a test greps
  for.
- **Nothing in the test suite can reach a live host**, which a test also greps
  for: `SurfaceTests` does not depend on the adapter, so it cannot construct
  an HTTP client at all.

## Behavioral Examples

**A member proves an account.** `/verify` defers ephemerally inside three
seconds, asks the portal for a session, and answers with a disclosure card
carrying who is asking, what this server keeps, what other members see, how
to leave, and one link button. The member signs in a browser. The portal
calls back. The listener answers `200` only after the payload has been
validated, then admits the member, proves the account, reads every account
they have, builds ``Gating/MemberHoldings`` with unknown where a read failed,
calls ``Gating/RoleRules/decide(configuration:holdings:currentRoleIds:)``, and
applies the managed set in one call.

**A member links a second, empty account.** Both accounts are read and summed,
so the member keeps the rung the first one earned. Six hundred plus six
hundred clears a rung neither clears alone.

**A node blinks during a callback.** The reading is `unavailable`, which
becomes ``Gating/Reading/unknown``, which takes every role the balance decides
out of the managed set. Nothing is revoked, the card says so, and the next
sweep will put it right.

**A member unlinks one of three accounts.** They are listed if none was named.
The named one is removed, the accounts are read again rather than subtracted
from the list read before the removal, the member is kept because two remain,
the portal is told, and the roles are re-decided from what is left rather
than stripped and re-granted. If one of the two left has never been read, the
total is unknown and every rung is held.

**A peer connects to a listener and says nothing.** It is accepted on the
accept thread, served on a thread of its own, and dropped when the receive
timeout expires. Everything else carries on being served throughout.

**A configured role id has a wrong digit.** The member update succeeds, the
chat client drops the id, the read back after it finds the difference, and a
line naming the exact id is reported. Without it the bot looks like it works
and re-sends the same list for ever.

**A member leaves the server.** `guildMemberRemove` for the served guild
forgets them in one transaction. A leave event from any other server is
ignored.

**A second copy of the bot starts.** It opens the store, fails to bind the
health port, and exits. It never identifies, so the copy already serving the
server keeps serving it.

**Somebody reorders an options array.** The validator names the command, the
option and the rule, the boot stops, and no registration is sent.

**A card grows past a limit.** It is clamped on a whole-line boundary and says
how much was left out; a payload whose truncated form would still read as
complete is refused with a sentence instead.

## Error Cases

| Error | When | What happens |
|-------|------|--------------|
| ``SurfaceConfigurationError/missing(key:why:)`` | A required variable is unset or blank | Boot refuses, naming the variable and why it is needed. |
| ``SurfaceConfigurationError/placeholder(key:value:)`` | A value was copied out of an example file | Boot refuses rather than pointing the bot at a stranger's server (`ADOPT-7.a`). |
| ``SurfaceConfigurationError/invalid(key:value:why:)`` | A server id that is not digits, a port out of range, the two ports the same, a portal URL with no host | Boot refuses, naming the variable. |
| ``CommandCatalogInvalid`` | A catalogue breaks a rule Discord enforces | Boot refuses, listing every issue with its path and rule. Nothing is registered. |
| ``BootError/portInUse(port:detail:)`` | A port is taken, almost always by a second copy | Boot refuses before identify. The store is closed on the way out. |
| ``BootError/storeHeld(detail:)`` | Another process holds the store | Boot refuses before any port is claimed. |
| ``BootError/sharedSecretMismatch`` | The keyed probe came back `401` | Boot refuses, rather than every `/verify` failing with a `401` nobody sees (`VERIFY-5.b`). |
| ``VerificationError/unreachable(_:)`` | The portal did not answer its health check | Boot refuses, so nobody is handed a link into nothing. |
| ``VerificationError/unexpectedStatus(expected:received:)`` | A portal answered `200` where the contract says `201` | The member is told the link could not be created and nothing about their account changed. |
| ``VerificationCallbackError/refused(_:)`` | A foreign server, a missing server, a malformed member id or a malformed account | `400` with the reason, before `200`, so a portal never records a verification this bot threw away. |
| ``VerificationCallbackError/accountBelongsToSomebodyElse(address:)`` | Another member proved this account | Refused. One account, one member, and the account is left where it is. |
| ``ListenerError`` | A socket could not be made, an address could not be parsed, a port was taken, or a bound socket would not listen | The bind step throws and the boot stops. |
| A run of failed accepts | `EINTR`, `ECONNABORTED`, `EMFILE` or a closed socket | Each is logged and retried with a doubling wait; fifty in a row exits the process so a supervisor starts a working listener. |
| A callback arrives before the store is open | The window between the bind and the boot returning | `503 starting`, so the other half retries rather than recording a verification this bot threw away. |
| A role the chat client accepted and ignored | A configured role id that is not a role here, or one above this bot's own | A line naming the ids. The API reports nothing, so this is the only record. |
| A handler's reply is over a limit | Any send | ``ReplyBounds`` clamps it, or refuses with a sentence the member can read. It never becomes a `400` after a defer. |
| An interaction arrives from another server | Any | An ephemeral refusal. Nothing is read and nothing is written. |
| A component id nobody claims | Any | An ephemeral sentence saying the button is from an older build. |

## Dependencies

- `Store` for the member directory, the accounts and the lease.
- `Gating` for the token profile, the ladder, the collections, the pools and
  ``Gating/RoleRules``, which is the only thing that turns holdings into
  roles.
- `Chain` for ``Chain/WalletCheck`` and its gaps, so a partial reading is
  never a number.
- `DiscordBM`, in `SurfaceDiscord` alone. It is the one new entry in
  `Package.resolved` this target adds directly, and what comes with it is
  listed in `docs/WHAT-IT-TALKS-TO.md` rather than estimated.

`Reserve` and `Games` are not dependencies of this surface. They join when
their commands do.

## Change Log

- **1**. First version. The gateway lifecycle, slash-command registration
  validated offline, the interaction router, the reply layer and its payload
  bounds, cards as values, and four commands: `/ping`, `/help`, `/verify` and
  `/unlink`. Corrected before release, each against a test that failed
  first: the accept loop retries instead of dying silently, connections are
  served off the cooperative pool with a timeout, the rate limit counts the
  callback route alone, an unset secret closes that route instead of
  matching an empty header, health waits for the gateway's ready event, a
  callback during boot is refused rather than dropped, `refuse` is honoured
  by the count and total bounds as well as the string ones, `/unlink` never
  turns an unread balance into a zero, a role write is read back, and a
  subcommand inside a subcommand is refused offline.
