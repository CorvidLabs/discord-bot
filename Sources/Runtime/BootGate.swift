import Foundation

/// The gates, in the one order they run in.
///
/// Not reorderable by configuration, and the order is the whole design
/// (RT-008). Each row is a sentence about why it is where it is.
///
/// | # | Gate | What it can refuse with |
/// |---|------|-------------------------|
/// | 1 | Banner | never |
/// | 2 | Configuration | 78, naming the variable |
/// | 3 | Store | 69, held or unusable |
/// | 4 | Budget restore | 70 |
/// | 5 | Bind | 69, address in use |
/// | 6 | Chain | 78, only on a contradiction |
/// | 7 | Chat | 78, if a chat variable is set |
/// | 8 | Loops | never |
///
/// **The banner is first, before the settings are even read**, because a
/// start that then refuses is still a start and it is the one a contributor
/// sees most often (BUILD-3.b).
///
/// **Configuration is next** because it is the only gate that touches
/// nothing, so a wrong variable costs no lock, no socket and no request.
///
/// **The store comes before the socket.** The bot this was ported from binds
/// first, on the grounds that binding is how a process discovers another
/// copy. That reasoning is right and the conclusion moves, because the store
/// takes an exclusive lease on a sibling of its file before it opens the
/// handle, and the lease asks the exact question: whether another instance is
/// using **this data**. A port clash only approximates it, and approximates it
/// wrongly in the case this product has to support, where one machine hosts
/// several communities with a store and a port each. Both still happen long
/// before anything could identify (RUN-7.a).
///
/// **The budget restore sits between them** because it needs the store and
/// must happen before the first request, or a restart hands the process a
/// fresh day's allowance (RUN-8.b).
public enum BootGate: String, Sendable, Equatable, CaseIterable {

    /// Says whether this build can move anything.
    case banner

    /// Reads and checks everything, touching nothing.
    case configuration

    /// Takes the lease, opens the store, migrates it.
    case store

    /// Puts today's request count back into the one governor.
    case budget

    /// Binds the health endpoint. Produces ``ListenerBound``.
    case bind

    /// Asks the node whether the asset is the one the operator described.
    case chain

    /// Identifies to the chat service. Nothing to connect to yet.
    case chat

    /// Starts the loops. Nothing to start yet.
    case loops
}
