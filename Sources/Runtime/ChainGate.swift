import Chain
import Foundation
import Gating

/// What the node said about the asset when the boot asked.
public enum ChainGateOutcome: Sendable, Equatable {

    /// The node confirmed the asset and its precision.
    case confirmed

    /// The operator turned the check off, so nothing was asked.
    case notProbed(reason: String)

    /// The node did not answer, or answered something that says nothing about
    /// the configuration. The instance stays up and `starting`.
    case unreached(reason: String)

    /// The node contradicted the configuration. The boot stops.
    case contradiction(BootFailure)
}

/// Asking the node, once, whether the asset is the one the operator described.
///
/// **It refuses on some answers and not others, and the line matters.** A node
/// that says the asset does not exist, or that its precision is different, has
/// contradicted the configuration, and that is a mistake an operator can fix
/// in a minute once they are told. A node that does not answer at all has said
/// nothing about the configuration: if that stopped the boot, a provider
/// having a bad five minutes at the moment a supervisor restarts the process
/// would turn a blip into a bot that stays down until somebody notices. The
/// `starting` answer exists to carry exactly that state (ADOPT-12.a, RUN-3).
///
/// A 401 or a 403 that is not the provider's quota refusal is treated as a
/// contradiction, because it is the operator's token that is wrong and no
/// amount of waiting fixes it.
public enum ChainGate: Sendable {

    // MARK: - Properties

    /// How long the first retry waits.
    public static let firstRetryDelay: Duration = .seconds(5)

    /// The longest a retry ever waits.
    ///
    /// A ceiling rather than an unbounded doubling, so a node down overnight
    /// cannot spend the day's budget on retries, and a node that comes back
    /// moves the health answer from `starting` to `ok` without a restart.
    public static let maximumRetryDelay: Duration = .seconds(900)

    // MARK: - Public Methods

    /// The wait before the retry after one that waited `previous`.
    ///
    /// Doubling to the ceiling and staying there. Pure, so the schedule is
    /// pinned by a test rather than by waiting fifteen minutes for one.
    ///
    /// - Parameter previous: What the last wait was, or nil before the first.
    public static func nextRetryDelay(after previous: Duration?) -> Duration {
        guard let previous else { return firstRetryDelay }
        let doubled = previous * 2
        return doubled > maximumRetryDelay ? maximumRetryDelay : doubled
    }

    /// Asks the node once and classifies the answer.
    ///
    /// - Parameter reader: The reader, sharing the process's one governor.
    public static func probe(reader: ChainReader) async -> ChainGateOutcome {
        let configuration = await reader.configuration
        guard configuration.verifiesAssetDecimals else {
            return .notProbed(
                reason: "\(ChainEnvironment.verifyAssetDecimals) is off, so the node was not "
                    + "asked at start whether asset \(configuration.token.assetId) exists or how "
                    + "many decimal places it has. Every balance this reads is divided by "
                    + "\(TokenProfile.decimalsKey) either way."
            )
        }
        do {
            // The instance's own work, not a member's: a boot check is not a
            // person and must not be rationed against one member's share of
            // the day. `RequestCaller.system` is the case that says so.
            try await reader.verifyAssetDecimals(for: .system(job: "boot.assetDecimals"))
            return .confirmed
        } catch {
            return classify(error)
        }
    }

    /// Which of the four answers an error is.
    ///
    /// - Parameter error: What the read threw.
    public static func classify(_ error: any Error) -> ChainGateOutcome {
        // Asked before the status code is looked at, because a provider's own
        // quota refusal arrives as a 403 and is an outage rather than a wrong
        // credential: waiting fixes it and editing the token does not.
        if ChainError.isProviderQuotaRefusal(error) {
            return .unreached(
                reason: describe(error)
            )
        }
        guard let chain = error as? ChainError else {
            return .unreached(reason: describe(error))
        }
        switch chain {
        case .assetNotFound(let assetId):
            return .contradiction(
                BootFailure(
                    variable: TokenProfile.assetIdKey,
                    summary: "The node has never heard of asset \(assetId).",
                    remedy: "Correct \(TokenProfile.assetIdKey), or point "
                        + "\(ChainEnvironment.nodeURL) at the network your asset is on.",
                    code: .configuration
                )
            )
        case let .assetDecimalsDisagree(assetId, configured, onChain):
            return .contradiction(
                BootFailure(
                    variable: TokenProfile.decimalsKey,
                    summary: "Asset \(assetId) has \(onChain) decimal places on chain and "
                        + "\(TokenProfile.decimalsKey) is \(configured). Every balance would be "
                        + "wrong by a factor of ten for each missing place.",
                    remedy: "Correct \(TokenProfile.decimalsKey) or \(TokenProfile.assetIdKey).",
                    code: .configuration
                )
            )
        case let .api(statusCode, message) where statusCode == 401 || statusCode == 403:
            return .contradiction(
                BootFailure(
                    variable: ChainEnvironment.apiToken,
                    summary: "The node refused with \(statusCode): \(message)",
                    remedy: "That is a credential this node will not accept, and waiting does "
                        + "not fix it. Check \(ChainEnvironment.apiToken) and "
                        + "\(ChainEnvironment.nodeURL).",
                    code: .configuration
                )
            )
        // The two caller-share refusals are listed rather than folded into a
        // default, so that adding a case to `ChainError` breaks this switch
        // instead of silently reading as "the node could not be reached".
        // Neither can actually happen here: the boot probe is
        // `RequestCaller.system`, which carries no share. If one ever arrives
        // it means a share was applied to the instance's own work, and
        // reporting that as unreached is the honest answer, because the node
        // was indeed not reached and the operator should see the reason.
        case .api, .network, .invalidAddress, .requestBudgetSpent, .providerRefusedQuota,
             .requestBudgetCannotCover, .callerShareSpent, .callerShareCannotCover,
             .incompleteRead, .poolAddressNotFound:
            return .unreached(reason: describe(chain))
        }
    }

    // MARK: - Private Methods

    private static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? "\(error)"
    }
}
