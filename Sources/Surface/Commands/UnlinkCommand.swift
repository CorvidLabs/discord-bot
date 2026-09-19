@preconcurrency import Foundation
import Gating
import Store

/// `/unlink`: stop being tracked.
///
/// `VERIFY-3` is the want, and it is the small version of leaving: a member
/// who wants out can get out. `VERIFY-7` is the large version, and the rule
/// that connects them is here: removing the **last** account forgets the
/// member entirely, and removing one of several does not.
///
/// Two steps rather than one required option. With no account named it lists
/// what the member has and changes nothing; with one named it removes that
/// one. The alternative, a required option, would mean a member has to know
/// the address before they can ask what their addresses are.
///
/// Roles are re-decided afterwards rather than assumed. Somebody who unlinks
/// one of three accounts may still be on the same rung, and stripping first
/// and re-granting later is a promotion and a demotion in the member's
/// notifications for a change that did nothing.
public struct UnlinkCommand: CommandHandler {

    // MARK: - Properties

    public let name = CommandCatalog.unlink

    /// The one server this process serves.
    private let guildId: String

    /// What the operator configured.
    private let configuration: GatingConfiguration

    /// Where members and accounts are kept.
    private let store: any BotStore

    /// How a decision reaches the chat client.
    private let roles: any RoleApplier

    /// The other half, or nil when verification is off.
    private let verification: (any VerificationClient)?

    /// The words and colours this operator set.
    private let chrome: CardChrome

    // MARK: - Initializers

    /// - Parameters:
    ///   - guildId: The one server this process serves.
    ///   - configuration: What the operator configured.
    ///   - store: Where members and accounts are kept.
    ///   - roles: How a decision reaches the chat client.
    ///   - verification: The other half, or nil.
    ///   - chrome: The words and colours this operator set.
    public init(
        guildId: String,
        configuration: GatingConfiguration,
        store: any BotStore,
        roles: any RoleApplier,
        verification: (any VerificationClient)?,
        chrome: CardChrome
    ) {
        self.guildId = guildId
        self.configuration = configuration
        self.store = store
        self.roles = roles
        self.verification = verification
        self.chrome = chrome
    }

    // MARK: - Public Methods

    public func handle(_ request: InteractionRequest) async -> SurfaceReply {
        let found = try? await store.member(externalId: request.userExternalId)
        guard let member = found ?? nil else {
            return .refuse("You have not proved an account here, so there is nothing to unlink.")
        }
        guard let accounts = try? await store.accounts(memberKey: member.key), !accounts.isEmpty else {
            return .refuse("You have not proved an account here, so there is nothing to unlink.")
        }

        guard let asked = request.string(CommandCatalog.unlinkAccountOption) else {
            return .followUp(VisibleMessage(
                card: Self.listCard(chrome: chrome, accounts: accounts.map(\.address)),
                isEphemeral: true
            ))
        }

        guard let match = Self.match(asked, in: accounts.map(\.address)) else {
            let listed = ReplyLimits.joinWithinLimit(
                accounts.map { "`\(Self.shorten($0.address))`" },
                limit: ReplyLimits.messageContent - 120,
                separator: ", "
            )
            return .refuse("No account of yours matches that. You have: \(listed)")
        }

        do {
            try await store.unlink(address: match)
        } catch {
            return .refuse("That could not be removed just now. Nothing changed; try again shortly.")
        }

        // Read again rather than subtracting the removed one from the list
        // read before the removal. Two `/unlink` calls naming different
        // accounts each see the other's account still present in a stale
        // list, so neither is holding the last one and the member is left
        // with a record and nothing in it.
        let reread = try? await store.accounts(memberKey: member.key)
        let remaining = (reread ?? accounts.filter { $0.address != match }).map(\.address)

        var forgotten = false
        if let reread, reread.isEmpty {
            // Only when nothing is left, and only on a read that worked. A
            // member with a second account has not left, and a store that
            // could not be read is not an empty one.
            forgotten = ((try? await store.forget(memberKey: member.key)) != nil)
        }

        // Best effort, and deliberately not fatal. The local removal is what
        // the member asked for; a portal that did not answer must not turn
        // their request to leave into an error message. It is still worth
        // trying, because leaving a live session there is how an unlinked
        // member keeps whatever that session opened.
        try? await verification?.deleteSession(externalId: request.userExternalId, guildId: guildId)

        let roleNote = await reapplyRoles(
            externalId: request.userExternalId,
            memberKey: member.key,
            remaining: reread
        )

        return .followUp(VisibleMessage(
            card: Self.removedCard(
                chrome: chrome,
                removed: match,
                remaining: remaining,
                forgotten: forgotten,
                roleNote: roleNote
            ),
            isEphemeral: true
        ))
    }

