import Foundation
import Testing
@testable import Gating

/// The whole configuration read in one go, the way a boot reads it.
@Suite("Gating configuration")
struct GatingConfigurationTests {

    // MARK: - One pass over the environment

    @Test("An operator's whole server is read from their own variables")
    func loadsEverything() throws {
        let configuration = try Fixture.configuration()
        #expect(configuration.token.symbol == "TOKEN")
        #expect(configuration.token.decimals == 6)
        #expect(configuration.ladder.rungs.count == 3)
        #expect(configuration.collections.collections.count == 2)
        #expect(configuration.pools.pools.count == 2)
        #expect(configuration.verifiedRoleId == Fixture.verified)
        #expect(configuration.admins.accounts == ["ADMIN-ONE"])
    }

    @Test("Every role the bot may ever touch is knowable before it touches one")
    func allRoleIds() throws {
        let configuration = try Fixture.configuration()
        #expect(configuration.allRoleIds == [
            Fixture.bronze, Fixture.silver, Fixture.gold,
            Fixture.passBadge, Fixture.palOne, Fixture.palTen, Fixture.palFifty,
            Fixture.poolBadge, Fixture.providerBadge, Fixture.verified
        ])
    }

    @Test("The token is read before the ladder, because the ladder cannot be read without it")
    func tokenFirst() throws {
        // Reading the rungs first is how a module ends up assuming a
        // precision: there is nothing else to convert a threshold with.
        do {
            _ = try GatingConfiguration.load(from: Fixture.environment(removing: ["TOKEN_DECIMALS"]))
            Issue.record("a precision appeared out of nowhere")
        } catch let error as GatingConfigurationError {
            guard case .missing(let key, _) = error else {
                Issue.record("refused for the wrong reason: \(error)")
                return
            }
            #expect(key == "TOKEN_DECIMALS")
        }
    }

    @Test("Each pool is given the token the operator named, once")
    func poolsShareTheOneTokenId() throws {
        let configuration = try Fixture.configuration(overriding: ["TOKEN_ASSET_ID": "4242"])
        #expect(configuration.token.assetId == 4_242)
        #expect(configuration.pools.pools.allSatisfy { $0.tokenAssetId == 4_242 })
    }

    @Test("A server that gates on a balance alone needs no collections and no pools")
    func ladderOnly() throws {
        let configuration = try GatingConfiguration.load(from: [
            "TOKEN_ASSET_ID": "7001",
            "TOKEN_SYMBOL": "TOKEN",
            "TOKEN_DECIMALS": "0",
            "TIER_1_NAME": "Member",
            "TIER_1_MIN": "1",
            "TIER_1_ROLE_ID": "role-member"
        ])
        #expect(configuration.collections.isEmpty)
        #expect(configuration.pools.isEmpty)
        #expect(configuration.admins.isEmpty)
        #expect(configuration.allRoleIds == ["role-member"])

        // And it still decides roles.
        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: MemberHoldings(
                memberId: "member-1",
                directBalance: .known(5),
                liquidityPositions: .known([])
            ),
            currentRoleIds: []
        )
        #expect(decision.granted == ["role-member"])
    }

    @Test("A rung's role is found by the rung's id, so renaming a rung keeps its role")
    func roleLookupByRungId() throws {
        let configuration = try Fixture.configuration()
        let bronze = try #require(configuration.ladder.rung(id: "bronze"))
        #expect(configuration.roleId(for: bronze) == Fixture.bronze)

        let renamed = try Fixture.configuration(overriding: [
            "TIER_1_NAME": "Copper",
            "TIER_1_ID": "bronze"
        ])
        let copper = try #require(renamed.ladder.rung(id: "bronze"))
        #expect(copper.name == "Copper")
        #expect(renamed.roleId(for: copper) == Fixture.bronze)
    }
}
