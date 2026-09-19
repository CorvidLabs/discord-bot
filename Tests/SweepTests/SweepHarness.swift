import Chain
import Foundation
import Gating
import Store
@testable import Sweep

/// One assembled sweep and everything it was built from, so a test can
/// reach the spies afterwards without rebuilding the graph by hand.
struct Harness {

    let sweep: RoleSweep
    let store: InMemoryStore
    let gateway: SpyGateway
    let reader: RecordingChainReader
    let journal: RecordingJournal
    let log: CollectingLog
    let roster: SpyRoster?

    /// Builds a sweep over the fixture server.
    ///
    /// - Parameters:
    ///   - members: Who is on record.
    ///   - readings: What the chain says, keyed by address.
    ///   - roles: What each member holds in the chat service now.
    ///   - unreadable: Members whose roles cannot be read.
    ///   - refusing: Members whose writes are refused.
    ///   - registry: The collection catalogue, or nil for none.
    ///   - roster: The server listing, or nil for no orphan pass.
    ///   - configuration: What the operator decided.
    ///   - store: Where balances and the baseline go.
    ///   - now: The clock.
    static func build(
        members: [SweptMember],
        readings: [String: WalletCheck] = [:],
        roles: [String: Set<String>] = [:],
        unreadable: Set<String> = [],
        refusing: Set<String> = [],
        registry: (any CollectionRegistry)? = Fixture.catalogue,
        roster: SpyRoster? = nil,
        configuration: GatingConfiguration? = nil,
        store: InMemoryStore = InMemoryStore(),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) async throws -> Harness {
        let gateway = SpyGateway(roles: roles, unreadable: unreadable, refusing: refusing)
        let reader = RecordingChainReader(readings)
        let journal = RecordingJournal()
        let log = CollectingLog()
        // Every member the sweep is told about is a real row in the store.
        // The pass reads the accounts again immediately before it writes, to
        // catch somebody who unlinked while it was running, and a fixture
        // member who was never admitted would read as exactly that. Seeding
        // here rather than in each test also means the write-back path has
        // rows to write to, which is what the store is for.
        let seeded = try await Self.seed(members, into: store)
        let sweep = RoleSweep(
            configuration: try configuration ?? Fixture.configuration(),
            directory: StaticSweepDirectory(members: seeded),
            store: store,
            chain: reader,
            registry: registry,
            gateway: gateway,
            roster: roster,
            journal: journal,
            log: log,
            limits: .unthrottled,
            now: now
        )
        return Harness(
            sweep: sweep,
            store: store,
            gateway: gateway,
            reader: reader,
            journal: journal,
            log: log,
            roster: roster
        )
    }

    /// Writes each fixture member and their accounts into the store, and
    /// hands back the members as the store now names them.
    ///
    /// The key comes back from the store rather than from the fixture,
    /// because the store mints its own and the sweep looks a member up by
    /// the key it was given.
    ///
    /// - Parameters:
    ///   - members: The fixture members.
    ///   - store: Where they go.
    private static func seed(_ members: [SweptMember], into store: InMemoryStore) async throws -> [SweptMember] {
        var seeded: [SweptMember] = []
        seeded.reserveCapacity(members.count)
        for member in members {
            let record = try await store.admitMember(
                externalId: member.member.externalId,
                at: member.member.firstSeenAt
            )
            var accounts: [AccountRecord] = []
            for account in member.accounts {
                let owned = AccountRecord(
                    memberKey: record.key,
                    address: account.address,
                    provenAt: account.provenAt
                )
                try await store.prove(account: owned)
                accounts.append(owned)
            }
            seeded.append(SweptMember(member: record, accounts: accounts))
        }
        return seeded
    }
}
