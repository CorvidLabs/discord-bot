import Foundation

/// Which collection each asset belongs to.
///
/// A sweep cannot work this out from a wallet. It sees asset ids, and only a
/// catalogue built from each collection's creator can say that one of them is
/// a pass and another is not.
///
/// **A registry that throws is not a member holding none of them.** The sweep
/// turns a refusal into ``Gating/Reading/unknown``, which holds every
/// collection's roles exactly where they are and leaves the ladder and the
/// pools to be decided normally (ROLE-4.b). Supplying no registry at all does
/// the same thing, for ever, which is the safe direction and is why it is
/// allowed.
public protocol CollectionRegistry: Sendable {

    /// The collection id each known asset belongs to, keyed by asset id.
    ///
    /// - Throws: When the catalogue could not be built or refreshed. The
    ///   sweep records it as a problem an operator can read afterwards and
    ///   carries on with the roles it can decide.
    func assetCollections() async throws -> [UInt64: String]
}

/// A catalogue that is simply known, for a test or a host that keeps one.
public struct StaticCollectionRegistry: CollectionRegistry {

    // MARK: - Properties

    /// The catalogue handed back every time.
    public let assets: [UInt64: String]

    // MARK: - Initializers

    /// - Parameter assets: The collection id each asset belongs to.
    public init(assets: [UInt64: String]) {
        self.assets = assets
    }

    // MARK: - Public Methods

    public func assetCollections() async throws -> [UInt64: String] {
        assets
    }
}
