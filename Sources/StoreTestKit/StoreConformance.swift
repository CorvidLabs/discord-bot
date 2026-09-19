@preconcurrency import Foundation
import Chain
import Reserve
import Store

/// Every behaviour a store must have, run against a freshly made one.
///
/// A backend proves itself by calling this. The in-memory store and the SQLite
/// store run the identical list, which is the whole point: a contributor who
/// builds a third backend writes six lines and finds out whether it is a store
/// or only looks like one.
///
/// The store is made once per behaviour rather than once per suite, because a
/// store that only works on a clean file is a store that fails in week two.
public struct StoreConformance: Sendable {

    // MARK: - Properties

    /// Makes a store with nothing in it, plus whatever probes it can offer.
    public typealias Factory = @Sendable () async throws -> StoreUnderTest

    /// One named behaviour, so a failure says which one.
    public enum Behaviour: String, CaseIterable, Sendable {

        /// A member written is the member read back.
        case aMemberRoundTrips

        /// A key is drawn, never derived, and a member who leaves and returns
        /// is a different member to everything below the chat boundary.
        case aKeyComesFromNothing

        /// Two chat ids that differ in their bytes are two members.
        case identifiersAreComparedByTheirBytes

        /// An account written is the account read back, at every amount.
        case anAccountRoundTrips

        /// One account belongs to one member.
        case oneAccountBelongsToOneMember

        /// A member's accounts come back oldest first.
        case accountsComeBackOldestFirst

        /// The stored halves are what stop a second wallet demoting somebody.
        case storedBalancesStopADemotion

        /// Unlinking one account leaves the member and the others alone.
        case unlinkingLeavesTheMember

        /// The sweep guard counts members, not accounts.
        case theSweepCountCountsMembers

        /// No baseline reads as nil, which is a first run.
        case anAbsentBaselineIsNil

        /// A baseline written is the baseline read back.
        case aBaselineRoundTrips

        /// No state reads as a fresh reserve.
        case anAbsentReserveStateIsFresh

        /// The reserve's state round-trips, including saturated figures.
        case reserveStateRoundTrips

        /// An epoch nobody ran reads as unpaid, not as missing.
        case anAbsentEpochIsUnpaid

        /// An epoch's record round-trips, order and all.
        case anEpochRoundTrips

        /// A released claim really leaves the row.
        case aReleasedClaimIsGone

        /// No count reads as nil, and nil means never written.
        case anAbsentBudgetIsNil

        /// The day's count round-trips, including a saturated one.
        case theBudgetRoundTrips

        /// Instants come back rounded to the second, everywhere.
        case instantsAreRecordedToTheSecond

        /// An unreadable epoch row throws rather than reading as unpaid.
        case anUnreadableEpochThrows

        /// An unreadable count throws rather than reading as never written.
        case anUnreadableBudgetThrows

        /// An unreadable account throws rather than reading as absent.
        case anUnreadableAccountThrows

        /// An unreadable reserve state throws rather than reading as fresh.
        case anUnreadableStateThrows

        /// An unreadable baseline throws rather than reading as a first run.
        case anUnreadableBaselineThrows

        /// Forgetting takes the member and everything they owned.
        case forgettingTakesEverything

        /// Forgetting somebody who is not there says so quietly.
        case forgettingTwiceIsQuiet

        /// What the ledger keeps after a forgetting names nobody.
        case theLedgerNamesNobodyAfterAForgetting

        /// A member can be shown everything before deciding.
        case disclosureShowsEverything

        /// A hundred writes at once all land.
        case concurrentWritesAllLand

        /// Recomputed spend only ever rises.
        case reconciledSpendOnlyRises

        /// A run cut at any save resumes without paying anybody twice.
        case aCutRunPaysNobodyTwice

        /// The same, across a handle that was let go and opened again.
        case aCutRunPaysNobodyTwiceAcrossAReopen

        /// A claim that a save returned for is on the storage, not in a buffer.
        case aClaimIsOnTheStorageBeforeAPaymentIsAttempted

        // MARK: - Public Methods

        /// Behaviours that need a way to write an unreadable row.
        public static var needingCorruption: [Behaviour] {
            [
                .anUnreadableEpochThrows,
                .anUnreadableBudgetThrows,
                .anUnreadableAccountThrows,
                .anUnreadableStateThrows,
                .anUnreadableBaselineThrows
            ]
        }

        /// Behaviours that need a way to look at the storage from elsewhere.
        public static var needingDurability: [Behaviour] {
            [.aCutRunPaysNobodyTwiceAcrossAReopen, .aClaimIsOnTheStorageBeforeAPaymentIsAttempted]
        }
    }

    /// Whether a behaviour ran, or why it did not.
    public enum Outcome: Sendable, Equatable {

        /// The behaviour ran and the store had it.
        case ran

        /// The behaviour did not run, and this is the honest reason.
        ///
        /// A skip is a statement the suite makes, not a silence. "This store is
        /// not durable" is worth reading.
        case skipped(reason: String)

        // MARK: - Public Methods

        /// Why the behaviour did not run, or nil because it did.
        public var skipReason: String? {
            switch self {
            case .ran: return nil
            case .skipped(let reason): return reason
            }
        }
    }

    /// The backend under test, as the caller named it.
    public let backend: String

    private let makeStore: Factory

    // MARK: - Initializers

    /// - Parameters:
    ///   - backend: What to call this backend in a failure.
    ///   - makeStore: Makes an empty store, once per behaviour.
    public init(backend: String, makeStore: @escaping Factory) {
        self.backend = backend
        self.makeStore = makeStore
    }

    // MARK: - Public Methods

