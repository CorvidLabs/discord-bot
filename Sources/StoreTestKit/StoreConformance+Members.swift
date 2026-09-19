@preconcurrency import Foundation
import Gating
import Reserve
import Store

extension StoreConformance {

    // MARK: - Internal Methods

    internal func aMemberRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let admitted = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let byExternalId = try await store.member(externalId: ConformanceFixture.externalId(1))
        let byKey = try await store.member(key: admitted.key)
        try expectEqual(byExternalId, admitted, .aMemberRoundTrips, "the member read by chat id")
        try expectEqual(byKey, admitted, .aMemberRoundTrips, "the member read by key")

        // Admitting twice is the ordinary case: every command a member runs
        // reaches for their row, and a second key would orphan the first.
        let again = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(500)
        )
        try expectEqual(again, admitted, .aMemberRoundTrips, "admitting the same member twice")

        let stranger = try await store.member(externalId: ConformanceFixture.externalId(2))
        try expect(stranger == nil, .aMemberRoundTrips, "a member nobody admitted read as \(String(describing: stranger))")
    }

    internal func aKeyComesFromNothing(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let first = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let second = try await store.admitMember(
            externalId: ConformanceFixture.externalId(2),
            at: ConformanceFixture.instant(0)
        )
        try expect(
            first.key != second.key,
            .aKeyComesFromNothing,
            "two members were given the same key"
        )
        for member in [first, second] {
            try expectEqual(
                member.key.value.count,
                MemberKey.characterCount,
                .aKeyComesFromNothing,
                "the width of a key"
            )
            try expect(
                !member.key.value.contains(member.externalId),
                .aKeyComesFromNothing,
                "the key \(member.key) carries the chat id it was drawn beside"
            )
        }

        // The property the whole identity model rests on: a member who leaves
        // and comes back is a different member to everything below the chat
        // boundary, so two closed epochs cannot be joined into one person.
        try await store.forget(memberKey: first.key)
        let returned = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(1_000)
        )
        try expect(
            returned.key != first.key,
            .aKeyComesFromNothing,
            "a member who was forgotten came back under the key they had before"
        )
    }

    /// Two chat ids that no chat client would call the same.
    ///
    /// What a chat client hands over is bytes. Swift compares strings by
    /// canonical equivalence and a text column compares them byte for byte, so
    /// a store keyed by `String` gives the second of a normalised pair the
    /// first one's member key, and with it the first one's wallets and rungs,
    /// while a store keyed by the column treats them as two people. A text
    /// binding measured to its first NUL does the same thing to a pair that
    /// matches up to one. The two backends cannot both be right, and the byte
    /// answer is the one the chat client meant.
    internal func identifiersAreComparedByTheirBytes(_ subject: StoreUnderTest) async throws {
        let behaviour = Behaviour.identifiersAreComparedByTheirBytes
        let store = subject.store
        let pairs = [
            ("EXTERNAL-\u{00E9}", "EXTERNAL-e\u{0301}"),
            ("EXTERNAL-0001\u{0000}A", "EXTERNAL-0001\u{0000}B")
        ]
        for (first, second) in pairs {
            let one = try await store.admitMember(externalId: first, at: ConformanceFixture.instant(0))
            let other = try await store.admitMember(externalId: second, at: ConformanceFixture.instant(1))
            try expect(
                one.key != other.key,
                behaviour,
                "two chat ids whose bytes differ were given one member between them"
            )
            try expectEqual(
                try await store.member(externalId: first)?.key,
                one.key,
                behaviour,
                "the member the first of the pair finds"
            )
            try expectEqual(
                try await store.member(externalId: second)?.key,
                other.key,
                behaviour,
                "the member the second of the pair finds"
            )
            // And the id comes back as it was handed over, rather than as
            // much of it as survived the trip.
            try expectEqual(
                try await store.member(key: one.key)?.externalId,
                first,
                behaviour,
                "the chat id read back"
            )
        }
    }

    internal func anAccountRoundTrips(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        // The saturated figure is asserted here rather than left to a
        // performance test, because it is the value the payout engine is
        // designed to produce on overflow and the value a signed integer column
        // cannot hold.
        for amount in [UInt64(0), 1, UInt64(Int64.max), UInt64(Int64.max) + 1, UInt64.max] {
            let record = AccountRecord(
                memberKey: member.key,
                address: ConformanceFixture.account(Int(amount % 97)),
                provenAt: ConformanceFixture.instant(10),
                directBaseUnits: amount,
                liquidityBaseUnits: amount,
                balancesReadAt: ConformanceFixture.instant(20)
            )
            try await store.prove(account: record)
            let read = try await store.account(address: record.address)
            try expectEqual(read, record, .anAccountRoundTrips, "an account holding \(amount)")
            try await store.unlink(address: record.address)
        }

        let unread = AccountRecord(
            memberKey: member.key,
            address: ConformanceFixture.account(50),
            provenAt: ConformanceFixture.instant(10)
        )
        try await store.prove(account: unread)
        let readBack = try await store.account(address: unread.address)
        try expect(
            readBack?.balancesReadAt == nil,
            .anAccountRoundTrips,
            "an account nobody has read came back claiming a reading time"
        )

        // A reading for an address nobody proved is not written, and the
        // answer says so. That answer is the only way a caller can tell a
        // reading that landed from one that went nowhere.
        let nowhere = try await store.recordBalances(
            address: ConformanceFixture.account(98),
            directBaseUnits: 1,
            liquidityBaseUnits: 1,
            at: ConformanceFixture.instant(40)
        )
        try expect(
            !nowhere,
            .anAccountRoundTrips,
            "a reading for an address nobody proved was reported as written"
        )
    }

    internal func oneAccountBelongsToOneMember(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let owner = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let stranger = try await store.admitMember(
            externalId: ConformanceFixture.externalId(2),
            at: ConformanceFixture.instant(0)
        )
        let address = ConformanceFixture.account(1)
        try await store.prove(
            account: AccountRecord(
                memberKey: owner.key,
                address: address,
                provenAt: ConformanceFixture.instant(10),
                directBaseUnits: 500
            )
        )
        var refused = false
        do {
            try await store.prove(
                account: AccountRecord(
                    memberKey: stranger.key,
                    address: address,
                    provenAt: ConformanceFixture.instant(20)
                )
            )
        } catch StoreError.accountAlreadyProven {
            refused = true
        }
        try expect(refused, .oneAccountBelongsToOneMember, "a second member proved the same account")
        let still = try await store.account(address: address)
        try expectEqual(
            still?.memberKey,
            owner.key,
            .oneAccountBelongsToOneMember,
            "who the account still belongs to"
        )
        try expectEqual(
            still?.directBaseUnits,
            500,
            .oneAccountBelongsToOneMember,
            "the figure the refused write left alone"
        )

        // Re-proving your own account is an ordinary thing a member does, and
        // it must not lose the figures somebody else just read.
        try await store.prove(
            account: AccountRecord(
                memberKey: owner.key,
                address: address,
                provenAt: ConformanceFixture.instant(30)
            )
        )
        let reproved = try await store.account(address: address)
        try expectEqual(
            reproved?.directBaseUnits,
            500,
            .oneAccountBelongsToOneMember,
            "the figure kept across re-proving"
        )
        // Re-proving moves when they proved it, which is the half of the
        // promise the figures surviving does not cover, and which a member's
        // accounts are ordered by.
        try expectEqual(
            reproved?.provenAt,
            ConformanceFixture.instant(30),
            .oneAccountBelongsToOneMember,
            "when the member last proved it"
        )
    }

    internal func accountsComeBackOldestFirst(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        for index in [3, 1, 2] {
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: ConformanceFixture.account(index),
                    provenAt: ConformanceFixture.instant(index * 10)
                )
            )
        }
        let addresses = try await store.accounts(memberKey: member.key).map(\.address)
        try expectEqual(
            addresses,
            [1, 2, 3].map { ConformanceFixture.account($0) },
            .accountsComeBackOldestFirst,
            "the order accounts come back in"
        )
    }

    internal func storedBalancesStopADemotion(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let first = ConformanceFixture.account(1)
        try await store.prove(
            account: AccountRecord(
                memberKey: member.key,
                address: first,
                provenAt: ConformanceFixture.instant(10)
            )
        )
        try await store.recordBalances(
            address: first,
            directBaseUnits: 9_000,
            liquidityBaseUnits: 1_000,
            at: ConformanceFixture.instant(20)
        )

        // The morning this is about: a member on the top rung links an empty
        // second wallet, verification reads only the wallet that just signed,
        // and a sweep takes every rung off somebody who gained an account.
        let second = ConformanceFixture.account(2)
        try await store.prove(
            account: AccountRecord(
                memberKey: member.key,
                address: second,
                provenAt: ConformanceFixture.instant(30)
            )
        )
        let totals = CombinedBalance.afterLinking(
            account: second,
            directBaseUnits: 0,
            liquidityBaseUnits: 0,
            knownAccounts: try await store.balances(memberKey: member.key)
        )
        try expectEqual(totals.combined, 10_000, .storedBalancesStopADemotion, "the combined total")
        try expectEqual(totals.direct, 9_000, .storedBalancesStopADemotion, "the direct half")
        try expectEqual(totals.liquidity, 1_000, .storedBalancesStopADemotion, "the pooled half")
        try expect(
            totals.otherAccountsExist,
            .storedBalancesStopADemotion,
            "the member was reported as having only the account that just signed"
        )
    }

    internal func unlinkingLeavesTheMember(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        for index in [1, 2] {
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: ConformanceFixture.account(index),
                    provenAt: ConformanceFixture.instant(index)
                )
            )
        }
        let removed = try await store.unlink(address: ConformanceFixture.account(1))
        try expect(removed, .unlinkingLeavesTheMember, "unlinking an account that was there")
        let again = try await store.unlink(address: ConformanceFixture.account(1))
        try expect(!again, .unlinkingLeavesTheMember, "unlinking the same account twice")
        let left = try await store.accounts(memberKey: member.key).map(\.address)
        try expectEqual(
            left,
            [ConformanceFixture.account(2)],
            .unlinkingLeavesTheMember,
            "what the member has left"
        )
        let stillThere = try await store.member(key: member.key)
        try expect(stillThere != nil, .unlinkingLeavesTheMember, "the member went with the account")
    }

    internal func theSweepCountCountsMembers(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let empty = try await store.verifiedMemberCount()
        try expectEqual(empty, 0, .theSweepCountCountsMembers, "the count of an empty store")

        let busy = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        for index in [1, 2, 3] {
            try await store.prove(
                account: AccountRecord(
                    memberKey: busy.key,
                    address: ConformanceFixture.account(index),
                    provenAt: ConformanceFixture.instant(index)
                )
            )
        }
        // A member with three accounts is one member. Counting accounts would
        // hide exactly the collapse the sweep guard exists to catch.
        try expectEqual(
            try await store.verifiedMemberCount(),
            1,
            .theSweepCountCountsMembers,
            "one member with three accounts"
        )

        // A member who has proved nothing is not verified.
        _ = try await store.admitMember(
            externalId: ConformanceFixture.externalId(2),
            at: ConformanceFixture.instant(0)
        )
        try expectEqual(
            try await store.verifiedMemberCount(),
            1,
            .theSweepCountCountsMembers,
            "a member who has proved nothing"
        )
    }

    internal func forgettingTakesEverything(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let bystander = try await store.admitMember(
            externalId: ConformanceFixture.externalId(2),
            at: ConformanceFixture.instant(0)
        )
        for index in [1, 2] {
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: ConformanceFixture.account(index),
                    provenAt: ConformanceFixture.instant(index)
                )
            )
        }
        try await store.prove(
            account: AccountRecord(
                memberKey: bystander.key,
                address: ConformanceFixture.account(9),
                provenAt: ConformanceFixture.instant(9)
            )
        )

        let outcome = try await store.forget(memberKey: member.key)
        try expectEqual(outcome.memberKey, member.key, .forgettingTakesEverything, "who was forgotten")
        try expectEqual(
            outcome.cleared[StoreTable.members],
            1,
            .forgettingTakesEverything,
            "directory rows removed"
        )
        try expectEqual(
            outcome.cleared[StoreTable.accounts],
            2,
            .forgettingTakesEverything,
            "account rows removed"
        )
        try expect(
            try await store.member(key: member.key) == nil,
            .forgettingTakesEverything,
            "the directory row survived"
        )
        try expect(
            try await store.member(externalId: ConformanceFixture.externalId(1)) == nil,
            .forgettingTakesEverything,
            "the chat id still finds a member"
        )
        try expectEqual(
            try await store.accounts(memberKey: member.key).count,
            0,
            .forgettingTakesEverything,
            "accounts left behind"
        )
        try expect(
            try await store.account(address: ConformanceFixture.account(1)) == nil,
            .forgettingTakesEverything,
            "an account row survived its member"
        )
        // The bystander is the half of this that a cascade gets wrong.
        try expect(
            try await store.account(address: ConformanceFixture.account(9)) != nil,
            .forgettingTakesEverything,
            "somebody else's account went too"
        )
    }

    internal func forgettingTwiceIsQuiet(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        _ = try await store.forget(memberKey: member.key)
        let second = try await store.forget(memberKey: member.key)
        try expectEqual(
            second.clearedRowCount,
            0,
            .forgettingTwiceIsQuiet,
            "rows cleared by forgetting somebody already gone"
        )
        let stranger = try await store.forget(memberKey: MemberKey.mint())
        try expectEqual(
            stranger.clearedRowCount,
            0,
            .forgettingTwiceIsQuiet,
            "rows cleared by forgetting a key nobody has"
        )
    }

    internal func disclosureShowsEverything(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        for index in [1, 2] {
            try await store.prove(
                account: AccountRecord(
                    memberKey: member.key,
                    address: ConformanceFixture.account(index),
                    provenAt: ConformanceFixture.instant(index),
                    directBaseUnits: UInt64(index) * 1_000
                )
            )
        }
        let disclosure = try await store.disclosure(memberKey: member.key)
        try expectEqual(disclosure?.member, member, .disclosureShowsEverything, "the directory row shown")
        try expectEqual(
            disclosure?.accounts.map(\.address),
            [1, 2].map { ConformanceFixture.account($0) },
            .disclosureShowsEverything,
            "the accounts shown"
        )
        try expect(
            disclosure?.retainedAfterForgetting.contains(MemberDisclosure.payoutLedgerSentence) == true,
            .disclosureShowsEverything,
            "the sentence about what a payment record keeps was not shown"
        )
        try expect(
            try await store.disclosure(memberKey: MemberKey.mint()) == nil,
            .disclosureShowsEverything,
            "a key nobody has disclosed something"
        )
    }

    internal func concurrentWritesAllLand(_ subject: StoreUnderTest) async throws {
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let count = 100
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    try await store.prove(
                        account: AccountRecord(
                            memberKey: member.key,
                            address: ConformanceFixture.account(index),
                            provenAt: ConformanceFixture.instant(index),
                            directBaseUnits: UInt64(index)
                        )
                    )
                }
            }
            try await group.waitForAll()
        }
        let landed = try await store.accounts(memberKey: member.key)
        try expectEqual(landed.count, count, .concurrentWritesAllLand, "accounts that landed")
        try expectEqual(
            Set(landed.map(\.address)).count,
            count,
            .concurrentWritesAllLand,
            "distinct accounts that landed"
        )
    }
}

