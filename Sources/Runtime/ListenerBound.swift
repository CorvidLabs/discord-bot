import Foundation

/// Proof that a listener is bound, and where.
///
/// This type exists to make one ordering impossible rather than merely
/// documented. A second instance that identified to a chat service before
/// discovering it was a duplicate takes the live instance's session away,
/// because the gateway answers a duplicate identify by invalidating the
/// session, and then dies a moment later on the bind. Under a supervisor that
/// restarts it, the healthy instance is knocked offline every time the doomed
/// one boots and neither keeps a session (RUN-7, RUN-7.a).
///
/// So the bind produces a value, its initialiser is internal to this module,
/// and ``ChatGateway/connect(afterBinding:)`` requires one. An adapter in
/// another target can hold one and cannot make one, so connecting before
/// binding does not compile.
///
/// **What the trick proves, exactly.** It proves a bound listener exists when
/// connect is called. It does not prove the bind happened first in time,
/// because nothing stops a caller holding a value from an earlier bind. What
/// closes that gap is that this module is the only thing that can make one and
/// makes exactly one, in ``BootSequence``, at the gate before the chat gate.
///
/// It is also the reason a bound socket is not health: binding is what tells a
/// second copy that a first one is here, so the endpoint answers `starting`
/// until the parts that must be up are up (SEE-1.a).
public struct ListenerBound: Sendable, Equatable {

    // MARK: - Properties

    /// The address bound.
    public let address: String

    /// The port actually obtained, which is not the configured one when the
    /// configured one was zero.
    public let port: UInt16

    // MARK: - Initializers

    /// Made only by a completed bind, inside this module.
    internal init(address: String, port: UInt16) {
        self.address = address
        self.port = port
    }

    // MARK: - Public Methods

    /// The address and port as one line for the report.
    public var description: String {
        "\(address):\(port)"
    }
}
