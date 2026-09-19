import Chain
import Foundation
import Gating
import Store
import Testing
@testable import Sweep

/// The single most important behaviour in the sweep: a read the bot could
/// not complete is never a demotion.
///
/// Every test here holds a member who would lose roles if a failed read
/// were counted as a zero, and asserts that nothing was written and that
/// the reason is recorded as a deliberate hold rather than a failure.
@Suite("A read that did not complete never demotes")
struct NeverDemoteTests {

    @Test("A wallet nobody could read leaves every rung exactly where it was")
    func unreadableWalletHolds() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let held: Set<String> = [Fixture.bronze, Fixture.silver, Fixture.gold, Fixture.verified]
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.unreadable("WALLET-1")],
            roles: ["member-1": held]
        )

        let report = await harness.sweep.run()

        #expect(await harness.gateway.applied.isEmpty)
        #expect(await harness.gateway.rolesHeld(by: "member-1") == held)
        #expect(report.tally.held == 1)
        #expect(report.tally.changed == 0)
        #expect(report.tally.heldReasons[SweepSkipReason.factsUnread.rawValue] == 1)
        #expect(report.tally.unreadFacts["balance"] == 1)
    }

    @Test("One wallet out of two unread makes the whole member unread")
    func oneShortWalletHoldsTheMember() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1", "WALLET-2"])
        let held: Set<String> = [Fixture.gold, Fixture.silver, Fixture.bronze, Fixture.verified]
        let harness = try await Harness.build(
            members: [member],
            readings: [
                "WALLET-1": Fixture.read("WALLET-1", tokens: 0),
                "WALLET-2": Fixture.unreadable("WALLET-2")
            ],
            roles: ["member-1": held]
        )

        let report = await harness.sweep.run()

        // Three wallets out of four is a real number and it is not this
        // person's number. Counting the zero alone would strip every rung.
        #expect(await harness.gateway.applied.isEmpty)
        #expect(await harness.gateway.rolesHeld(by: "member-1") == held)
        #expect(report.tally.held == 1)
    }

    @Test("An account missing from the batch entirely is unread, not absent")
    func accountMissingFromBatchHolds() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1", "WALLET-2"])
        let held: Set<String> = [Fixture.gold, Fixture.silver, Fixture.bronze, Fixture.verified]
        let harness = try await Harness.build(
            members: [member],
            // The reader answers about one wallet and says nothing at all
            // about the other, which a `compactMap` would silently drop.
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 0)],
            roles: ["member-1": held]
        )

        let report = await harness.sweep.run()

        #expect(await harness.gateway.applied.isEmpty)
        #expect(report.tally.held == 1)
        #expect(report.tally.heldReasons[SweepSkipReason.factsUnread.rawValue] == 1)
    }

    @Test("A pool whose reserves did not load does not demote its provider")
    func shortLiquidityHolds() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let held: Set<String> = [Fixture.gold, Fixture.silver, Fixture.bronze, Fixture.verified]
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.shortLiquidity("WALLET-1", tokens: 1)],
            roles: ["member-1": held]
        )

        let report = await harness.sweep.run()

        #expect(await harness.gateway.applied.isEmpty)
        #expect(await harness.gateway.rolesHeld(by: "member-1") == held)
        #expect(report.tally.unreadFacts["liquidity-positions"] == 1)
    }

    @Test("A collection the catalogue could not answer for holds only that badge")
    func unreadCatalogueHoldsOnlyItsBadge() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            roles: ["member-1": [Fixture.passBadge]],
            registry: FailingRegistry()
        )

        let report = await harness.sweep.run()

        let decision = try #require(await harness.gateway.applied["member-1"])
        // The ladder still moved, and the badge the unread collection
        // decides was neither granted nor taken away.
        #expect(decision.granted.contains(Fixture.gold))
        #expect(decision.revoked.isEmpty)
        #expect(decision.held.contains(Fixture.passBadge))
        #expect(await harness.gateway.rolesHeld(by: "member-1").contains(Fixture.passBadge))
        #expect(report.problems.contains { $0.kind == .registryUnread })
    }

    @Test("No catalogue at all holds every collection badge and decides the rest")
    func noCatalogueHoldsBadges() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 20_000)],
            roles: ["member-1": [Fixture.passBadge]],
            registry: nil
        )

        _ = await harness.sweep.run()

        let decision = try #require(await harness.gateway.applied["member-1"])
        #expect(decision.held.contains(Fixture.passBadge))
        #expect(decision.revoked.isEmpty)
    }

    @Test("A clean read really does demote, so the hold is a decision and not an inability")
    func cleanReadDemotes() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 0)],
            roles: ["member-1": [Fixture.bronze, Fixture.silver, Fixture.gold, Fixture.verified]]
        )

        let report = await harness.sweep.run()

        let decision = try #require(await harness.gateway.applied["member-1"])
        #expect(decision.revoked == [Fixture.bronze, Fixture.silver, Fixture.gold])
        #expect(report.tally.changed == 1)
        #expect(report.tally.held == 0)
    }

    @Test("A role nobody configured survives a sweep that changes everything else")
    func handGrantedRoleSurvives() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: ["WALLET-1"])
        let harness = try await Harness.build(
            members: [member],
            readings: ["WALLET-1": Fixture.read("WALLET-1", tokens: 0)],
            roles: ["member-1": [Fixture.gold, Fixture.handGranted]]
        )

        _ = await harness.sweep.run()

        #expect(await harness.gateway.rolesHeld(by: "member-1").contains(Fixture.handGranted))
    }

    @Test("A member with no proved account is held, not stripped")
    func memberWithNoAccountsIsHeld() async throws {
        let member = Fixture.member(externalId: "member-1", addresses: [])
        let harness = try await Harness.build(
            members: [member],
            roles: ["member-1": [Fixture.gold]]
        )

        let report = await harness.sweep.run()

        #expect(await harness.gateway.applied.isEmpty)
        #expect(report.tally.heldReasons[SweepSkipReason.noAccounts.rawValue] == 1)
    }
}
