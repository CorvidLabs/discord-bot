import Foundation

/// The chat service, as this module is willing to know about it.
///
/// Declared over Foundation types, with a role and a member both named by a
/// `String`, exactly as `Gating` already treats a role. That is what lets the
/// boot sequence say "connect" with no chat library existing anywhere in the
/// package, and it is what keeps `Store` two edges away from ever acquiring
/// one: the adapter that knows about snowflakes will depend on this target,
/// and SwiftPM refuses a cycle, so this target can never depend back on it
/// (RT-002, BUILD-4).
///
/// **Nothing in this package conforms to it.** There is no gateway, no slash
/// command and no embed at this commit. The seam and the ordering exist so
/// that the ordering is testable before there is anything to identify with.
public protocol ChatGateway: Sendable {

    /// Identifies to the service.
    ///
    /// Takes the proof that a listener is already bound, which is what makes
    /// the wrong order a compile error rather than a comment somebody moves
    /// (RUN-7.a). See ``ListenerBound``.
    ///
    /// - Parameter listener: What the bind produced.
    func connect(afterBinding listener: ListenerBound) async throws

    /// Every role a member holds now, including ones this build knows nothing
    /// about.
    ///
    /// - Parameter member: The member, as the service names them.
    func roleIds(ofMember member: String) async throws -> Set<String>

    /// Sets a member's roles to exactly this set.
    ///
    /// - Parameters:
    ///   - member: The member, as the service names them.
    ///   - roleIds: Exactly the roles they should hold afterwards, which
    ///     ``Gating/RoleDecision/target`` already carries, including the ones
    ///     this build does not manage and must preserve.
    func setRoles(ofMember member: String, to roleIds: Set<String>) async throws

    /// Stops talking to the service.
    func disconnect() async
}
