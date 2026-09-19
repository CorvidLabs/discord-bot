import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// The one description of every variable this build reads.
///
/// TRUST-1 is that the list of what this asks for can be read rather than
/// discovered by running it, and ADOPT-9 is that an operator reads back what
/// the bot made of their settings. Both rest on this list being complete, so
/// the suite checks completeness rather than taking it on trust.
@Suite("Every variable, described exactly once")
internal struct SettingsCatalogueTests {

    // MARK: - Completeness

    @Test("Every variable a full load reads is described (TRUST-1)")
    internal func everyVariableReadIsDescribed() throws {
        let settings = Fixture.settings(extras: [
            "COLLECTION_1_ID": "pieces",
            "COLLECTION_1_CREATOR": "CREATOR-ACCOUNT",
            "COLLECTION_1_ROLE_ID": "role-pieces",
            "COLLECTION_1_COUNT_1_MIN": "5",
            "COLLECTION_1_COUNT_1_ROLE_ID": "role-five",
            "POOL_1_ID": "pool",
            "POOL_1_LP_ASA": "5150",
            "POOL_1_PAIRED_ASA": "7007",
            "POOL_1_DECIMALS": "6",
            "ADMIN_WALLET_1": "ADMIN-ACCOUNT",
            "TOKEN_LINK_1_LABEL": "Explorer",
            "TOKEN_LINK_1_URL": "https://explorer.example"
        ])
        let loaded = try LoadedConfiguration.load(settings)
        let undescribed = loaded.keysRead.filter { SettingsCatalogue.entry(for: $0) == nil }
        #expect(undescribed.sorted() == [])
    }

    @Test("A key read and not described fails the boot with the internal code (RT-006)")
    internal func undescribedKeyIsAnInternalError() {
        // The audit is what the boot runs, so the case is exercised through
        // it rather than through a loader that would have to be edited to
        // produce it.
        let audit = SettingsAudit.of(
            settings: Fixture.settings(),
            keysRead: ["SOMETHING_NOBODY_DESCRIBED"]
        )
        #expect(audit.undescribed == ["SOMETHING_NOBODY_DESCRIBED"])
        #expect(audit.refusal?.code == .internalError)
        #expect(audit.refusal?.variable == "SOMETHING_NOBODY_DESCRIBED")
    }

    // MARK: - Shape

    @Test("Names come from the constants that own them, so a rename cannot orphan one")
    internal func namesComeFromTheConstants() {
        let patterns = SettingsCatalogue.entries.map(\.pattern)
        #expect(patterns.contains(TokenProfile.assetIdKey))
        #expect(patterns.contains(TokenProfile.decimalsKey))
        #expect(patterns.contains(ChainEnvironment.nodeURL))
        #expect(patterns.contains(GatingConfiguration.verifiedRoleKey))
        #expect(patterns.contains(LiquidityConfiguration.providerRoleKey))
        #expect(patterns.contains(TierConfiguration.unrankedNameKey))
        #expect(patterns.contains(RuntimeEnvironment.storePath))
    }

    @Test("A numbered family is one entry, not thirty-two")
    internal func familiesAreOneEntry() {
        let ladderEntries = SettingsCatalogue.entries.filter { $0.pattern.hasPrefix("TIER_") }
        #expect(ladderEntries.count == 7)
        #expect(SettingsCatalogue.entry(for: "TIER_7_MIN")?.pattern == "TIER_#_MIN")
        #expect(SettingsCatalogue.entry(for: "TIER_31_ROLE_ID")?.pattern == "TIER_#_ROLE_ID")
    }

    @Test("A family with two numbers in it matches both")
    internal func nestedFamiliesMatch() {
        #expect(
            SettingsCatalogue.entry(for: "COLLECTION_2_COUNT_3_ROLE_ID")?.pattern
                == "COLLECTION_#_COUNT_#_ROLE_ID"
        )
        #expect(SettingsCatalogue.entry(for: "COLLECTION_2_COUNT_ROLE_ID") == nil)
        #expect(SettingsCatalogue.entry(for: "COLLECTION_2_COUNT_3_ROLE_IDS") == nil)
    }

    @Test("No two entries describe the same variable")
    internal func entriesDoNotOverlap() {
        let samples = [
            "TOKEN_ASSET_ID", "TOKEN_LINK_1_URL", "TIER_1_NAME", "TIER_UNRANKED_NAME",
            "COLLECTION_1_ID", "COLLECTION_1_COUNT_1_MIN", "POOL_1_ID", "ADMIN_WALLET_1",
            "CHAIN_NODE_URL", "STORE_PATH", "HEALTH_PORT", "HEALTH_ADDRESS"
        ]
        for name in samples {
            let matching = SettingsCatalogue.entries.filter { $0.matches(name) }
            #expect(matching.count == 1, "\(name) is described \(matching.count) times")
        }
    }

    // MARK: - No money switch

    @Test("No variable exists whose effect is to stop money moving (BUILD-3.a)")
    internal func noMoneySwitch() {
        // The bot this was ported from carries a note in its own
        // documentation saying its test mode is not a money switch. A project
        // that has to carry such a note has already failed to say so in
        // software, so the variable does not exist here and this is what
        // stops one arriving by accident.
        let forbidden = ["TEST_MODE", "DRY_RUN", "SAFE_MODE", "READ_ONLY", "NO_SEND"]
        for name in forbidden {
            #expect(SettingsCatalogue.entry(for: name) == nil, "\(name) is in the catalogue")
        }
    }

    @Test("Exactly one variable is a secret, and it is the node's token")
    internal func oneSecret() {
        let secrets = SettingsCatalogue.entries.filter { $0.secrecy == .secret }
        #expect(secrets.map(\.pattern) == [ChainEnvironment.apiToken])
    }

    @Test("Every required variable is one the fixture sets, so the fixture is complete")
    internal func requiredSetMatchesTheFixture() {
        // A family's first member, because that is what a required family
        // means: `TIER_#_NAME` required is `TIER_1_NAME` required.
        let required = SettingsCatalogue.entries
            .filter { $0.requirement == .required }
            .map { $0.pattern.replacingOccurrences(of: "#", with: "1") }
            .sorted()
        #expect(required == Fixture.requiredNames.sorted())
    }

    @Test("Every variable the catalogue marks required is one a boot actually refuses without")
    internal func requiredIsWhatTheLoadersRefuseWithout() throws {
        // The listing is where an operator finds out what is still missing
        // (RT-026), so a variable marked optional that the loaders demand
        // sends them round again for each one. Asserted against the loaders
        // rather than against the fixture, which is the direction that can
        // fail.
        for name in Fixture.requiredNames {
            #expect(throws: (any Error).self, "\(name) loaded without being set") {
                try LoadedConfiguration.load(Fixture.settings(extras: [name: nil]))
            }
        }
        // And the other direction: nothing marked optional is in fact
        // demanded. One sample per optional family would be a long test, so
        // the complete fixture standing on its own is the check: it sets
        // every required variable and nothing else.
        #expect(throws: Never.self) {
            try LoadedConfiguration.load(Fixture.settings())
        }
    }
}
