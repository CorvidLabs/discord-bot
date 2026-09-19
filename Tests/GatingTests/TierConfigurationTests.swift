import Foundation
import Testing
@testable import Gating

/// What the ladder refuses to be, and what an operator is told when it does.
@Suite("Tier configuration")
struct TierConfigurationTests {

    // MARK: - There is no default ladder

    @Test("A server that configured no rungs is told to configure one (ADOPT-1.a)")
    func noDefaultLadder() throws {
        // The original fell back to six rungs at one project's thresholds
        // whenever the first rung was unset, which meant a stranger's server
        // silently granted roles at numbers nobody there had chosen.
        let bare = Fixture.environment(removing: [
            "TIER_1_NAME", "TIER_1_MIN", "TIER_1_EMOJI", "TIER_1_ROLE_ID",
            "TIER_2_NAME", "TIER_2_MIN", "TIER_2_ROLE_ID",
            "TIER_3_NAME", "TIER_3_MIN", "TIER_3_ROLE_ID"
        ])
        do {
            _ = try TierConfiguration.load(from: bare, token: try Fixture.token())
            Issue.record("a ladder appeared out of nowhere")
        } catch let error as GatingConfigurationError {
            guard case .missing(let key, _) = error else {
                Issue.record("refused for the wrong reason: \(error)")
                return
            }
            #expect(key == "TIER_1_NAME")
        }
    }

    @Test("A ladder is as long or as short as the operator wants")
    func anyNumberOfRungs() throws {
        let one = try TierConfiguration.load(
            from: [
                "TIER_1_NAME": "Member",
                "TIER_1_MIN": "1",
                "TIER_1_ROLE_ID": "role-member"
            ],
            token: try Fixture.token()
        )
        #expect(one.ladder.rungs.count == 1)
        #expect(one.roleIds == ["member": "role-member"])

        let three = try TierConfiguration.load(from: Fixture.environment(), token: try Fixture.token())
        #expect(three.ladder.rungs.map(\.name) == ["Bronze", "Silver", "Gold"])
    }

    // MARK: - The gap

    @Test("A mistyped rung number drops that rung and the ones above it, rather than renumbering")
    func firstGapEndsTheLadder() throws {
        // The operator meant four rungs and typed the fourth as TIER_5.
        // Carrying on past the gap would hand them a four-rung ladder whose
        // fourth rung is their fifth, at their fifth's threshold, and nothing
        // would ever say so. Stopping here loses a rung visibly instead.
        let loaded = try TierConfiguration.load(
            from: Fixture.environment(overriding: [
                "TIER_5_NAME": "Platinum",
                "TIER_5_MIN": "100000",
                "TIER_5_ROLE_ID": "role-platinum"
            ]),
            token: try Fixture.token()
        )
        #expect(loaded.ladder.rungs.map(\.name) == ["Bronze", "Silver", "Gold"])
        #expect(loaded.roleIds["platinum"] == nil)
    }

    @Test("A rung written with nothing in it is the same as a rung not written")
    func blankIsUnset() throws {
        let loaded = try TierConfiguration.load(
            from: Fixture.environment(overriding: ["TIER_3_NAME": "   "]),
            token: try Fixture.token()
        )
        #expect(loaded.ladder.rungs.map(\.name) == ["Bronze", "Silver"])
    }

    // MARK: - Refusals