    /// The card that lists what a member has, and changes nothing.
    ///
    /// - Parameters:
    ///   - chrome: The words and colours this operator set.
    ///   - accounts: Their accounts.
    public static func listCard(chrome: CardChrome, accounts: [String]) -> SurfaceCard {
        // Full addresses overran the field limit in the original at fourteen
        // accounts, on the one screen whose job is to tell somebody what to
        // type next.
        let lines = accounts.enumerated().map { index, address in
            "\(index + 1). `\(shorten(address))`"
        }
        return SurfaceCard(
            title: "Your accounts",
            description: "Nothing has been removed. Run `/unlink account:<address>` with the one "
                + "you want gone.",
            fields: [
                SurfaceField(
                    name: "Proved here (\(accounts.count))",
                    value: ReplyLimits.joinWithinLimit(lines, limit: ReplyLimits.embedFieldValue)
                )
            ],
            color: chrome.color,
            footer: "Removing your last account forgets you here."
        )
    }

    /// The card that says what was removed.
    ///
    /// - Parameters:
    ///   - chrome: The words and colours this operator set.
    ///   - removed: What was removed.
    ///   - remaining: What is left.
    ///   - forgotten: Whether the member was forgotten entirely.
    ///   - roleNote: What happened to their roles.
    public static func removedCard(
        chrome: CardChrome,
        removed: String,
        remaining: [String],
        forgotten: Bool,
        roleNote: String
    ) -> SurfaceCard {
        var fields = [
            SurfaceField(name: "Removed", value: "`\(shorten(removed))`", inline: true),
            SurfaceField(name: "Roles", value: roleNote)
        ]
        if !remaining.isEmpty {
            fields.insert(
                SurfaceField(
                    name: "Still proved (\(remaining.count))",
                    value: ReplyLimits.joinWithinLimit(
                        remaining.map { "`\(shorten($0))`" },
                        limit: ReplyLimits.embedFieldValue
                    )
                ),
                at: 1
            )
        }
        return SurfaceCard(
            title: forgotten ? "Unlinked, and forgotten" : "Account unlinked",
            description: forgotten
                ? "That was your last account here, so everything this server kept about you is gone."
                : "You still have \(remaining.count) account\(remaining.count == 1 ? "" : "s") proved here.",
            fields: fields,
            color: chrome.color,
            footer: forgotten ? "Prove one again any time with /verify." : "Use /verify to add another."
        )
    }

    // MARK: - Private Methods

    /// Which of these accounts the member meant.
    ///
    /// Exact first, then a prefix or a suffix, because every card in this
    /// package shortens an address and a member copying one off a card has
    /// the two ends of it and not the middle.
    private static func match(_ asked: String, in addresses: [String]) -> String? {
        if let exact = addresses.first(where: { $0 == asked }) { return exact }
        let candidates = addresses.filter { $0.hasPrefix(asked) || $0.hasSuffix(asked) }
        // Two matches is not a match. Guessing between them removes the wrong
        // account, which is not something a member can undo by running it
        // again.
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// An account shortened enough to recognise and not to read out.
    private static func shorten(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))\u{2026}\(address.suffix(4))"
    }

    /// Re-decides and applies this member's roles, and says what happened.
    ///
    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - memberKey: The member.
    ///   - remaining: What they still have, or nil when that could not be
    ///     read. Nil holds every role rather than deciding from a list
    ///     nobody managed to look at.
    private func reapplyRoles(
        externalId: String,
        memberKey: MemberKey,
        remaining: [AccountRecord]?
    ) async -> String {
        guard let remaining else {
            return "Could not be re-read just now, so none was changed. The next sweep will put it right."
        }
        let currentRoleIds: Set<String>
        do {
            currentRoleIds = try await roles.currentRoleIds(externalId: externalId)
        } catch {
            return "Could not be read just now, so none was changed. The next sweep will put it right."
        }

        let holdings: MemberHoldings
        if remaining.isEmpty {
            // Provably none, which is the one case where zero is the truth
            // rather than an absence of evidence.
            holdings = MemberHoldings.unlinked(memberId: memberKey.value, configuration: configuration)
        } else {
            // What is left is not re-read here: a member pressing unlink
            // should not cost a chain request per remaining account. But a
            // stored figure is only a reading when somebody took it. An
            // account proved a minute ago and never read holds `0` with no
            // `balancesReadAt`, and adding that in as a reading takes every
            // rung off somebody nobody has looked at yet (`ROLE-1.a`).
            let everyAccountWasRead = remaining.allSatisfy { $0.balancesReadAt != nil }
            // `across` rather than a sum of its own: it saturates instead of
            // wrapping, so the largest holder in the server does not land on
            // no rung at all.
            let totals = CombinedBalance.across(remaining.map(\.balance))
            holdings = MemberHoldings(
                memberId: memberKey.value,
                isVerified: true,
                directBalance: everyAccountWasRead ? totals.map(\.direct) : .unknown,
                // Not re-read, so not known. Every role the pooled half
                // decides is held rather than taken away (ROLE-1.a).
                liquidityPositions: configuration.pools.pools.isEmpty ? .known([]) : .unknown
            )
        }

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: currentRoleIds
        )
        do {
            try await roles.apply(decision, externalId: externalId)
        } catch {
            return "Could not be updated in Discord just now. The next sweep will put it right."
        }
        guard !decision.revoked.isEmpty || !decision.granted.isEmpty else {
            return "Unchanged."
        }
        return "\(decision.granted.count) granted, \(decision.revoked.count) removed."
    }
}
