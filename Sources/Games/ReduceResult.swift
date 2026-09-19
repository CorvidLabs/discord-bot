import Foundation

/// The next state of a table plus the only chip movement it is allowed to ask for.
///
/// Chips move by delta, never by an absolute balance, so a replayed or retried
/// action cannot silently overwrite a total that changed underneath it. A reducer
/// that could write a balance would be a reducer that can lose somebody else's
/// concurrent win.
///
/// There is exactly one field here that moves value, it is an `Int` of a score, and
/// nothing in this package can turn it into anything else (`PLAY-1.a`).
public struct ReduceResult<State: Sendable>: Sendable {

    // MARK: - Properties

    /// State after the action.
    public let state: State

    /// Chips won (positive) or staked (negative). Zero when nothing moved.
    public let chipDelta: Int

    /// One line for an audit trail or a card footer.
    public let note: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - state: State after the action.
    ///   - chipDelta: Chips won or staked.
    ///   - note: One line for an audit trail or a footer.
    public init(state: State, chipDelta: Int, note: String? = nil) {
        self.state = state
        self.chipDelta = chipDelta
        self.note = note
    }
}
