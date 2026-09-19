import Foundation
import Gating

/// Why a read of the chain did not produce an answer.
///
/// The two pauses are separate cases although they pause the same work, because
/// they are different facts about the world and an operator does different
/// things about them. ``requestBudgetSpent`` is this process deciding it has
/// read enough today, which an operator fixes by raising the budget or reading
/// less often. ``providerRefusedQuota`` is the provider refusing, which an
/// operator fixes with their provider.
public enum ChainError: Error, Equatable, LocalizedError, Sendable {

    /// A string that has to be a canonical address was not one.
    case invalidAddress(String)

    /// The node answered, and said no.
    case api(statusCode: Int, message: String)

    /// The request did not complete, or the answer could not be understood.
    case network(String)

    /// The asset does not exist, as far as the node is concerned.
    case assetNotFound(assetId: UInt64)

    /// The chain says the asset has a different precision from the configured
    /// one. Every balance would be wrong by a factor of ten per missing place.
    case assetDecimalsDisagree(assetId: UInt64, configured: UInt8, onChain: UInt64)

    /// Today's request budget is spent. Reads and signing are paused until the
    /// UTC day rolls over.
    case requestBudgetSpent(until: Date)

    /// The provider refused with its own quota error. Same pause, different
    /// cause.
    case providerRefusedQuota(until: Date)

    /// Today's budget cannot cover a reservation that had to be taken whole.
    ///
    /// Deliberately not a pause and deliberately not ``requestBudgetSpent``.
    /// The day still has requests in it, and they belong to every caller that
    /// can use them one at a time; only the indivisible piece of work was
    /// refused, before it started, having spent nothing.
    case requestBudgetCannotCover(requested: UInt64, remaining: UInt64)

    /// Something a caller needed could not be read, so there is no complete
    /// answer to give it.
    case incompleteRead(gaps: [ChainReadGap])

    /// A pool's reserve account could not be found, so its reserves cannot be
    /// read.
    case poolAddressNotFound(poolId: String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "`\(address)` is not a valid address."
        case .api(let statusCode, let message):
            return "The node refused with \(statusCode): \(message)"
        case .network(let message):
            return "The node could not be reached: \(message)"
        case .assetNotFound(let assetId):
            return "Asset \(assetId) does not exist on this node."
        case .assetDecimalsDisagree(let assetId, let configured, let onChain):
            return "Asset \(assetId) has \(onChain) decimal places on chain, and "
                + "\(TokenProfile.decimalsKey) is set to \(configured). Every balance would be wrong by "
                + "a factor of ten for each missing place, so this refuses to start. Correct "
                + "\(TokenProfile.decimalsKey) or \(TokenProfile.assetIdKey)."
        case .requestBudgetSpent(let until):
            return "Today's request budget is spent. Reads and signing are paused until "
                + "\(UTCDay.stamp(until)) UTC. Raise \(ChainEnvironment.dailyRequestBudget) or read less "
                + "often. This is a count of requests, not a limit on what may be sent."
        case .providerRefusedQuota(let until):
            return "The node's provider refused: its own quota is spent. Reads and signing are paused until "
                + "\(UTCDay.stamp(until)) UTC. Retrying now spends nothing and fixes nothing."
        case .requestBudgetCannotCover(let requested, let remaining):
            return "This work needs \(ChainFormatting.grouped(requested)) requests reserved together and "
                + "\(ChainFormatting.grouped(remaining)) are left of today's budget, so it was refused "
                + "before it started rather than stopping half way through. Nothing was reserved and "
                + "nothing is paused: everything that reads a request at a time carries on. Raise "
                + "\(ChainEnvironment.dailyRequestBudget), or run this earlier in the UTC day."
        case .incompleteRead(let gaps):
            let reasons = gaps.map(\.summary).joined(separator: "; ")
            return "The chain could not be read completely, so there is no answer to give: \(reasons). "
                + "An incomplete reading is not an empty one, and acting on it as though it were zero "
                + "would take something away from somebody who did nothing wrong."
        case .poolAddressNotFound(let poolId):
            return "Pool `\(poolId)` has no reserve account on chain, so its reserves cannot be read."
        }
    }

    // MARK: - Public Methods

    /// Whether an error is a provider refusing because its own quota is spent.
    ///
    /// Recognised by the shape every provider seems to use: a 403 whose message
    /// mentions a quota. Match on both this layer's own pauses and the raw
    /// refusal, because a caller uses this to decide whether to stop asking,
    /// and by the time the error has been wrapped once it is the same fact.
    public static func isProviderQuotaRefusal(_ error: any Error) -> Bool {
        guard let chain = error as? ChainError else { return false }
        switch chain {
        case .providerRefusedQuota, .requestBudgetSpent:
            return true
        case .api(let statusCode, let message):
            return statusCode == 403 && message.lowercased().contains("quota")
        default:
            return false
        }
    }

    /// Whether an error means the account or asset simply is not there.
    ///
    /// A 404 is a **complete** negative answer, not a failed read: the node is
    /// telling us the account holds nothing, which is different from the node
    /// not telling us anything. That distinction is the whole of ``ChainReading``
    /// and it starts here.
    public static func isNotFound(_ error: any Error) -> Bool {
        guard let chain = error as? ChainError, case .api(let statusCode, _) = chain else { return false }
        return statusCode == 404
    }
}
