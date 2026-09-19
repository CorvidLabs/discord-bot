@preconcurrency import Foundation
import Algorand

/// The real data source: a node, over HTTP.
///
/// Thin on purpose. Everything it does is translate, and the translation is
/// where the interesting decision lives: a node's own error type is turned into
/// this layer's, so that nothing above here has to know which client library is
/// underneath, and so a test can produce any failure the node can produce
/// without a network.
public struct NodeAccountDataSource: AccountDataSource {

    // MARK: - Properties

    private let client: AlgodClient

    // MARK: - Initializers

    /// - Parameters:
    ///   - nodeURL: An absolute `http` or `https` URL.
    ///   - apiToken: The node's token, when it needs one.
    public init(nodeURL: URL, apiToken: String? = nil) {
        self.client = AlgodClient(baseURL: nodeURL, apiToken: apiToken)
    }

    /// Builds the data source the configuration describes.
    public init(configuration: ChainConfiguration) {
        self.init(nodeURL: configuration.nodeURL, apiToken: configuration.apiToken)
    }

    // MARK: - Public Methods

    public func account(address: String) async throws -> ChainAccount {
        let parsed = try parse(address)
        do {
            let information = try await client.accountInformation(parsed)
            return ChainAccount(
                address: address,
                nativeBalance: information.amount,
                holdings: (information.assets ?? []).map {
                    ChainHolding(assetId: $0.assetID, amount: $0.amount, isFrozen: $0.isFrozen)
                },
                createdAssets: (information.createdAssets ?? []).map {
                    Self.details(id: $0.index, params: $0.params)
                }
            )
        } catch {
            throw Self.translate(error)
        }
    }

    public func assetDetails(assetId: UInt64) async throws -> ChainAssetDetails {
        do {
            let information = try await client.assetInfo(assetId)
            return Self.details(id: information.index, params: information.params)
        } catch {
            let translated = Self.translate(error)
            if ChainError.isNotFound(translated) {
                throw ChainError.assetNotFound(assetId: assetId)
            }
            throw translated
        }
    }

    public func isValidAddress(_ address: String) -> Bool {
        (try? Address(string: address)) != nil
    }

    // MARK: - Private Methods

    private func parse(_ address: String) throws -> Address {
        do {
            return try Address(string: address)
        } catch {
            throw ChainError.invalidAddress(address)
        }
    }

    private static func details(id: UInt64, params: AssetParamsResponse) -> ChainAssetDetails {
        ChainAssetDetails(
            id: id,
            creator: params.creator,
            decimals: params.decimals,
            total: params.total,
            unitName: params.unitName,
            name: params.name,
            url: params.url,
            reserveAddress: params.reserve
        )
    }

    /// Turns the client's error into this layer's.
    ///
    /// A status code survives the translation because two of them are
    /// decisions rather than failures: 404 means the account really is not
    /// there, and 403 with a quota in the message means the provider has
    /// refused for the rest of the day. Flattening both into "something went
    /// wrong" is how a missing account becomes a member who sold up.
    private static func translate(_ error: any Error) -> any Error {
        if error is ChainError { return error }
        guard let algorand = error as? AlgorandError else {
            return ChainError.network(error.localizedDescription)
        }
        switch algorand {
        case .apiError(let statusCode, let message):
            return ChainError.api(statusCode: statusCode, message: message)
        case .invalidAddress(let message):
            return ChainError.invalidAddress(message)
        default:
            return ChainError.network(algorand.localizedDescription)
        }
    }
}
