import Chain
@preconcurrency import Foundation
import Gating
import Store

/// The impure half of making a member's roles follow what they hold: the
/// loop, the batching, the run record and the per-member reasons.
///
/// **The decision is not here.** ``Gating/RoleRules/decide(configuration:holdings:currentRoleIds:)``
/// decides, from values, with no clock and no network, and this target does
/// not second-guess it. Everything below is the part that cannot be a
/// function of its arguments: reading a chain, talking to a chat service,
/// writing down what happened, and refusing when the answer is not good
/// enough to act on.
///
/// Four things it does that a straightforward loop would not, each of which
/// the original paid for:
///
/// **A read the bot could not complete is never a demotion.** A failed
/// balance or asset read arrives as ``Gating/Reading/unknown`` rather than a
/// zero, the roles that fact decides drop out of the managed set, and they
/// are preserved (ROLE-1.a). An account missing from the batch entirely is
/// substituted with an explicitly unread reading rather than dropped, because
/// three wallets out of four is a real number and it is not that person's
/// number.
///
/// **The orphan pass records its baseline only after its guard passes.** The
/// guard is ``Gating/RoleRules/orphanSweep(verifiedMemberCount:lastRecordedCount:)``
/// and it answers with either a run carrying a baseline or a refusal carrying
/// none, so there is no count to write on a refusal and the old baseline
/// survives for the next pass.
///
/// **The record is written before the work and again after it**, so a sweep
/// killed part way reads as unfinished rather than as the previous one's
/// success.
///
/// **Every line carries the same run id** (SEE-6), and members whose roles
/// did not change are split into held on purpose and missed, each with a
/// named reason (SEE-2.a).
public actor RoleSweep {

    // MARK: - Properties

    /// What this sweep is called when it spends a chain request.
    ///
    /// A sweep is the instance's own work, not a member's, so it reads with
    /// ``Chain/RequestCaller/system(job:)`` and is not rationed against one
    /// person's share of the day. That is not convenience: a sweep cannot
    /// type fast, it is already bounded by its batch size and the interval
    /// between runs, and holding it to a member's share would break the
    /// product's main job in order to protect it.
    public static let jobName = "role-sweep"

    private let configuration: GatingConfiguration
    private let directory: any SweepDirectory
    private let store: any AccountStore & RoleBaselineStore
    private let chain: any SweepChainReader
    private let registry: (any CollectionRegistry)?
    private let gateway: any RoleGateway
    private let roster: (any ServerRoster)?
    private let journal: any SweepJournal
    private let log: any SweepLog
    private let limits: SweepLimits
    private let now: @Sendable () -> Date

    private var inProgress = false
    private var isLooping = false
    private var loopTask: Task<Void, Never>?
    private var lastReport: SweepReport?

    // MARK: - Initializers

    /// - Parameters:
    ///   - configuration: What the operator decided: the ladder, the
    ///     collections, the pools and the roles.
    ///   - directory: Everybody this instance has on record.
    ///   - store: Where read balances are written back and where the orphan
    ///     pass keeps its baseline.
    ///   - chain: Where readings come from.
    ///   - registry: Which collection each asset belongs to, or nil. Nil
    ///     holds every collection's roles for ever, which is the safe
    ///     direction.
    ///   - gateway: How a decision reaches the chat service.
    ///   - roster: How the whole server is listed, or nil for no orphan pass
    ///     at all.
    ///   - journal: Where the run record and the problems go.
    ///   - log: Where the lines go.
    ///   - limits: How hard to push the chat service.
    ///   - now: The clock, injected so a test pins a run id and an elapsed
    ///     time.
    public init(
        configuration: GatingConfiguration,
        directory: any SweepDirectory,
        store: any AccountStore & RoleBaselineStore,
        chain: any SweepChainReader,
        registry: (any CollectionRegistry)? = nil,
        gateway: any RoleGateway,
        roster: (any ServerRoster)? = nil,
        journal: any SweepJournal,
        log: any SweepLog = SilentSweepLog(),
        limits: SweepLimits = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.directory = directory
        self.store = store
        self.chain = chain
        self.registry = registry
        self.gateway = gateway
        self.roster = roster
        self.journal = journal
        self.log = log
        self.limits = limits
        self.now = now
    }

    // MARK: - Public Methods

    /// Whether a pass is running right now.
    public var isSweeping: Bool { inProgress }

    /// The last pass that actually ran, or nil before one has.
    ///
    /// In memory, and therefore gone after a restart. The question is asked
    /// after a restart at least as often as before one, so the answer that
    /// matters lives in the journal; this is only for a caller that has one
    /// in hand.
    public var lastCompleted: SweepReport? { lastReport }

    /// Starts the periodic loop.
    ///
    /// The first pass is **delayed by whatever is left of the interval**
    /// since the last recorded sweep. Every boot used to sweep, so a restart
    /// loop multiplied the day's chain spend by the restart count, and the
    /// bot then ran out of budget because it kept being restarted for
    /// running out of budget.
    ///
    /// - Parameter interval: How long between passes.
    public func start(interval: TimeInterval = SweepSchedule.defaultInterval) {
        guard !isLooping else { return }
        isLooping = true
        let seconds = SweepSchedule.wholeSeconds(interval)
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.note("Sweeping every \(seconds)s.")
            if let wait = await self.secondsUntilDue(interval: seconds) {
                await self.note(
                    "A sweep ran less than \(seconds)s ago; waiting \(wait)s rather than repeating it."
                )
                try? await Task.sleep(for: .seconds(wait))
            }
            while !Task.isCancelled, await self.isLooping {
                // Unstructured on purpose, and the only place in this file
                // that needs to be. `stop()` cancels this loop, and a pass
                // that was a child of it would be cancelled along with it:
                // every member the pass had not reached yet would be written
                // down as missed, whose sentence blames the chat service for
                // a permission problem that never happened, and the pause
                // between batches would stop pausing. An unstructured task
                // does not inherit cancellation, so an ordinary shutdown
                // leaves the last record in the journal honest, which is the
                // one record SEE-2 and SEE-5 exist to make trustworthy.
                let pass = Task { await self.run() }
                _ = await pass.value
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// Stops the periodic loop.
    ///
    /// **A pass already in flight runs to its end**, and this does not wait
    /// for it. Each pass runs in a task of its own rather than as a child of
    /// the loop, so cancelling the loop cannot reach inside one: a cancelled
    /// pass would record every member it had not reached yet as missed and
    /// blame the chat service for it, which would put a permission outage
    /// that never happened into the journal on every redeploy.
    public func stop() async {
        isLooping = false
        loopTask?.cancel()
        loopTask = nil
        await log.write("Sweep loop stopped.")
    }

    /// How long before the next pass is due, or nil when one is due now.
    ///
    /// - Parameter interval: The configured interval, in whole seconds.
    public func secondsUntilDue(interval: UInt64) async -> UInt64? {
        let last = await journal.lastSweep()
        return SweepSchedule.secondsUntilDue(lastSweep: last?.startedAt, now: now(), interval: interval)
    }

    /// Runs one pass over everybody.
    ///
    /// Never throws. A sweep that cannot finish is a sweep that says so in
    /// its record and its report, because the caller is usually a loop that
    /// has to be running again in half an hour either way.
    @discardableResult
    public func run() async -> SweepReport {
        guard !inProgress else {
            await log.write("A sweep is already running, so this one did nothing rather than doubling up.")
            return .skipped
        }
        inProgress = true
        defer { inProgress = false }

        let startedAt = now()
        let runId = SweepRecord.newRunId(startedAt: startedAt)
        let line = RunLog(log: log, runId: runId)
        let opened = SweepRecord(runId: runId, startedAt: startedAt)
        // Before any work. A sweep that never reaches the end has to read as
        // unfinished, not as the previous sweep's success.
        await journal.begin(opened)
        await line.write("Sweep starting.")

        var problems: [SweepProblem] = []
        var tally = SweepTally.empty
        var memberCount = 0
        var accountCount = 0
        var orphansCleared = 0

        do {
            let members = try await directory.verifiedMembers()
            memberCount = members.count
            let addresses = Self.addresses(of: members)
            accountCount = addresses.count
            await line.write("Visiting \(memberCount) member(s) across \(accountCount) account(s).")

            let catalogue = await readCatalogue(runId: runId, line: line, problems: &problems)

            // One batched read for the whole pass. Reading per member would
            // read each pool's reserves once per member, which is one request
            // per person for a number that does not change between them.
            let byAddress = Self.indexed(
                await chain.check(wallets: addresses, for: .system(job: Self.jobName))
            )

            for batch in members.chunked(into: limits.memberBatchSize) {
                let outcomes = await withTaskGroup(of: MemberSweepOutcome.self) { group in
                    for member in batch {
                        group.addTask {
                            await self.sweep(
                                member: member,
                                readings: byAddress,
                                catalogue: catalogue,
                                line: line
                            )
                        }
                    }
                    var collected: [MemberSweepOutcome] = []
                    collected.reserveCapacity(batch.count)
                    for await outcome in group {
                        collected.append(outcome)
                    }
                    return collected
                }
                for outcome in outcomes {
                    tally.record(outcome)
                }
                if limits.pauseBetweenBatches > .zero {
                    try? await Task.sleep(for: limits.pauseBetweenBatches)
                }
            }

            let orphanPass = await sweepOrphans(runId: runId, members: members, line: line)
            orphansCleared = orphanPass.cleared
            problems.append(contentsOf: orphanPass.problems)

            problems.append(contentsOf: Self.skipProblems(runId: runId, tally: tally, at: now()))
            let finished = opened.ended(
                at: now(),
                memberCount: memberCount,
                accountCount: accountCount,
                orphansCleared: orphansCleared,
                tally: tally
            )
            await journal.end(finished)
            await journal.record(SweepProblem.trimmed(problems, limit: limits.problemLimit))

            let report = SweepReport(
                ran: true,
                runId: runId,
                memberCount: memberCount,
                accountCount: accountCount,
                orphansCleared: orphansCleared,
                tally: tally,
                elapsed: finished.elapsed ?? 0,
                problems: problems
            )
            await line.write("Sweep finished. " + report.summary)
            lastReport = report
            return report
        } catch {
            let detail = String(describing: error)
            await line.write("Sweep stopped before it finished: \(detail)")
            problems.append(
                SweepProblem(
                    at: now(),
                    runId: runId,
                    kind: .sweepFailed,
                    detail: "The sweep stopped before it finished, so some members keep the roles they "
                        + "had. Nothing was taken from anybody. Underlying reason: \(detail)"
                )
            )
            problems.append(contentsOf: Self.skipProblems(runId: runId, tally: tally, at: now()))
            // A sweep that threw is a finished sweep with a reason, not an
            // abandoned one. The two want different responses and must not
            // read the same.
            let finished = opened.ended(
                at: now(),
                memberCount: memberCount,
                accountCount: accountCount,
                orphansCleared: orphansCleared,
                tally: tally,
                failure: detail
            )
            await journal.end(finished)
            await journal.record(SweepProblem.trimmed(problems, limit: limits.problemLimit))

            let report = SweepReport(
                ran: true,
                runId: runId,
                memberCount: memberCount,
                accountCount: accountCount,
                orphansCleared: orphansCleared,
                tally: tally,
                elapsed: finished.elapsed ?? 0,
                problems: problems,
                failure: detail
            )
            lastReport = report
            return report
        }
    }

    // MARK: - Internal Methods

    /// The addresses to read, deduplicated, in the order they were proved.
    ///
    /// The same address twice is one question, not two. One account belongs
    /// to one member in this package's store, but a directory is a seam and
    /// a host's own query is allowed to be wrong in that direction without
    /// costing the day's budget twice.
    internal static func addresses(of members: [SweptMember]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for member in members {
            for address in member.addresses where seen.insert(address).inserted {
                ordered.append(address)
            }
        }
        return ordered
    }

    /// Readings keyed by the address they describe.
    ///
    /// Built once, as a constant, so the batch of members that reads it
    /// shares one immutable value rather than a variable this actor could
    /// still be writing to.
    internal static func indexed(_ readings: [WalletCheck]) -> [String: WalletCheck] {
        var byAddress: [String: WalletCheck] = [:]
        byAddress.reserveCapacity(readings.count)
        for reading in readings {
            byAddress[reading.address] = reading
        }
        return byAddress
    }

    /// The one journal entry a sweep writes about the members it did not
    /// sweep.
    ///
    /// One entry per sweep rather than one per member: the journal is a
    /// fixed-size list, and a sweep that held two hundred members would push
    /// out the overnight failure an operator came to read (SEE-5). A clean
    /// sweep writes nothing at all.
    ///
    /// - Parameters:
    ///   - runId: The sweep this belongs to.
    ///   - tally: What the sweep counted.
    ///   - at: When the sweep ended.
    internal static func skipProblems(runId: String, tally: SweepTally, at instant: Date) -> [SweepProblem] {
        guard tally.held > 0 || tally.missed > 0 else { return [] }
        var parts: [String] = []
        if tally.missed > 0 {
            parts.append("\(tally.missed) missed (\(SweepTally.summary(tally.missedReasons)))")
        }
        if tally.held > 0 {
            parts.append("\(tally.held) held on purpose (\(SweepTally.summary(tally.heldReasons)))")
        }
        if !tally.unreadFacts.isEmpty {
            parts.append("facts not read: \(SweepTally.summary(tally.unreadFacts))")
        }
        return [
            SweepProblem(
                at: instant,
                runId: runId,
                kind: .membersSkipped,
                detail: "Of \(tally.members) member(s): " + parts.joined(separator: ", ")
            )
        ]
    }

    // MARK: - Private Methods

    /// Writes one line from inside the loop's task.
    private func note(_ text: String) async {
        await log.write(text)
    }

    /// Which collection each asset belongs to, or unknown.
    ///
    /// A registry that refuses is a problem to read later and nothing more.
    /// The ladder and the pools are still decided; only the collections are
    /// held (ROLE-4.b).
    private func readCatalogue(
        runId: String,
        line: RunLog,
        problems: inout [SweepProblem]
    ) async -> Reading<[UInt64: String]> {
        guard let registry else {
            if !configuration.collections.isEmpty {
                await line.write("No collection catalogue is configured, so collection roles were left alone.")
            }
            return .unknown
        }
        do {
            return .known(try await registry.assetCollections())
        } catch {
            let detail = "The catalogue of which asset belongs to which collection could not be read, "
                + "so every collection role was left exactly as it was and nothing else was affected. "
                + "Underlying reason: \(error)"
            await line.write(detail)
            problems.append(SweepProblem(at: now(), runId: runId, kind: .registryUnread, detail: detail))
            return .unknown
        }
    }

    /// One member, from readings already in hand.
    ///
    /// Not isolated to the actor, so a batch of members really runs at once
    /// rather than queueing behind this actor's own mailbox. Everything it
    /// touches is immutable and `Sendable`.
    ///
    /// - Parameters:
    ///   - member: Who to sweep.
    ///   - readings: What the chain said, keyed by address.
    ///   - catalogue: Which collection each asset belongs to, or unknown.
    ///   - line: Where this member's lines go, already tagged.
    private nonisolated func sweep(
        member: SweptMember,
        readings: [String: WalletCheck],
        catalogue: Reading<[UInt64: String]>,
        line: RunLog
    ) async -> MemberSweepOutcome {
        // This instance's own name for the member, never the chat service's:
        // a log line and a journal row then carry nothing belonging to a
        // person.
        let memberId = member.member.key.value
        guard !member.accounts.isEmpty else {
            return .held(memberId: memberId, .noAccounts)
        }

        // The same address twice is one wallet, not two. ``addresses(of:)``
        // already deduplicates what is asked of the chain, for exactly the
        // directory that lists one address twice; walking the member's own
        // list unfiltered here would look that address up twice in the batch
        // and hand the same reading to the bridge twice, which sums the
        // balance twice and promotes somebody on money they do not have. The
        // request budget was never the only thing the duplicate cost.
        var mine: [WalletCheck] = []
        var seen: Set<String> = []
        mine.reserveCapacity(member.accounts.count)
        for account in member.accounts where seen.insert(account.address).inserted {
            guard let reading = readings[account.address] else {
                // An account that is not in the batch at all was not read.
                // Dropping it would leave a member made of their other
                // wallets, which is a real number and is not their number.
                mine.append(WalletCheck.unreadable(address: account.address, gap: .notRead))
                continue
            }
            mine.append(reading)
        }

        let holdings = MemberHoldings.fromChain(
            memberId: memberId,
            isVerified: true,
            checks: mine,
            pools: configuration.pools.pools,
            collections: configuration.collections,
            assetCollections: catalogue
        )

        // Written before the chat service is touched. The reading has
        // already been paid for out of the day's budget, and an outage at
        // the chat service is no reason to throw it away.
        await writeBack(readings: mine)

        let current: Set<String>
        do {
            current = try await gateway.currentRoleIds(externalId: member.member.externalId)
        } catch {
            // Deliberately before the decision. A decision computed against
            // an empty set revokes every managed role the member holds, for
            // a member nobody could look at.
            await line.write("\(memberId): current roles could not be read, so nothing was written. \(error)")
            return .missed(memberId: memberId, .rolesUnreadable)
        }

        let decision = RoleRules.decide(
            configuration: configuration,
            holdings: holdings,
            currentRoleIds: current
        )

        guard decision.disposition == .changed else {
            guard decision.isComplete else {
                await line.write("\(memberId): held. " + decision.summary)
                return .held(
                    memberId: memberId,
                    .factsUnread,
                    unknowns: decision.unknowns,
                    heldRoleCount: decision.held.count
                )
            }
            return .unchanged(memberId: memberId)
        }

        // The last guard before the write, and deliberately a second read of
        // the store. Everything above was decided from a snapshot taken when
        // the pass opened, and on a real server a pass is minutes long: a
        // member who unlinked in the middle of it has already had every
        // managed role stripped by the command that unlinked them, and this
        // decision would hand the lot straight back, verified badge and all,
        // to somebody who has now proved nothing. A store that will not
        // answer is not evidence that anybody unlinked, so an unreadable
        // re-check falls through to the snapshot the pass already believed
        // rather than holding a member on a hiccup.
        if let latest = try? await store.accounts(memberKey: member.member.key), latest.isEmpty {
            await line.write("\(memberId): held. " + SweepSkipReason.unlinkedMidSweep.sentence)
            // No role count: `heldRoleCount` means configured roles left
            // alone for an unread fact, and here the whole decision was
            // dropped for a fact that was read perfectly well.
            return .held(memberId: memberId, .unlinkedMidSweep, unknowns: decision.unknowns)
        }

        do {
            try await gateway.apply(decision, externalId: member.member.externalId)
        } catch {
            await line.write("\(memberId): the chat service refused the role change. \(error)")
            return .missed(memberId: memberId, .applyFailed, unknowns: decision.unknowns)
        }
        await line.write("\(memberId): " + decision.summary)
        return .changed(
            memberId: memberId,
            unknowns: decision.unknowns,
            heldRoleCount: decision.held.count
        )
    }

    /// Writes back the figures from readings that completed.
    ///
    /// **Only complete ones.** A short liquidity reading written back would
    /// become the stored figure the linking arithmetic adds to next time,
    /// which turns one bad minute into a number that is wrong until the next
    /// clean sweep.
    ///
    /// - Parameter readings: This member's readings.
    private nonisolated func writeBack(readings: [WalletCheck]) async {
        let instant = now()
        for reading in readings {
            guard
                let direct = reading.directBalance.completeValue,
                let liquidity = reading.liquidityAmount.completeValue
            else { continue }
            // A store that will not take the figures is not a reason to hold
            // roles: the decision was already made from the reading itself.
            _ = try? await store.recordBalances(
                address: reading.address,
                directBaseUnits: direct,
                liquidityBaseUnits: liquidity,
                at: instant
            )
        }
    }

    /// Takes managed roles back from members this bot has no record of.
    ///
    /// The most destructive thing in the package, because with nobody on
    /// record **every** member holding a managed role looks like an orphan
    /// and the whole server is stripped in one pass. That is not
    /// hypothetical: it is what a mistyped store path produces.
    ///
    /// - Parameters:
    ///   - runId: The sweep this belongs to.
    ///   - members: Everybody on record, as the directory listed them.
    ///   - line: Where the lines go.
    private func sweepOrphans(
        runId: String,
        members: [SweptMember],
        line: RunLog
    ) async -> (cleared: Int, problems: [SweepProblem]) {
        guard let roster else { return (0, []) }
        let managed = configuration.allRoleIds
        guard !managed.isEmpty else { return (0, []) }

        // Members, not accounts, and only those who actually proved
        // something. Counting accounts would let one person with four
        // wallets hide the collapse the guard exists to catch.
        let proved = members.filter { !$0.accounts.isEmpty }
        let verifiedIds = Set(proved.map(\.member.externalId))

        let baseline: RoleBaselineRecord?
        do {
            baseline = try await store.loadRoleBaseline()
        } catch {
            // A baseline that will not read is not a missing baseline.
            // Reading it as nothing disarms the halving check in silence, so
            // the pass that could strip the server is the one that does not
            // run.
            let detail = "The orphan pass refused: the baseline it compares against could not be read, "
                + "and a baseline read as nothing would let the next pass strip roles across the "
                + "server. Nothing was taken from anybody. Underlying reason: \(error)"
            await line.write(detail)
            return (0, [SweepProblem(at: now(), runId: runId, kind: .orphanSweepRefused, detail: detail)])
        }

        let verdict = RoleRules.orphanSweep(
            verifiedMemberCount: proved.count,
            lastRecordedCount: baseline?.verifiedMemberCount
        )
        guard case .run(let recordBaseline) = verdict else {
            let detail = (verdict.refusal ?? "The orphan pass refused.")
                + " Check that this bot is pointed at the store you meant."
            await line.write(detail)
            return (0, [SweepProblem(at: now(), runId: runId, kind: .orphanSweepRefused, detail: detail)])
        }

        // Recorded only now, which is the whole reason the guard answers with
        // a decision rather than a `Bool`: a caller that recorded the count it
        // observed during a refusal would lower the bar to the wrong store's
        // own tiny count, and the next pass would pass the halving check
        // against itself and strip the server anyway.
        //
        // Before the server is listed, because the count describes this
        // instance's records and a chat failure below does not make it stale.
        do {
            try await store.save(
                roleBaseline: RoleBaselineRecord(verifiedMemberCount: recordBaseline, recordedAt: now())
            )
        } catch {
            await line.write("The orphan baseline could not be written, so the next pass compares against the "
                + "previous one. \(error)")
        }

        let listed: [ServerMember]
        do {
            listed = try await roster.members(holdingAnyOf: managed)
        } catch {
            let detail = "The orphan pass could not list the server, so no role was taken from anybody. "
                + "This is usually a missing permission for this bot. Underlying reason: \(error)"
            await line.write(detail)
            return (0, [SweepProblem(at: now(), runId: runId, kind: .orphanSweepFailed, detail: detail)])
        }

        // The snapshot this pass opened with is minutes old by the time the
        // server has been listed: the batched chain read, one or two chat
        // round trips per member and a pause between every batch all
        // happened in between. A member who finished verifying inside that
        // window is absent from it, matches every test for an orphan, and
        // would have the roles their verification granted seconds earlier
        // taken straight back off them, with the pass reporting it as a
        // cleared orphan. So the records are read once more, here, with
        // nothing left to do afterwards but the filter.
        let latest: [SweptMember]
        do {
            latest = try await directory.verifiedMembers()
        } catch {
            let detail = "The orphan pass refused: the records could not be read a second time to "
                + "check them against the server listing, and the list this pass opened with is "
                + "too old to strip anybody on. Nothing was taken from anybody. Underlying "
                + "reason: \(error)"
            await line.write(detail)
            return (0, [SweepProblem(at: now(), runId: runId, kind: .orphanSweepRefused, detail: detail)])
        }
        // A union, because a second reading can only ever protect somebody:
        // an id in either list is an id this bot has a record of.
        let known = verifiedIds.union(latest.filter { !$0.accounts.isEmpty }.map(\.member.externalId))

        let orphans = listed.filter { !known.contains($0.externalId) }
        guard !orphans.isEmpty else { return (0, []) }
        await line.write("\(orphans.count) member(s) hold a managed role with nothing on record.")

        var cleared = 0
        var failures = 0
        let configuration = self.configuration
        let gateway = self.gateway
        for batch in orphans.chunked(into: limits.orphanBatchSize) {
            let results = await withTaskGroup(of: Bool.self) { group in
                for orphan in batch {
                    group.addTask {
                        // Read, and empty. Safe only because the guard above
                        // proved the records are worth believing.
                        let holdings = MemberHoldings.unlinked(
                            memberId: orphan.externalId,
                            configuration: configuration
                        )
                        let decision = RoleRules.decide(
                            configuration: configuration,
                            holdings: holdings,
                            currentRoleIds: orphan.roleIds
                        )
                        guard decision.disposition == .changed else { return true }
                        do {
                            try await gateway.apply(decision, externalId: orphan.externalId)
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                var collected: [Bool] = []
                collected.reserveCapacity(batch.count)
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            cleared += results.filter { $0 }.count
            failures += results.filter { !$0 }.count
            if limits.pauseBetweenBatches > .zero {
                try? await Task.sleep(for: limits.pauseBetweenBatches)
            }
        }

        var problems: [SweepProblem] = []
        if failures > 0 {
            let detail = "The orphan pass could not take roles back from \(failures) of "
                + "\(orphans.count) member(s). This is usually this bot's own role sitting below the "
                + "roles it was asked to remove."
            await line.write(detail)
            problems.append(SweepProblem(at: now(), runId: runId, kind: .orphanSweepFailed, detail: detail))
        }
        await line.write("Orphan pass finished: \(cleared) of \(orphans.count) cleared.")
        return (cleared, problems)
    }
}

extension Array {

    /// The array in runs of at most `size`, keeping order.
    ///
    /// - Parameter size: The largest run. Anything under one is treated as
    ///   one, so a misconfigured batch size cannot produce an empty run and
    ///   an endless loop.
    internal func chunked(into size: Int) -> [[Element]] {
        let step = Swift.max(size, 1)
        return stride(from: 0, to: count, by: step).map {
            Array(self[$0..<Swift.min($0 + step, count)])
        }
    }
}
