import Chain
import Foundation
import Gating
import Store
@testable import Sweep

/// A reader that answers from a fixed table and remembers who asked.
///
/// The caller is recorded because "the sweep is the instance's own work" is
/// a rule nothing else can check: pass a member's key here and the sweep is
/// rationed against one person's share of the day, and the only symptom is a
/// sweep that stops half way through on a busy afternoon.
actor RecordingChainReader: SweepChainReader {

    private let table: [String: WalletCheck]
    private(set) var callers: [RequestCaller] = []
    private(set) var asked: [[String]] = []

    init(_ table: [String: WalletCheck]) {
        self.table = table
    }

    func check(wallets: [String], for caller: RequestCaller) async -> [WalletCheck] {
        callers.append(caller)
        asked.append(wallets)
        return wallets.compactMap { table[$0] }
    }
}

/// A chat service that remembers what it was asked to do.
actor SpyGateway: RoleGateway {

    /// What each member holds now.
    private var roles: [String: Set<String>]
    /// Members whose roles cannot be read.
    private let unreadable: Set<String>
    /// Members whose writes are refused.
    private let refusing: Set<String>

    private(set) var applied: [String: RoleDecision] = [:]
    private(set) var reads: [String] = []

    init(
        roles: [String: Set<String>] = [:],
        unreadable: Set<String> = [],
        refusing: Set<String> = []
    ) {
        self.roles = roles
        self.unreadable = unreadable
        self.refusing = refusing
    }

    func currentRoleIds(externalId: String) async throws -> Set<String> {
        reads.append(externalId)
        if unreadable.contains(externalId) {
            throw SpyFailure.refused
        }
        return roles[externalId] ?? []
    }

    func apply(_ decision: RoleDecision, externalId: String) async throws {
        if refusing.contains(externalId) {
            throw SpyFailure.refused
        }
        applied[externalId] = decision
        // Character for character what `SurfaceDiscord.DiscordRoleApplier`
        // sends. Written the long way round once and the two drifted: the
        // adapter unioned `decision.held`, which turns "leave this alone
        // because nobody read it" into "grant it", and this double could not
        // see it because it was doing the arithmetic correctly by another
        // route. A double that paraphrases the thing it stands in for proves
        // nothing about the thing it stands in for.
        let current = roles[externalId] ?? []
        roles[externalId] = decision.target
            .intersection(decision.managed)
            .union(current.subtracting(decision.managed))
            .subtracting(decision.revoked)
    }

    func rolesHeld(by externalId: String) -> Set<String> {
        roles[externalId] ?? []
    }
}

/// A server listing, which may refuse.
actor SpyRoster: ServerRoster {

    private let listing: [ServerMember]
    private let fails: Bool
    private(set) var listCount = 0

    init(_ listing: [ServerMember], fails: Bool = false) {
        self.listing = listing
        self.fails = fails
    }

    func members(holdingAnyOf roleIds: Set<String>) async throws -> [ServerMember] {
        listCount += 1
        if fails {
            throw SpyFailure.refused
        }
        return listing.filter { !$0.roleIds.isDisjoint(with: roleIds) }
    }
}

/// A directory that can refuse, so the sweep's own failure path is exercised.
struct FailingDirectory: SweepDirectory {

    func verifiedMembers() async throws -> [SweptMember] {
        throw SpyFailure.refused
    }
}

/// A catalogue that refuses.
struct FailingRegistry: CollectionRegistry {

    func assetCollections() async throws -> [UInt64: String] {
        throw SpyFailure.refused
    }
}

/// A journal that keeps every write in order, so "before the work and again
/// after it" can be asserted rather than believed.
actor RecordingJournal: SweepJournal {

    private(set) var writes: [SweepRecord] = []
    private(set) var problems: [SweepProblem] = []

    func begin(_ record: SweepRecord) async {
        writes.append(record)
    }

    func end(_ record: SweepRecord) async {
        writes.append(record)
    }

    func record(_ problems: [SweepProblem]) async {
        self.problems.append(contentsOf: problems)
    }

    func lastSweep() async -> SweepRecord? {
        writes.last
    }

    func recentProblems() async -> [SweepProblem] {
        problems
    }
}

/// A log that keeps every line, in the order it was written.
actor CollectingLog: SweepLog {

    private(set) var lines: [String] = []

    func write(_ line: String) async {
        lines.append(line)
    }
}

/// What a double refuses with.
enum SpyFailure: Error {
    case refused
}

/// A latch a test opens when it is ready.
///
/// Used to hold a sweep inside its own run so a second one can be started
/// while the first is still going, which is the only way to exercise the
/// overlap guard without racing on timing.
actor GateSignal {

    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    /// How many callers have reached the latch.
    private(set) var arrivals = 0

    /// Waits until the latch is opened.
    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// Opens the latch and lets everybody through.
    func release() {
        isOpen = true
        let waiting = continuations
        continuations = []
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// A directory that holds the sweep at the latch before answering.
struct GatedDirectory: SweepDirectory {

    let gate: GateSignal
    let members: [SweptMember]

    func verifiedMembers() async throws -> [SweptMember] {
        await gate.wait()
        return members
    }
}
