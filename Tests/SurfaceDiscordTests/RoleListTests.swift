import Gating
import Testing

@testable import SurfaceDiscord

/// The list of role ids one decision sends to the chat service.
///
/// No socket, no token and no server: this is the arithmetic, and the
/// arithmetic is the part that took roles away from people the last time it
/// was wrong. Every decision here comes out of `RoleRules.decide` rather
/// than being built by hand, because a hand-built decision can satisfy
/// invariants the real one does not and then the test proves nothing.
@Suite("The role list that goes out")
struct RoleListTests {

    private static let bronze = "role-bronze"
    private static let silver = "role-silver"
    private static let passBadge = "role-pass"
    private static let verified = "role-verified"
    private static let handGranted = "role-moderator"

    private static let passes = "passes"
    private static let tokenAsset: UInt64 = 7001
    private static let passAsset: UInt64 = 5001

    private static func configuration() throws -> GatingConfiguration {
        try GatingConfiguration.load(from: [
            "TOKEN_ASSET_ID": "7001",
            "TOKEN_SYMBOL": "TOKEN",
            "TOKEN_NAME": "Example Token",
            "TOKEN_DECIMALS": "6",

            "TIER_1_NAME": "Bronze",
            "TIER_1_MIN": "100",
            "TIER_1_ROLE_ID": bronze,
            "TIER_2_NAME": "Silver",
            "TIER_2_MIN": "1000",
            "TIER_2_ROLE_ID": silver,

            "COLLECTION_1_ID": passes,
            "COLLECTION_1_NAME": "Passes",
            "COLLECTION_1_CREATOR": "CREATOR-PASSES",
            "COLLECTION_1_NAME_PREFIX": "Pass",
            "COLLECTION_1_ROLE_ID": passBadge,

            "VERIFIED_ROLE_ID": verified
        ])
    }

    /// A member whose balance read and whose collection count did not, which
    /// is what any caller that hands `fromChain` no catalogue produces.
    private static func partlyRead(tokens: UInt64) -> MemberHoldings {
        MemberHoldings(
            memberId: "member-1",
            isVerified: true,
            directBalance: .known(tokens * 1_000_000),
            liquidityPositions: .known([]),
            collectionCounts: [:]
        )
    }

    @Test("A role held because nobody read the fact behind it is not granted")
    func heldRolesAreNeverGranted() throws {
        let configuration = try Self.configuration()
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 20_000),
            currentRoleIds: []
        )

        // The premise: the collection went unread, so its badge is held.
        #expect(decision.held.contains(Self.passBadge))

        let sent = DiscordRoleApplier.rolesToSend(decision: decision, current: [])

        // Held means neither granted nor revoked. Sending it turns every
        // unread fact into a grant, which is ROLE-1.a exactly backwards: a
        // member nobody could look up would collect the badge for a
        // collection they have never held a piece of.
        #expect(!sent.contains(Self.passBadge))
        #expect(sent == [Self.bronze, Self.silver, Self.verified])
    }

    @Test("A badge a moderator handed out by hand survives the write")
    func handGrantedRolesSurvive() throws {
        let configuration = try Self.configuration()
        let current: Set<String> = [Self.handGranted, Self.bronze]
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 20_000),
            currentRoleIds: current
        )

        let sent = DiscordRoleApplier.rolesToSend(decision: decision, current: current)

        #expect(sent.contains(Self.handGranted))
        #expect(sent == [Self.handGranted, Self.bronze, Self.silver, Self.verified])
    }

    @Test("A rung the member sold out of is gone from the list")
    func revokedRungsAreDropped() throws {
        let configuration = try Self.configuration()
        let current: Set<String> = [Self.bronze, Self.silver, Self.verified]
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 500),
            currentRoleIds: current
        )

        let sent = DiscordRoleApplier.rolesToSend(decision: decision, current: current)

        #expect(decision.revoked == [Self.silver])
        #expect(sent == [Self.bronze, Self.verified])
    }

    @Test("A role held for an unread fact is left exactly where it was, present or absent")
    func heldRolesAreLeftAlone() throws {
        let configuration = try Self.configuration()
        // The same member twice, differing only in whether they already hold
        // the badge whose collection nobody read. Held has to mean "as it
        // was" in both directions, which one example on its own cannot show.
        let withBadge: Set<String> = [Self.passBadge]
        let withDecision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 20_000),
            currentRoleIds: withBadge
        )
        let withoutDecision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 20_000),
            currentRoleIds: []
        )

        #expect(DiscordRoleApplier.rolesToSend(decision: withDecision, current: withBadge)
            .contains(Self.passBadge))
        #expect(!DiscordRoleApplier.rolesToSend(decision: withoutDecision, current: [])
            .contains(Self.passBadge))
    }

    @Test("Nothing outside the managed set is invented from the decision alone")
    func onlyManagedRolesComeFromTheDecision() throws {
        let configuration = try Self.configuration()
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: Self.partlyRead(tokens: 20_000),
            currentRoleIds: []
        )

        let sent = DiscordRoleApplier.rolesToSend(decision: decision, current: [])

        // Everything sent is either managed and wanted, or a role the member
        // already had. Nothing else may appear.
        #expect(sent.subtracting(decision.managed).isEmpty)
    }
}