    @Test("A threshold that is not a whole number of tokens names the variable to fix (ADOPT-2)")
    func minimumMustBeANumber() throws {
        #expect(throws: GatingConfigurationError.notANumber(key: "TIER_2_MIN", value: "lots")) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_2_MIN": "lots"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("A rung everybody reaches is refused rather than granted to everybody")
    func zeroMinimumRefused() throws {
        #expect(throws: GatingConfigurationError.zeroMinimum(key: "TIER_1_MIN")) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_1_MIN": "0"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("A rung with no threshold at all is refused, not given one")
    func missingMinimumRefused() throws {
        #expect(throws: (any Error).self) {
            try TierConfiguration.load(
                from: Fixture.environment(removing: ["TIER_2_MIN"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("Two rungs at one threshold are refused, because one could never be reached")
    func duplicateMinimumRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateThreshold(
                baseUnits: 100_000_000,
                first: "TIER_1_MIN",
                firstWhole: 100,
                second: "TIER_2_MIN",
                secondWhole: 100
            )
        ) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_2_MIN": "100"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("Two rungs with one name are refused, because a stored row could not tell them apart")
    func duplicateNameRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateName(
                name: "bronze",
                first: "TIER_1_NAME",
                second: "TIER_2_NAME"
            )
        ) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_2_NAME": "bronze"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("Two rungs whose names slug to one id are refused, naming where the id came from")
    func duplicateIdRefused() throws {
        #expect(
            throws: GatingConfigurationError.duplicateId(
                id: "bronze",
                first: "TIER_1_NAME",
                second: "TIER_2_ID"
            )
        ) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_2_ID": "Bronze"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("A rung named in punctuation alone has no id to be made from it")
    func unusableNameRefused() throws {
        #expect(throws: GatingConfigurationError.unusableName(key: "TIER_2_NAME", value: "***")) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_2_NAME": "***"]),
                token: try Fixture.token()
            )
        }
    }

    @Test("A rung named after the no-rung label is refused, because a stored row could not tell them apart")
    func rungNamedAfterTheUnrankedLabelRefused() throws {
        // The label for holding too little has no threshold and no role. A
        // rung sharing it resolves for a stored row and then grants that
        // rung's role to somebody on no rung at all.
        #expect(
            throws: GatingConfigurationError.duplicateName(
                name: "None",
                first: TierConfiguration.unrankedNameKey,
                second: "TIER_3_NAME"
            )
        ) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: ["TIER_3_NAME": "None"]),
                token: try Fixture.token()
            )
        }

        // The operator's own word for it, too.
        #expect(throws: GatingConfigurationError.self) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: [
                    "TIER_UNRANKED_NAME": "Guest",
                    "TIER_3_NAME": "guest"
                ]),
                token: try Fixture.token()
            )
        }
    }

    @Test("Two thresholds too large to convert are still two thresholds at one place")
    func saturatingMinimumsCollide() throws {
        // Both of these are past what six decimals can express, so both land
        // on the ceiling. Comparing the numbers the operator typed sees two
        // different rungs; comparing what they convert to sees the ladder
        // nobody can climb that they actually wrote.
        #expect(
            throws: GatingConfigurationError.duplicateThreshold(
                baseUnits: UInt64.max,
                first: "TIER_1_MIN",
                firstWhole: 18_446_744_073_709_551_615,
                second: "TIER_2_MIN",
                secondWhole: 18_000_000_000_000_000_000
            )
        ) {
            try TierConfiguration.load(
                from: Fixture.environment(overriding: [
                    "TIER_1_MIN": "18446744073709551615",
                    "TIER_2_MIN": "18000000000000000000"
                ]),
                token: try Fixture.token()
            )
        }
    }

    @Test("A refusal over two saturating thresholds prints both numbers and the one they met at")
    func saturatingRefusalNamesAllThreeNumbers() throws {
        // The refusal used to carry one of the typed numbers, which is a
        // threshold neither rung sits at: they collided on the ceiling, and
        // an operator shown 18,000,000,000,000,000,000 has been sent to look
        // for a collision at a number that is in only one of their variables.
        do {
            _ = try TierConfiguration.load(
                from: Fixture.environment(overriding: [
                    "TIER_1_MIN": "18446744073709551615",
                    "TIER_2_MIN": "18000000000000000000"
                ]),
                token: try Fixture.token()
            )
            Issue.record("a ladder with two unreachable rungs loaded")
        } catch let error as GatingConfigurationError {
            let sentence = try #require(error.errorDescription)
            #expect(sentence.contains("TIER_1_MIN is 18,446,744,073,709,551,615"))
            #expect(sentence.contains("TIER_2_MIN is 18,000,000,000,000,000,000"))
            #expect(sentence.contains("come to 18,446,744,073,709,551,615 of its smallest unit"))
        }
    }

    @Test("A ladder longer than this module reads is refused, not quietly cut short")
    func tooManyRungsRefused() throws {
        var environment: [String: String] = [:]
        for index in 1...(NumberedEnvironment.maxEntries + 1) {
            environment["TIER_\(index)_NAME"] = "Rung \(index)"
            environment["TIER_\(index)_MIN"] = "\(index)"
            environment["TIER_\(index)_ROLE_ID"] = "role-\(index)"
        }
        #expect(
            throws: GatingConfigurationError.tooManyEntries(
                key: "TIER_\(NumberedEnvironment.maxEntries + 1)_NAME",
                limit: NumberedEnvironment.maxEntries
            )
        ) {
            try TierConfiguration.load(from: environment, token: try Fixture.token())
        }
    }

    // MARK: - Ids and roles

    @Test("A rung's id is a slug of its name unless the operator gives it one")
    func idsAreSlugs() throws {
        let loaded = try TierConfiguration.load(
            from: Fixture.environment(overriding: [
                "TIER_2_NAME": "Diamond Hands",
                "TIER_3_ID": "top-rung"
            ]),
            token: try Fixture.token()
        )
        #expect(loaded.ladder.rung(id: "diamond_hands") != nil)
        #expect(loaded.ladder.rung(id: "top_rung") != nil)
    }

    @Test("A rung with no role still exists, for a card that shows a rung without granting one")
    func rungWithoutARole() throws {
        let loaded = try TierConfiguration.load(
            from: Fixture.environment(removing: ["TIER_2_ROLE_ID"]),
            token: try Fixture.token()
        )
        #expect(loaded.ladder.rungs.count == 3)
        #expect(loaded.roleIds["silver"] == nil)
        #expect(loaded.roleIds["bronze"] == Fixture.bronze)

        // And it is nameable, because a mistyped TIER_2_ROLE_ID looks exactly
        // like a rung meant to grant nothing: the rung is in no decision's
        // managed set and in no decision's held set, so this is the only
        // place an operator could be told about it.
        #expect(loaded.rungsWithoutRoles.map(\.id) == ["silver"])
        let whole = try TierConfiguration.load(from: Fixture.environment(), token: try Fixture.token())
        #expect(whole.rungsWithoutRoles.isEmpty)
    }

    @Test("A threshold may be written with underscores, because nine zeros is hard to count")
    func underscoresInNumbers() throws {
        let loaded = try TierConfiguration.load(
            from: Fixture.environment(overriding: ["TIER_3_MIN": "1_000_000"]),
            token: try Fixture.token()
        )
        #expect(try #require(loaded.ladder.rung(id: "gold")).minimumBaseUnits == Fixture.whole(1_000_000))
    }
}
