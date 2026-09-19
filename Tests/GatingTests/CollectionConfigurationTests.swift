import Foundation
import Testing
@testable import Gating

/// As many collections as a server has, each saying for itself what holding
/// one earns (ADOPT-1.b).
@Suite("Collection catalogue")
struct CollectionConfigurationTests {

    // MARK: - Any number of collections

    @Test("A server brings its own collections, and there are not two of them by default")
    func collectionsAreConfiguration() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())
        #expect(catalog.collections.map(\.id) == [Fixture.passes, Fixture.pals])
        #expect(catalog.collection(id: Fixture.passes)?.displayName == "Passes")

        let none = try CollectionConfiguration.load(from: [:])
        #expect(none.isEmpty)
        #expect(none.allRoleIds.isEmpty)
    }

    @Test("A third collection needs no code, only a third set of variables")
    func aThirdCollection() throws {
        let catalog = try CollectionConfiguration.load(
            from: Fixture.environment(overriding: [
                "COLLECTION_3_ID": "relics",
                "COLLECTION_3_CREATOR": "CREATOR-RELICS",
                "COLLECTION_3_ROLE_ID": "role-relic"
            ])
        )
        #expect(catalog.collections.count == 3)
        #expect(catalog.collection(id: "relics")?.roleId == "role-relic")
        // Its display name falls back to its id, which is the operator's
        // word either way.
        #expect(catalog.collection(id: "relics")?.displayName == "relics")
    }

    @Test("A mistyped collection number drops it and the ones above it")
    func firstGapEndsTheCatalog() throws {
        let catalog = try CollectionConfiguration.load(
            from: Fixture.environment(overriding: [
                "COLLECTION_4_ID": "relics",
                "COLLECTION_4_CREATOR": "CREATOR-RELICS"
            ])
        )
        #expect(catalog.collections.map(\.id) == [Fixture.passes, Fixture.pals])
    }

    // MARK: - The creator is required

    @Test("A collection with no minting account is refused, because there is no default creator")
    func creatorIsRequired() throws {
        // The original filled this in from a literal account written into the
        // source, so a server that never set it granted roles for holding
        // another project's art.
        do {
            _ = try CollectionConfiguration.load(
                from: Fixture.environment(removing: ["COLLECTION_1_CREATOR"])
            )
            Issue.record("a creator appeared out of nowhere")
        } catch let error as GatingConfigurationError {
            guard case .missing(let key, _) = error else {
                Issue.record("refused for the wrong reason: \(error)")
                return
            }
            #expect(key == "COLLECTION_1_CREATOR")
        }
    }

    @Test("Two collections with one id are refused")
    func duplicateIdRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateId(
                id: Fixture.passes,
                first: "COLLECTION_1_ID",
                second: "COLLECTION_2_ID"
            )
        ) {
            try CollectionConfiguration.load(
                from: Fixture.environment(overriding: ["COLLECTION_2_ID": "Passes"])
            )
        }
    }

    // MARK: - Recognising a piece

    @Test("A piece belongs to the collection whose rules it satisfies, and to no other")
    func matching() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())

        #expect(
            catalog.match(creator: "CREATOR-PASSES", name: "Pass 17", unitName: nil, total: 1)?.id
                == Fixture.passes
        )
        #expect(
            catalog.match(creator: "CREATOR-PALS", name: "Anything", unitName: "pal", total: 1)?.id
                == Fixture.pals
        )
        // Right creator, wrong name.
        #expect(catalog.match(creator: "CREATOR-PASSES", name: "Something", unitName: nil, total: 1) == nil)
        // Right creator, wrong unit name.
        #expect(catalog.match(creator: "CREATOR-PALS", name: "Pal 1", unitName: "coin", total: 1) == nil)
        // Nobody's creator.
        #expect(catalog.match(creator: "CREATOR-OTHER", name: "Pass 1", unitName: nil, total: 1) == nil)
    }

    @Test("A creator's fungible token is not one of their pieces, however much of it somebody holds")
    func supplyOfOne() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())
        #expect(catalog.match(creator: "CREATOR-PASSES", name: "Pass token", unitName: nil, total: 1_000) == nil)
        #expect(catalog.match(creator: "CREATOR-PASSES", name: "Pass 1", unitName: nil, total: 1) != nil)
    }

    @Test("A collection minted as editions is configuration, not a collection that matches nothing")
    func editionsCollection() throws {
        // Twenty-five of each piece is an ordinary way to mint. Nothing in
        // this operator's configuration is wrong, so a supply rule written
        // into the source would count them zero pieces and take every one of
        // their collection roles away with nothing said.
        let catalog = try CollectionConfiguration.load(
            from: Fixture.environment(overriding: ["COLLECTION_1_MAX_SUPPLY": "25"])
        )
        #expect(
            catalog.match(creator: "CREATOR-PASSES", name: "Pass 17", unitName: nil, total: 25)?.id
                == Fixture.passes
        )
        #expect(
            catalog.match(creator: "CREATOR-PASSES", name: "Pass 17", unitName: nil, total: 1)?.id
                == Fixture.passes
        )
        // Still not the creator's fungible token.
        #expect(catalog.match(creator: "CREATOR-PASSES", name: "Pass token", unitName: nil, total: 26) == nil)

        // And a collection that set nothing is 1-of-1 pieces, as before.
        let plain = try CollectionConfiguration.load(from: Fixture.environment())
        #expect(plain.collection(id: Fixture.passes)?.maxSupply == 1)
        #expect(plain.match(creator: "CREATOR-PASSES", name: "Pass 17", unitName: nil, total: 25) == nil)
    }

    @Test("A supply ceiling of nothing is refused, because nothing could ever match it")
    func zeroMaxSupplyRefused() throws {
        #expect(throws: GatingConfigurationError.zeroSupply(key: "COLLECTION_1_MAX_SUPPLY")) {
            try CollectionConfiguration.load(
                from: Fixture.environment(overriding: ["COLLECTION_1_MAX_SUPPLY": "0"])
            )
        }
    }

    @Test("Match rules ignore case, because an operator types a prefix the way they say it")
    func matchingIgnoresCase() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())
        #expect(catalog.match(creator: "CREATOR-PASSES", name: "PASS 9", unitName: nil, total: 1) != nil)
        #expect(catalog.match(creator: "CREATOR-PALS", name: nil, unitName: "PAL", total: 1) != nil)
    }

    // MARK: - Count rungs

    @Test("Holding more pieces earns more roles, and keeps the ones underneath")
    func countRungsStack() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())
        let pals = try #require(catalog.collection(id: Fixture.pals))

        #expect(pals.rungsToAssign(count: 0).isEmpty)
        #expect(pals.rungsToAssign(count: 1).map(\.roleId) == [Fixture.palOne])
        #expect(pals.rungsToAssign(count: 49).map(\.roleId) == [Fixture.palOne, Fixture.palTen])
        #expect(
            pals.rungsToAssign(count: 500).map(\.roleId)
                == [Fixture.palOne, Fixture.palTen, Fixture.palFifty]
        )
    }

    @Test("Count rungs written out of order are still a ladder")
    func countRungsSort() throws {
        let catalog = try CollectionConfiguration.load(
            from: Fixture.environment(overriding: [
                "COLLECTION_2_COUNT_1_MIN": "50",
                "COLLECTION_2_COUNT_1_ROLE_ID": Fixture.palFifty,
                "COLLECTION_2_COUNT_3_MIN": "1",
                "COLLECTION_2_COUNT_3_ROLE_ID": Fixture.palOne
            ])
        )
        let pals = try #require(catalog.collection(id: Fixture.pals))
        #expect(pals.countRungs.map(\.minimumCount) == [1, 10, 50])
    }

    @Test("A count rung with no role to grant is refused rather than doing nothing quietly")
    func countRungNeedsARole() throws {
        do {
            _ = try CollectionConfiguration.load(
                from: Fixture.environment(removing: ["COLLECTION_2_COUNT_2_ROLE_ID"])
            )
            Issue.record("a rung that grants nothing was accepted")
        } catch let error as GatingConfigurationError {
            guard case .missing(let key, _) = error else {
                Issue.record("refused for the wrong reason: \(error)")
                return
            }
            #expect(key == "COLLECTION_2_COUNT_2_ROLE_ID")
        }
    }

    @Test("A count rung anybody reaches, or one written twice, is refused")
    func countRungRefusals() throws {
        #expect(throws: GatingConfigurationError.zeroMinimum(key: "COLLECTION_2_COUNT_1_MIN")) {
            try CollectionConfiguration.load(
                from: Fixture.environment(overriding: ["COLLECTION_2_COUNT_1_MIN": "0"])
            )
        }
        #expect(
            throws: GatingConfigurationError.duplicateMinimum(
                minimum: 1,
                first: "COLLECTION_2_COUNT_1_MIN",
                second: "COLLECTION_2_COUNT_2_MIN"
            )
        ) {
            try CollectionConfiguration.load(
                from: Fixture.environment(overriding: ["COLLECTION_2_COUNT_2_MIN": "1"])
            )
        }
    }

    @Test("A mistyped count rung number drops it and the ones above it")
    func countRungGap() throws {
        let catalog = try CollectionConfiguration.load(
            from: Fixture.environment(removing: ["COLLECTION_2_COUNT_2_MIN", "COLLECTION_2_COUNT_2_ROLE_ID"])
        )
        let pals = try #require(catalog.collection(id: Fixture.pals))
        #expect(pals.countRungs.map(\.minimumCount) == [1])
    }

    @Test("Every role a collection can grant is known without asking the chain")
    func rolesAreKnowable() throws {
        let catalog = try CollectionConfiguration.load(from: Fixture.environment())
        #expect(catalog.allRoleIds == [
            Fixture.passBadge, Fixture.palOne, Fixture.palTen, Fixture.palFifty
        ])
    }
}
