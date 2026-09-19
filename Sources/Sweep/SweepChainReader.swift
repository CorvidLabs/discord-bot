import Chain
import Foundation
import Gating

/// Reading the accounts a sweep is about to decide on.
///
/// One method, taking every address at once, because the batching is the
/// whole reason this seam exists: the reader behind it reads each pool's
/// reserves once for the run rather than once per member.
///
/// It takes a ``Chain/RequestCaller`` and does not default it. A sweep is the
/// instance's own work and must pass ``Chain/RequestCaller/system(job:)``, so
/// it is not rationed against one member's share of the day; a default here
/// would make that a thing a host gets right by accident.
public protocol SweepChainReader: Sendable {

    /// A reading for each address, in the order asked for.
    ///
    /// Never throws. A wallet that could not be read comes back as a reading
    /// that says so, because the alternative is one bad address ending a
    /// sweep of two thousand people.
    ///
    /// - Parameters:
    ///   - wallets: The addresses wanted.
    ///   - caller: Whose work this is.
    func check(wallets: [String], for caller: RequestCaller) async -> [WalletCheck]
}

/// The live reader, bound to the pools an operator counts.
///
/// The pools are bound here rather than passed per call because they are
/// configuration and do not change between members, and a per-call parameter
/// is a per-call opportunity to pass the empty list and quietly stop counting
/// anybody's liquidity.
public struct BatchedSweepReader: SweepChainReader {

    // MARK: - Properties

    private let reader: BatchedChainReader
    private let pools: [LiquidityPool]

    // MARK: - Initializers

    /// - Parameters:
    ///   - reader: The batched reader, shared with everything else that reads
    ///     the chain. Sharing it is the point: the day's budget is the whole
    ///     process, and a private reader is only right in a test.
    ///   - pools: The pools to count, as the operator configured them.
    public init(reader: BatchedChainReader, pools: [LiquidityPool]) {
        self.reader = reader
        self.pools = pools
    }

    // MARK: - Public Methods

    public func check(wallets: [String], for caller: RequestCaller) async -> [WalletCheck] {
        await reader.check(wallets: wallets, pools: pools, for: caller)
    }
}
