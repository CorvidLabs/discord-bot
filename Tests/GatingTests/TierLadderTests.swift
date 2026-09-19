import Foundation
import Testing
@testable import Gating

/// The ladder itself: which rung a balance reaches, and the three ways of
/// not being on one.
@Suite("Tier ladder")
struct TierLadderTests {

    private static func ladder() throws -> TierLadder {
        try TierConfiguration.load(from: Fixture.environment(), token: try Fixture.token()).ladder
    }

    // MARK: - No rung is not the same as no reading

    @Test("Somebody below the bottom rung is on no rung, and asking says so")
    func belowTheBottomRung() throws {
        let ladder = try Self.ladder()

        // This is the assertion the original could not make. Its no-rung case
        // was a `Tier` value with the id `none`, so `tier == .none` compiled,
        // resolved to `Optional.none`, and was always false. Four of those
        // shipped, every one of them warned about, none of them read. Here
        // the no-rung case *is* the optional, so the obvious comparison is
        // the correct one.
        #expect(ladder.tier(for: 0) == nil)
        #expect(ladder.tier(for: Fixture.whole(99)) == nil)
        #expect(ladder.tier(for: Fixture.whole(100))?.id == "bronze")
    }

    @Test("A balance nobody read is not a member who holds nothing")
    func unreadIsNotUnranked() throws {
        let ladder = try Self.ladder()

        #expect(ladder.standing(for: .known(0)) == .unranked)
        #expect(ladder.standing(for: .unknown) == .unread)
        #expect(ladder.standing(for: .known(0)) != ladder.standing(for: .unknown))

        // Both of these have no rung, and they are still not interchangeable:
        // one takes the roles away, the other leaves them alone.
        #expect(TierStanding.unranked.tier == nil)
        #expect(TierStanding.unread.tier == nil)
        #expect(TierStanding.unranked.wasRead)
        #expect(TierStanding.unread.wasRead == false)
    }

    @Test("The rung somebody reaches is the highest one they can afford")
    func highestRungWins() throws {
        let ladder = try Self.ladder()
        #expect(ladder.standing(for: .known(Fixture.whole(100))) == .on(try #require(ladder.rung(id: "bronze"))))
        #expect(ladder.standing(for: .known(Fixture.whole(9_999)))
            == .on(try #require(ladder.rung(id: "silver"))))
        #expect(ladder.standing(for: .known(Fixture.whole(10_000)))
            == .on(try #require(ladder.rung(id: "gold"))))
    }

    // MARK: - Stacking

    @Test("Somebody on the top rung keeps the ones underneath it")
    func rungsStack() throws {
        let ladder = try Self.ladder()
        #expect(ladder.rungsToAssign(for: Fixture.whole(10_000)).map(\.id) == ["bronze", "silver", "gold"])
        #expect(ladder.rungsToAssign(for: Fixture.whole(1_000)).map(\.id) == ["bronze", "silver"])
        #expect(ladder.rungsToAssign(for: 0).isEmpty)

        let silver = try #require(ladder.rung(id: "silver"))
        #expect(ladder.rungsToAssign(upTo: silver).map(\.id) == ["bronze", "silver"])
    }

    @Test("Rungs written out of order are still a ladder")
    func rungsSortThemselves() {
        let ladder = TierLadder(rungs: [
            Tier(id: "high", name: "High", minimumBaseUnits: 300),
            Tier(id: "low", name: "Low", minimumBaseUnits: 100),
            Tier(id: "mid", name: "Mid", minimumBaseUnits: 200)
        ])
        #expect(ladder.rungs.map(\.id) == ["low", "mid", "high"])
        #expect(ladder.tier(for: 250)?.id == "mid")
    }

    @Test("A server with no ladder at all is a configuration, not a crash")
    func emptyLadder() {
        let ladder = TierLadder(rungs: [])
        #expect(ladder.tier(for: UInt64.max) == nil)
        #expect(ladder.standing(for: .known(UInt64.max)) == .unranked)
        #expect(ladder.rungsToAssign(for: UInt64.max).isEmpty)
    }

    // MARK: - Reading a row somebody else wrote

    @Test("A row that stored the rung's display name still finds the rung (ROLE-1.c)")
    func storedNamesStillResolve() throws {
        let ladder = try Self.ladder()
        // Rows written by an earlier version stored the name, not the id.
        // Reading those as no rung would demote the whole server on the first
        // sweep after an upgrade.
        #expect(ladder.storedRung("Silver")?.id == "silver")
        #expect(ladder.storedRung("silver")?.id == "silver")
        #expect(ladder.storedRung("SILVER")?.id == "silver")
        #expect(ladder.storedRung("Platinum") == nil)
    }

    @Test("A card shows the operator's own word for holding too little")
    func unrankedIsNamed() throws {
        let ladder = try TierConfiguration.load(
            from: Fixture.environment(overriding: [
                "TIER_UNRANKED_NAME": "Guest",
                "TIER_UNRANKED_EMOJI": "[g]"
            ]),
            token: try Fixture.token()
        ).ladder
        #expect(ladder.unrankedName == "Guest")
        #expect(ladder.unrankedEmoji == "[g]")
    }

    @Test("A rung shows its emoji when it has one and just its name when it has not")
    func displayName() throws {
        let ladder = try Self.ladder()
        #expect(try #require(ladder.rung(id: "bronze")).display == "[b] Bronze")
        #expect(try #require(ladder.rung(id: "silver")).display == "Silver")
    }
}