extension StoreConformance {

    // MARK: - Internal Methods

    /// What the payout ledger keeps about somebody who has been forgotten.
    ///
    /// The two promises that collide everywhere else, held at once here. The
    /// ledger has to keep who was already paid this epoch, or a resumed run
    /// pays them again. Somebody who leaves has to be forgotten. Both are true
    /// because the thing the ledger keeps was never theirs: a key this instance
    /// drew, which stops naming anybody the moment the directory row goes.
    internal func theLedgerNamesNobodyAfterAForgetting(_ subject: StoreUnderTest) async throws {
        let behaviour = Behaviour.theLedgerNamesNobodyAfterAForgetting
        let store = subject.store
        let member = try await store.admitMember(
            externalId: ConformanceFixture.externalId(1),
            at: ConformanceFixture.instant(0)
        )
        let address = ConformanceFixture.account(1)
        try await store.prove(
            account: AccountRecord(
                memberKey: member.key,
                address: address,
                provenAt: ConformanceFixture.instant(1)
            )
        )
        var record = ReserveEpochRecord(streamId: ConformanceFixture.streamId, epoch: 1)
        record.claim(
            entry: ReserveEpochEntry(
                recipientId: member.key.value,
                account: address,
                units: 1,
                baseUnitsAmount: 4_000,
                claimedHoldingIds: [ConformanceFixture.holding(1)]
            ),
            at: ConformanceFixture.instant(2)
        )
        try await store.save(epoch: record)

        try await store.forget(memberKey: member.key)

        // The guard is untouched, so a run resumed after the forgetting still
        // skips the slot rather than paying it again.
        let ledger = try await store.loadEpoch(streamId: record.streamId, epoch: 1)
        try expectEqual(ledger, record, behaviour, "the ledger row after a forgetting")
        try expect(
            ledger.paidRecipientIdSet.contains(member.key.value),
            behaviour,
            "the ledger stopped recognising a slot it had already paid"
        )

        // And the key it kept now leads nowhere.
        try expect(
            try await store.member(key: member.key) == nil,
            behaviour,
            "the key in the ledger still finds a member"
        )
        try expect(
            try await store.member(externalId: ConformanceFixture.externalId(1)) == nil,
            behaviour,
            "the chat id still finds a member"
        )
        try expect(
            !ledger.paidRecipientIds.contains(ConformanceFixture.externalId(1)),
            behaviour,
            "the ledger holds the chat id itself, which no forgetting can take back"
        )
    }
}
