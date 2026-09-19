import Foundation

/// The decision itself: given what a member holds and what the operator
/// configured, which roles should they have.
///
/// This is the most valuable thing in the module and the only one worth
/// arguing about. In the original it was spread across a sweep loop, a role
/// service and a Discord client, tangled with a database, a rate limiter and
/// an HTTP call, and the only way to find out what it did was to run it
/// against a real server. Here it is a function from values to values: no
/// Discord, no chain, no clock, no store. Every rule below can be pinned by a
/// test, which is the only reason anybody should trust something that takes
/// roles away from people.
///
/// Two rules govern everything in it.
///
/// **A role outside ``RoleDecision/managed`` is never touched.** The bot adds
/// and removes only what the operator told it about. A badge a moderator hands
/// out by hand survives every sweep.
///
/// **A fact nobody read manages nothing.** The roles that fact decides drop
/// out of the managed set, so they are preserved rather than stripped. Silence
/// from a data provider is not evidence that somebody sold up, and acting as
/// though it were is the failure that actually matters here (ROLE-1.a). That
/// holds for a role two facts decide as well: one collection's count does not
/// give it the right to strip a badge the collection beside it also grants.
public enum RoleRules: Sendable {

    // MARK: - Public Methods

    /// Which roles this member should hold, and which they should not.
    ///
    /// - Parameters:
    ///   - configuration: What the operator decided.
    ///   - holdings: What the member holds, and how much of it was read.
    ///   - currentRoleIds: Every role the member holds now, including ones
    ///     this bot knows nothing about.
    public static func decide(
        configuration: GatingConfiguration,
        holdings: MemberHoldings,
        currentRoleIds: Set<String>
    ) -> RoleDecision {
        var managed: Set<String> = []
        var wanted: Set<String> = []
        // Every role an unread fact would have decided, collected as the
        // unreads are found and taken back out of `managed` at the end.
        // Accumulating `managed` per fact is not enough on its own: when two
        // facts decide one role id, the fact that was read puts the role in
        // and the fact that was not read cannot take it out again.
        var blocked: Set<String> = []
        var unknowns: [GatingUnknown] = []

        func note(_ unknown: GatingUnknown) {
            guard !unknowns.contains(unknown) else { return }
            unknowns.append(unknown)
        }

        // Having verified at all is this bot's own record, so it is always
        // decidable and therefore always managed.
        if let verifiedRoleId = configuration.verifiedRoleId {
            managed.insert(verifiedRoleId)
            if holdings.isVerified {
                wanted.insert(verifiedRoleId)
            }
        }

        // A server that counts no pools has nothing to add to the balance, so
        // the ladder is decided from what the member holds directly. Waiting
        // for a pooled half that nobody will ever read is how a ladder freezes
        // for good: there is no pool to read, so the natural caller leaves the
        // positions unread, and every rung in the server is then held for ever
        // on a fact that does not exist.
        let combinedBalance = configuration.pools.isEmpty
            ? holdings.directBalance
            : holdings.combinedBalance
        let standing = configuration.ladder.standing(for: combinedBalance)

        // The ladder. Rungs stack, so somebody on the fourth keeps the three
        // under it.
        if !configuration.ladder.rungs.isEmpty {
            switch combinedBalance {
            case .known(let baseUnits):
                for rung in configuration.ladder.rungs {
                    if let roleId = configuration.roleId(for: rung) {
                        managed.insert(roleId)
                    }
                }
                for rung in configuration.ladder.rungsToAssign(for: baseUnits) {
                    if let roleId = configuration.roleId(for: rung) {
                        wanted.insert(roleId)
                    }
                }
            case .unknown:
                // Both halves of the combined balance are named, because an
                // operator fixing this needs to know which one failed. A
                // pooled balance that came back short used to be counted as
                // zero, which dropped a member several rungs for a provider
                // error that lasted a minute.
                if !holdings.directBalance.isKnown {
                    note(.balance)
                }
                if !configuration.pools.isEmpty, !holdings.liquidityPositions.isKnown {
                    note(.liquidityPositions)
                }
                for rung in configuration.ladder.rungs {
                    if let roleId = configuration.roleId(for: rung) {
                        blocked.insert(roleId)
                    }
                }
            }
        }

        // The collections, each deciding its own roles from its own count. A
        // collection whose count was not read holds its roles and does not
        // stop the others being decided.
        for collection in configuration.collections.collections where !collection.allRoleIds.isEmpty {
            switch holdings.count(ofCollection: collection.id) {
            case .known(let count):
                managed.formUnion(collection.allRoleIds)
                if let roleId = collection.roleId, count > 0 {
                    wanted.insert(roleId)
                }
                for rung in collection.rungsToAssign(count: count) {
                    wanted.insert(rung.roleId)
                }
            case .unknown:
                blocked.formUnion(collection.allRoleIds)
                note(.collection(id: collection.id))
            }
        }

        // The pools: one badge for providing anywhere, and a badge per pool.
        let poolRoleIds = configuration.pools.allRoleIds
        if !poolRoleIds.isEmpty {
            switch holdings.liquidityPositions {
            case .known(let positions):
                managed.formUnion(poolRoleIds)
                let providing = positions.filter(\.isProviding)
                if let providerRoleId = configuration.pools.providerRoleId, !providing.isEmpty {
                    wanted.insert(providerRoleId)
                }
                for position in providing {
                    // A position in a pool the operator has since removed
                    // from the catalogue grants nothing, rather than being
                    // guessed at.
                    if let roleId = configuration.pools.pool(id: position.poolId)?.roleId {
                        wanted.insert(roleId)
                    }
                }
            case .unknown:
                blocked.formUnion(poolRoleIds)
                note(.liquidityPositions)
            }
        }

        // A role an unread fact decides is nobody's to take away, even when
        // another fact that WAS read also decides it: an operator may point
        // two collections at one badge, or the provider badge at a rung's
        // role, and no loader forbids either. A role a read fact positively
        // wants stays managed, so it is still granted and `granted` stays
        // inside `managed`; the rest come out, which is what puts them in
        // `held` rather than in `revoked`.
        managed.subtract(blocked.subtracting(wanted))

        // Everything the bot does not manage is carried over untouched. This
        // one line is what keeps a hand-granted badge, and what keeps a rung
        // whose balance nobody could read.
        let target = currentRoleIds.subtracting(managed).union(wanted)

        return RoleDecision(
            memberId: holdings.memberId,
            standing: standing,
            combinedBalance: combinedBalance,
            managed: managed,
            target: target,
            granted: target.subtracting(currentRoleIds),
            revoked: currentRoleIds.intersection(managed).subtracting(target),
            held: configuration.allRoleIds.subtracting(managed),
            unknowns: unknowns
        )
    }

