import Foundation
import Reserve
import Store
import Testing

@Suite("The records a store holds")
struct StoreRecordTests {

    @Test("A key is thirty two lowercase hexadecimal characters, and anything else is refused")
    func aKeyIsRefusedUnlessItIsAKey() throws {
        let minted = MemberKey.mint()
        #expect(minted.value.count == MemberKey.characterCount)
        #expect(try MemberKey(minted.value) == minted)
        for bad in ["", "abc", String(repeating: "g", count: 32), String(repeating: "A", count: 32)] {
            #expect(throws: StoreError.self) { _ = try MemberKey(bad) }
        }
    }

    @Test("A key decodes as one string, and a malformed one refuses rather than arriving")
    func aKeyValidatesOnTheWayIn() throws {
        let key = MemberKey.mint()
        let encoded = try ReserveCoding.encode(key)
        #expect(encoded == "\"\(key.value)\"")
        #expect(try ReserveCoding.decode(MemberKey.self, from: encoded) == key)
        #expect(throws: (any Error).self) {
            _ = try ReserveCoding.decode(MemberKey.self, from: "\"nope\"")
        }
    }

    @Test("Two thousand keys are two thousand different keys")
    func keysDoNotCollide() {
        let keys = Set((0..<2_000).map { _ in MemberKey.mint().value })
        #expect(keys.count == 2_000)
    }

    @Test("An instant is rounded down to its second, on both sides of 1970")
    func instantsRoundDown() {
        #expect(StoreDate.seconds(Date(timeIntervalSince1970: 10.9)) == 10)
        // Down rather than to nearest, so a recorded instant is never later
        // than the instant that happened.
        #expect(StoreDate.seconds(Date(timeIntervalSince1970: -10.1)) == -11)
        #expect(StoreDate.whole(nil) == nil)
        #expect(StoreDate.date(seconds: -11).timeIntervalSince1970 == -11)
    }

    @Test("A record keeps the whole of an amount, including the one an overflow saturates to")
    func recordsHoldSaturatedAmounts() throws {
        let record = AccountRecord(
            memberKey: MemberKey.mint(),
            address: "ACCOUNT-0001",
            provenAt: Date(timeIntervalSince1970: 1),
            directBaseUnits: UInt64.max,
            liquidityBaseUnits: UInt64.max
        )
        #expect(record.balance.directBaseUnits == UInt64.max)
        let round = try ReserveCoding.decode(
            AccountRecord.self,
            from: try ReserveCoding.encode(record)
        )
        #expect(round == record)
    }

    @Test("A refusal names what to change without printing the whole of an identifier")
    func refusalsAreReadable() throws {
        let key = MemberKey.mint()
        let sentence = try #require(StoreError.memberNotFound(key: key.value).errorDescription)
        #expect(!sentence.contains(key.value))
        #expect(sentence.contains(String(key.value.suffix(6))))
    }

    @Test("What a payment record keeps is named in full, wallet and holdings included")
    func theLedgerSentenceNamesTheWallet() {
        let sentence = MemberDisclosure.payoutLedgerSentence
        // The wallet paid and the ids of the things paid for both survive a
        // forgetting, and both came from the member. Saying the record "keeps
        // nothing that came from you" in the same breath as naming the wallet
        // contradicted itself, and the person it misled is the one deciding
        // whether to be forgotten.
        #expect(sentence.contains("the wallet it went to"))
        #expect(sentence.contains("the ids of the things it paid for"))
        #expect(!sentence.contains("keeps nothing that came from you"))
    }

    @Test("A forgetting reports what it cleared, by table")
    func aForgettingReportsItsWork() {
        let outcome = ForgetOutcome(
            memberKey: MemberKey.mint(),
            cleared: [StoreTable.members: 1, StoreTable.accounts: 3, "untouched": 0]
        )
        #expect(outcome.clearedRowCount == 4)
        #expect(outcome.clearedTables == [StoreTable.accounts, StoreTable.members])
    }
}

@Suite("Putting recorded spend back in step")
struct ReserveSpendReconciliationTests {

    @Test("An epoch number no schedule reaches is refused rather than walked part way")
    func anAbsurdEpochRangeIsRefused() async throws {
        let store = InMemoryStore()
        try await store.save(state: ReserveState(completedEpochs: ["s": 5_000]))
        // Walking a truncated range would answer with a spend figure that is
        // quietly too small, which is the direction the engine calls unsafe.
        await #expect(throws: StoreError.self) {
            _ = try await ReserveSpendReconciliation.reconcile(store: store, streamIds: ["s"])
        }
    }

    @Test("A stream nobody names is left exactly as it was")
    func anUnnamedStreamIsLeftAlone() async throws {
        let store = InMemoryStore()
        try await store.save(
            epoch: ReserveEpochRecord(streamId: "quiet", epoch: 1, paidBaseUnits: 900)
        )
        try await store.save(state: ReserveState(completedEpochs: ["quiet": 1]))
        let raised = try await ReserveSpendReconciliation.reconcile(store: store, streamIds: [])
        #expect(raised == [])
        #expect(try await store.loadState().spent("quiet") == 0)
    }

    @Test("The epoch in flight counts, not only the ones that finished")
    func theOpenEpochCounts() async throws {
        let store = InMemoryStore()
        try await store.save(
            epoch: ReserveEpochRecord(streamId: "s", epoch: 1, paidBaseUnits: 100, completedAt: Date())
        )
        // Claimed and not finished: the value has been committed and the
        // ledger has to say so.
        try await store.save(
            epoch: ReserveEpochRecord(streamId: "s", epoch: 2, paidBaseUnits: 40)
        )
        try await store.save(state: ReserveState(completedEpochs: ["s": 1], spentBaseUnits: ["s": 100]))
        _ = try await ReserveSpendReconciliation.reconcile(store: store, streamIds: ["s"])
        #expect(try await store.loadState().spent("s") == 140)
    }
}
