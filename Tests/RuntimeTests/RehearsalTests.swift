import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// The role rules, run against the operator's own configuration, with nothing
/// installed.
///
/// A contributor with a laptop and no keys should be able to watch the thing
/// work (BUILD-1.b). It invents members and holdings only, never
/// configuration, so what they watch is their own ladder rather than somebody
/// else's (ADOPT-6.a).
@Suite("Rehearsing the rules")
internal struct RehearsalTests {

    // MARK: - It is the operator's own configuration

    @Test("The rungs rehearsed are the operator's own, not invented ones (ADOPT-6.a)")
    internal func rungsAreTheOperatorsOwn() async {
        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(.rehearse, settings: Fixture.settings())
        #expect(result.exitCode == .ok)

        let printed = await output.outText
        #expect(printed.contains("Standing: Bronze") || printed.contains("Standing: Silver"))
        #expect(printed.contains("role-bronze"))
        // Nothing from anywhere else.
        #expect(!printed.contains("Gold"))
        #expect(!printed.contains("Platinum"))
    }

    @Test("A different ladder rehearses differently, because nothing here is hard coded")
    internal func aDifferentLadderRehearsesDifferently() throws {
        let configuration = try LoadedConfiguration.load(
            Fixture.settings(extras: [
                "TIER_1_NAME": "Sprout",
                "TIER_1_ROLE_ID": "role-sprout",
                "TIER_2_NAME": nil,
                "TIER_2_MIN": nil,
                "TIER_2_ROLE_ID": nil
            ])
        )
        let text = Rehearsal.report(configuration: configuration.gating)
            .flatMap(\.lines)
            .joined(separator: "\n")
        #expect(text.contains("Sprout"))
        #expect(text.contains("role-sprout"))
        #expect(!text.contains("Bronze"))
    }

    // MARK: - What it shows

    @Test("The member nobody could read is shown as unread, not as holding nothing (ROLE-1.a)")
    internal func unreadIsNotEmpty() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let sections = Rehearsal.report(configuration: configuration.gating)
        let unread = try #require(
            sections.first { $0.title.contains("had their balance go unread") }
        )
        let text = unread.lines.joined(separator: "\n")
        #expect(text.contains("Standing: nobody read it, which is not the bottom of the ladder"))
        #expect(text.contains("Revokes: nothing"))
        #expect(text.contains("could not be read"))
    }

    @Test("A member who holds nothing, read, does lose the rungs")
    internal func readAndEmptyRevokes() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let holdings = MemberHoldings(
            memberId: "member",
            isVerified: true,
            directBalance: .known(0),
            liquidityPositions: .known([]),
            collectionCounts: [:]
        )
        let decision = RoleRules.decide(
            configuration: configuration.gating,
            holdings: holdings,
            currentRoleIds: ["role-bronze", "role-silver"]
        )
        #expect(decision.revoked == ["role-bronze", "role-silver"])
        #expect(decision.standing == .unranked)
    }

    @Test("A pool member is only rehearsed when the operator has pools")
    internal func poolsOnlyWhenConfigured() throws {
        let without = try LoadedConfiguration.load(Fixture.settings())
        #expect(
            !Rehearsal.members(configuration: without.gating)
                .contains { $0.0.contains("position in every pool") }
        )
        let with = try LoadedConfiguration.load(
            Fixture.settings(extras: [
                "POOL_1_ID": "pool",
                "POOL_1_LP_ASA": "5150",
                "POOL_1_PAIRED_ASA": "7007",
                "POOL_1_DECIMALS": "6",
                "POOL_1_ROLE_ID": "role-pool"
            ])
        )
        #expect(
            Rehearsal.members(configuration: with.gating)
                .contains { $0.0.contains("position in every pool") }
        )
    }

    // MARK: - It touches nothing

    @Test("rehearse opens no file and makes no request")
    internal func rehearseTouchesNothing() async {
        let output = RecordingOutput()
        let result = await Runtime(
            seams: Fixture.seams(
                output: output,
                store: RefusingStoreOpener(.unusable(path: "x", reason: "nobody should open this")),
                chain: StubChainSource(failure: ChainError.network("nobody should ask"))
            )
        ).execute(
            .rehearse,
            settings: Fixture.settings(storePath: "/nonexistent-\(UUID().uuidString)/store.db")
        )
        #expect(result.exitCode == .ok)
        let printed = await output.outText
        #expect(!printed.contains("nobody should open this"))
        #expect(printed.contains("Nothing was read, nothing was written"))
    }

    @Test("rehearse refuses on a bad configuration, naming the variable")
    internal func rehearseRefusesOnBadConfiguration() async {
        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(.rehearse, settings: Settings([:]))
        #expect(result.exitCode == .configuration)
        let errors = await output.errorText
        #expect(errors.contains(TokenProfile.assetIdKey))
    }
}
