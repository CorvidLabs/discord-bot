import Foundation

/// Everything impure a game needs, handed in from the outside.
///
/// Clock, randomness and the host's perk configuration are all injected, so a table
/// replays from a seed and a timestamp and every rule can be pinned by a test. Game
/// logic never calls `Date()`, never reaches a global generator, and never reads an
/// environment variable.
public struct GameContext: Sendable {

    // MARK: - Properties

    /// Wall clock for this step. Injected, never read from the system.
    public let now: Date

    /// The player taking the action.
    public let player: GamePlayer

    /// What holding one of the host's collections is worth.
    ///
    /// Carried here rather than reached for as a global, because a global would be
    /// shared mutable state that two tables could disagree about, and because a
    /// test that cannot vary the perks cannot prove the no-perk path is untouched.
    public let perks: GamePerks

    /// Seeded generator, mutated as the game draws.
    public var rng: GameRNG

    // MARK: - Initializers

    /// - Parameters:
    ///   - now: Wall clock for this step.
    ///   - player: The player taking the action.
    ///   - perks: The host's perk configuration. Empty is the ordinary case.
    ///   - rng: Seeded generator for this step.
    public init(now: Date, player: GamePlayer, perks: GamePerks = .empty, rng: GameRNG) {
        self.now = now
        self.player = player
        self.perks = perks
        self.rng = rng
    }

    // MARK: - Public Methods

    /// The perks this player's holdings actually earn, in configuration order.
    public var activePerks: [CollectionPerk] {
        perks.active(for: player.holdings)
    }

    /// The configured perks whose collections could not be read for this
    /// player, in configuration order.
    ///
    /// A table still deals with these outstanding: the find, the wait and the
    /// loot table are all re-decided on the next action at no cost to anybody,
    /// so refusing to play would take away more than the perk is worth. It is
    /// here so that whatever draws the card can say so out loud, because the
    /// failure this type exists for is the silent one.
    public var unresolvedPerks: [CollectionPerk] {
        perks.unresolved(for: player.holdings)
    }
}