    // MARK: - Sweeping away roles nobody is owed

    /// Smallest recorded baseline the drop check applies to.
    ///
    /// Below this a server is too small for a halving to mean anything: a
    /// test server going from five verified members to three is a Tuesday.
    public static let orphanSweepBaselineMinimum = 10

    /// The drop check refuses when the count fell below this fraction of the
    /// last recorded one.
    public static let orphanSweepDropDivisor = 2

    /// Whether it is safe to take managed roles away from members who have no
    /// verified account, and what to record if it is.
    ///
    /// The sweep that does this is the most destructive thing the bot can do,
    /// because with zero verified members **every** member holding a managed
    /// role looks like an orphan and the whole server is stripped in one
    /// pass. That is not hypothetical: it is what a wrong database path
    /// produces, and a wrong database path is a typo.
    ///
    /// Zero is not enough of a floor on its own, because a wrong path that
    /// still has one leftover row passes it. So when a baseline of at least
    /// ``RoleRules/orphanSweepBaselineMinimum`` was recorded, a count that has
    /// fallen to under half of it is refused as well. No baseline falls back to
    /// the zero floor alone, which is what a first run has. An unreadable
    /// record is **not** a missing one: a store refuses it rather than
    /// answering with nothing, because a corrupt baseline read as nothing
    /// disarms this check in silence.
    ///
    /// **The baseline travels with the decision, and only with a ``run``.**
    /// That is the whole reason this is not a `Bool`. A refusal must leave the
    /// old baseline exactly where it is: a caller that records the count it
    /// just observed lowers the bar to the wrong database's own tiny count,
    /// and the next sweep passes the halving check against itself and strips
    /// the server anyway. The guard would then buy one interval and nothing
    /// more. With a decision there is no count to record on a refusal, so the
    /// mistake cannot be written.
    public enum OrphanSweep: Sendable, Equatable {

