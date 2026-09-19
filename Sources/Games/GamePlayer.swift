import Foundation

/// What a game reducer is allowed to read about the player at the table.
///
/// Deliberately small: a reducer may look at the chips, but it moves them only
/// through ``ReduceResult/chipDelta``, never by writing a balance back here. A
/// reducer that could set a balance is a reducer that can overwrite a total which
/// changed underneath it.
public struct GamePlayer: Sendable, Equatable {

    // MARK: - Properties

    /// Stable id for the player.
    ///
    /// Opaque to the engine. It is carried, compared and printed, never parsed, so
    /// nothing here depends on what a host's ids look like.
    public let id: String

    /// Display name for a card.
    public let name: String

    /// Chips the player holds right now.
    ///
    /// A score. Not a token, not a coin, not a balance of anything that can be
    /// sent (`PLAY-1.a`).
    public let chips: Int

    /// Collections the player holds, which is what sizes their perks.
    public let holdings: GameHoldings

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Stable, opaque player id.
    ///   - name: Display name for a card.
    ///   - chips: Chips held right now.
    ///   - holdings: Collections held.
    public init(id: String, name: String, chips: Int, holdings: GameHoldings = .empty) {
        self.id = id
        self.name = name
        self.chips = chips
        self.holdings = holdings
    }
}
