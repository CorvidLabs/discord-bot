import Foundation

/// Whether the chat session is open, as the gateway itself sees it.
///
/// Two cases and no detail, because the only thing above this has to decide
/// is whether ``HealthComponent/chat`` is reached. The reason a session ended
/// belongs in the surface's own log, where the words for it exist; a module
/// that links no chat library cannot spell a close code (`BUILD-4`).
public enum ChatSessionState: Sendable, Equatable {

    /// The service acknowledged the session and events are being delivered.
    ///
    /// Sent by the session's own opening event, never by the connect call
    /// returning: the identify is a request for a websocket and returns
    /// before there is one (`SEE-1.a`).
    case open

    /// The session ended, and nothing is being delivered.
    case closed
}

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
/// **One target conforms to it**, and it is the only one that may: the
/// adapter that knows what a snowflake is. A build that does not link that
/// adapter has no conformance at all and runs with no chat surface, which is
/// what the seam being optional in ``RuntimeSeams`` is for.
public protocol ChatGateway: Sendable {

    /// Every variable this surface reads, described the way
    /// ``SettingsCatalogue`` describes this build's own.
    ///
    /// The surface describes itself because this module cannot describe it.
    /// A module that never links a chat library also never learns the words
    /// that library uses, and a variable named here would be a word this
    /// module is not allowed to know (`BUILD-4`). Handing the descriptions
    /// back is what puts the chat variables in the startup report, counts
    /// them as read by the audit, and stops them being refused as belonging
    /// to a part that does not exist.
    var settingsEntries: [SettingsEntry] { get }

    /// Registers what this build offers, then identifies to the service.
    ///
    /// Takes the proof that a listener is already bound, which is what makes
    /// the wrong order a compile error rather than a comment somebody moves
    /// (RUN-7.a). See ``ListenerBound``.
    ///
    /// **Returning is not health.** It also takes the closure the surface
    /// reports its session through, because the only thing that knows the
    /// websocket is open is the session's own opening event, which arrives
    /// after this has returned. A build that treated the return as health
    /// would answer 200 to a deploy gate for a process that is not in the
    /// server (`SEE-1.a`).
    ///
    /// - Parameters:
    ///   - listener: What the bind produced.
    ///   - session: Called with ``ChatSessionState/open`` when the service
    ///     acknowledges the session and with ``ChatSessionState/closed``
    ///     when it ends. Called any number of times, in any order, because a
    ///     session that drops and resumes does both.
    func connect(
        afterBinding listener: ListenerBound,
        reporting session: @escaping @Sendable (ChatSessionState) async -> Void
    ) async throws

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