    /// Runs one behaviour against a store made for it.
    ///
    /// The store is closed before this returns, whether the behaviour passed,
    /// failed or was skipped. Closing inside a detached task instead would let
    /// a caller remove a temporary directory out from under an open handle,
    /// which is how a suite starts leaving files behind.
    @discardableResult
    public func run(_ behaviour: Behaviour) async throws -> Outcome {
        let subject = try await makeStore()
        do {
            let outcome = try await perform(behaviour, subject)
            await subject.store.close()
            return outcome
        } catch {
            await subject.store.close()
            throw error
        }
    }

    // MARK: - Private Methods

    private func perform(_ behaviour: Behaviour, _ subject: StoreUnderTest) async throws -> Outcome {
        switch behaviour {
        case .aMemberRoundTrips: try await aMemberRoundTrips(subject)
        case .aKeyComesFromNothing: try await aKeyComesFromNothing(subject)
        case .identifiersAreComparedByTheirBytes:
            try await identifiersAreComparedByTheirBytes(subject)
        case .anAccountRoundTrips: try await anAccountRoundTrips(subject)
        case .oneAccountBelongsToOneMember: try await oneAccountBelongsToOneMember(subject)
        case .accountsComeBackOldestFirst: try await accountsComeBackOldestFirst(subject)
        case .storedBalancesStopADemotion: try await storedBalancesStopADemotion(subject)
        case .unlinkingLeavesTheMember: try await unlinkingLeavesTheMember(subject)
        case .theSweepCountCountsMembers: try await theSweepCountCountsMembers(subject)
        case .anAbsentBaselineIsNil: try await anAbsentBaselineIsNil(subject)
        case .aBaselineRoundTrips: try await aBaselineRoundTrips(subject)
        case .anAbsentReserveStateIsFresh: try await anAbsentReserveStateIsFresh(subject)
        case .reserveStateRoundTrips: try await reserveStateRoundTrips(subject)
        case .anAbsentEpochIsUnpaid: try await anAbsentEpochIsUnpaid(subject)
        case .anEpochRoundTrips: try await anEpochRoundTrips(subject)
        case .aReleasedClaimIsGone: try await aReleasedClaimIsGone(subject)
        case .anAbsentBudgetIsNil: try await anAbsentBudgetIsNil(subject)
        case .theBudgetRoundTrips: try await theBudgetRoundTrips(subject)
        case .instantsAreRecordedToTheSecond: try await instantsAreRecordedToTheSecond(subject)
        case .forgettingTakesEverything: try await forgettingTakesEverything(subject)
        case .forgettingTwiceIsQuiet: try await forgettingTwiceIsQuiet(subject)
        case .theLedgerNamesNobodyAfterAForgetting:
            try await theLedgerNamesNobodyAfterAForgetting(subject)
        case .disclosureShowsEverything: try await disclosureShowsEverything(subject)
        case .concurrentWritesAllLand: try await concurrentWritesAllLand(subject)
        case .reconciledSpendOnlyRises: try await reconciledSpendOnlyRises(subject)
        case .aCutRunPaysNobodyTwice: try await aCutRunPaysNobodyTwice(subject)

        case .anUnreadableEpochThrows, .anUnreadableBudgetThrows, .anUnreadableAccountThrows,
             .anUnreadableStateThrows, .anUnreadableBaselineThrows:
            guard let probe = subject.corruption else {
                return .skipped(
                    reason: "\(backend) cannot write a row its own reader refuses, so the rule that "
                        + "an unreadable row throws is not proved here."
                )
            }
            try await runCorruption(behaviour, subject: subject, probe: probe)

        case .aCutRunPaysNobodyTwiceAcrossAReopen, .aClaimIsOnTheStorageBeforeAPaymentIsAttempted:
            guard let probe = subject.durability else {
                return .skipped(
                    reason: "\(backend) does not outlive the handle that wrote to it, so nothing "
                        + "here shows a claim reaching storage before a payment is attempted."
                )
            }
            try await runDurability(behaviour, subject: subject, probe: probe)
        }
        return .ran
    }

    // MARK: - Public Methods

    /// Runs every behaviour, answering with what each one did.
    ///
    /// For a caller that wants the whole picture in one value. A test target
    /// that wants a named failure per behaviour calls ``run(_:)`` instead.
    public func runAll() async throws -> [Behaviour: Outcome] {
        var outcomes: [Behaviour: Outcome] = [:]
        for behaviour in Behaviour.allCases {
            outcomes[behaviour] = try await run(behaviour)
        }
        return outcomes
    }

    // MARK: - Internal Methods

    /// Fails the behaviour when `condition` does not hold.
    internal func expect(
        _ condition: Bool,
        _ behaviour: Behaviour,
        _ detail: @autoclosure () -> String
    ) throws {
        guard !condition else { return }
        throw StoreConformanceFailure(backend: backend, behaviour: behaviour, detail: detail())
    }

    /// Fails the behaviour when `read` answers instead of refusing.
    ///
    /// Written as "it must throw" rather than "it must not equal" because the
    /// rule being checked is about the refusal itself: what a bad read comes
    /// back as is beside the point, since every wrong answer here is a wrong
    /// answer somebody acts on.
    internal func expectRefusal(
        _ behaviour: Behaviour,
        _ detail: String,
        _ read: () async throws -> Void
    ) async throws {
        do {
            try await read()
        } catch {
            return
        }
        throw StoreConformanceFailure(backend: backend, behaviour: behaviour, detail: detail)
    }

    /// Fails the behaviour when two values differ.
    internal func expectEqual<Value: Equatable>(
        _ found: Value,
        _ wanted: Value,
        _ behaviour: Behaviour,
        _ what: @autoclosure () -> String
    ) throws {
        try expect(found == wanted, behaviour, "\(what()): wanted \(wanted), found \(found)")
    }
}