        /// The sweep may run, and this is the count to record as the new
        /// baseline once it does. Nothing else is.
        case run(recordBaseline: Int)

        /// The sweep must not run. Nothing is recorded, so the baseline it was
        /// compared against survives for the next one.
        case refuse(reason: String)

        // MARK: - Public Methods

        /// True when the sweep may run.
        public var mayRun: Bool {
            switch self {
            case .run: return true
            case .refuse: return false
            }
        }

        /// Why the sweep was refused, or nil when it was not.
        public var refusal: String? {
            switch self {
            case .run: return nil
            case .refuse(let reason): return reason
            }
        }
    }

    /// Whether to sweep, and the baseline to record if so.
    ///
    /// - Parameters:
    ///   - verifiedMemberCount: Members with a verified account right now.
    ///   - lastRecordedCount: What the last sweep that ran recorded, or nil.
    public static func orphanSweep(verifiedMemberCount: Int, lastRecordedCount: Int?) -> OrphanSweep {
        guard verifiedMemberCount > 0 else {
            return .refuse(
                reason: "No member has a verified account, so every member holding a managed role "
                    + "would look like an orphan. Roles were left alone rather than stripped "
                    + "across the server. Check the store this bot was pointed at."
            )
        }
        guard
            let lastRecordedCount,
            lastRecordedCount >= orphanSweepBaselineMinimum
        else { return .run(recordBaseline: verifiedMemberCount) }

        // Rounded up, so half of an odd baseline is the half the sentence
        // above means rather than the one integer division gives: 200 of a
        // recorded 401 has fallen below half and is refused.
        let fewestAllowed = (lastRecordedCount + orphanSweepDropDivisor - 1) / orphanSweepDropDivisor
        guard verifiedMemberCount >= fewestAllowed else {
            return .refuse(
                reason: "\(verifiedMemberCount) members have a verified account and the last sweep "
                    + "that ran recorded \(lastRecordedCount). More than half of them have gone, "
                    + "so roles were left alone rather than stripped across the server. Check the "
                    + "store this bot was pointed at."
            )
        }
        return .run(recordBaseline: verifiedMemberCount)
    }
}

extension MemberHoldings {

    // MARK: - Unlinked members

    /// Holdings for somebody with no verified account: read, and empty.
    ///
    /// Every configured collection is filled in as a read zero, because a
    /// member with no account provably holds nothing rather than holding
    /// something nobody looked at. Passing this to
    /// ``RoleRules/decide(configuration:holdings:currentRoleIds:)`` revokes
    /// every managed role and leaves every other role alone.
    ///
    /// **Only safe once the caller has proved the member really is unlinked.**
    /// Building this from an empty read is how a whole server gets stripped;
    /// see ``RoleRules/orphanSweep(verifiedMemberCount:lastRecordedCount:)``
    /// for the guard that belongs in front of it.
    public static func unlinked(memberId: String, configuration: GatingConfiguration) -> MemberHoldings {
        var counts: [String: Reading<Int>] = [:]
        for collection in configuration.collections.collections {
            counts[collection.id] = .known(0)
        }
        return MemberHoldings(
            memberId: memberId,
            isVerified: false,
            directBalance: .known(0),
            liquidityPositions: .known([]),
            collectionCounts: counts
        )
    }
}
