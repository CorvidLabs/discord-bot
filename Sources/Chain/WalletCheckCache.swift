import Foundation
import Gating

/// Recently read wallets, so the same question does not become traffic.
///
/// Two separate ideas, kept separate because they answer different problems.
/// The **cache** holds an answer that is good enough to reuse for a while. The
/// **cooldown** refuses to ask the chain about the same wallet again too soon,
/// even when the caller says it wants a fresh reading, because the caller is
/// often a member typing in a channel and there is no upper bound on how fast
/// people type.
///
/// **Only a complete reading is ever cached.** Caching an incomplete one would
/// take a single failed request and serve it as this wallet's balance for the
/// whole lifetime of the entry, which turns one bad moment into minutes of
/// wrong answers.
public actor WalletCheckCache {

    // MARK: - Properties

    private let reader: BatchedChainReader
    private let pools: [LiquidityPool]
    private var cached: ExpiringMap<String, WalletCheck>
    private var cooldown: ExpiringMap<String, Bool>

    // MARK: - Initializers

    /// - Parameters:
    ///   - reader: Where fresh readings come from.
    ///   - pools: The pools to count.
    ///   - lifetimes: How long an answer and a cooldown last.
    public init(reader: BatchedChainReader, pools: [LiquidityPool], lifetimes: ChainCacheLifetimes) {
        self.reader = reader
        self.pools = pools
        self.cached = ExpiringMap(lifetime: lifetimes.walletCheck)
        self.cooldown = ExpiringMap(lifetime: lifetimes.walletCheckCooldown)
    }

    // MARK: - Public Methods

    /// Readings for these wallets, in the order asked for.
    ///
    /// **The cooldown bounds one wallet and the share bounds one member**, and
    /// the two are not the same thing. A member with ten proved accounts can
    /// draw ten reads per cooldown window all day, which is why the caller is
    /// named here and charged by the governor rather than left to the
    /// cooldown to contain.
    ///
    /// - Parameters:
    ///   - wallets: The wallets wanted.
    ///   - caller: Whose work this is. There is no default: a batch this cache
    ///     reads for a sweep and a batch it reads for a member's command are
    ///     the same call, and only the call site knows which it is.
    ///   - forceFresh: Reads again even when a cached answer is still usable.
    ///     The cooldown is not overridden: it exists precisely to bound how
    ///     often this can be forced.
    ///   - now: Injected so a test pins the lifetimes.
    public func check(
        wallets: [String],
        for caller: RequestCaller,
        forceFresh: Bool = false,
        now: Date = Date()
    ) async -> [WalletCheck] {
        var answers: [String: WalletCheck] = [:]
        var toRead: [String] = []
        // The same address twice in one list is one question, not two. Checking
        // `answers` alone would not have caught it: nothing is written there
        // for a wallet that has to be read, so a duplicate was appended twice
        // and cost two requests from the day's budget for one answer.
        var seen: Set<String> = []

        for wallet in wallets where seen.insert(wallet).inserted {
            if !forceFresh || isOnCooldown(wallet, now: now), let hit = cached.value(for: wallet, now: now) {
                answers[wallet] = hit
            } else {
                toRead.append(wallet)
            }
        }

        if !toRead.isEmpty {
            let fresh = await reader.check(wallets: toRead, pools: pools, for: caller, now: now)
            for reading in fresh {
                answers[reading.address] = reading
                cooldown.set(true, for: reading.address, now: now)
                // Complete readings only. An unreadable wallet is asked about
                // again next time rather than remembered as empty.
                if reading.combinedBalance.isComplete {
                    cached.set(reading, for: reading.address, now: now)
                }
            }
        }

        return wallets.compactMap { answers[$0] }
    }

    /// Whether this wallet was read recently enough that it should be left
    /// alone.
    public func isOnCooldown(_ address: String, now: Date = Date()) -> Bool {
        cooldown.contains(address, now: now)
    }

    /// Whether this wallet may be read on demand right now.
    public func shouldCheck(_ address: String, now: Date = Date()) -> Bool {
        !isOnCooldown(address, now: now)
    }

    /// Forgets one wallet's answer and its cooldown, so the next read is fresh.
    ///
    /// Called when something is known to have changed, such as a wallet being
    /// linked or unlinked: waiting out a five minute lifetime to show somebody
    /// the balance they just proved they own is the sort of thing people
    /// report as the bot being broken.
    public func invalidate(_ address: String) {
        cached.remove(address)
        cooldown.remove(address)
    }

    /// Forgets everything.
    public func invalidateAll() {
        cached.removeAll()
        cooldown.removeAll()
    }

    /// How many answers are held.
    public var cachedCount: Int { cached.count }

    /// How many wallets are within their cooldown.
    public var cooldownCount: Int { cooldown.count }
}
