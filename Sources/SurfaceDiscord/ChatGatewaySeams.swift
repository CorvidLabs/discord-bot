import Foundation
import Surface

/// Something the chat service sent, with every snowflake already gone.
///
/// The gateway actor above these is written against this and never against a
/// payload, which is what lets the whole of it be driven from a test with no
/// token, no socket and no chat library in the test target's own graph
/// (`BUILD-2`). The translation from a delivered event to one of these is the
/// boundary, and it happens in exactly one type.
public enum ChatEvent: Sendable, Equatable {

    /// The session opened and the service said who this bot is.
    ///
    /// The id is the bot's own account, as the service names it.
    case ready(botExternalId: String)

    /// A dropped session was picked up again, with nothing missed.
    case resumed

    /// A member ran something.
    case interaction(InteractionRequest)
}

/// The gateway connection, as the chat gateway needs it.
///
/// Three verbs and no payload type, so the ordering, the registration and the
/// answering can all be exercised against a double. The live conformance is
/// the only thing that touches a websocket.
public protocol ChatSession: Sendable {

    /// Identifies to the service.
    ///
    /// Called once, and only ever from
    /// ``Runtime/ChatGateway/connect(afterBinding:)``, which cannot itself be
    /// called without proof that a listener is already bound (`RUN-7.a`).
    func identify() async throws

    /// Hands every event to `handler` until the session ends.
    ///
    /// Push rather than a stream, because the only thing above this wants is
    /// to be called: a stream would have to be bridged out of the chat
    /// library's own sequence type and buffered on the way, and the buffer is
    /// where a slow handler turns into a lost interaction.
    ///
    /// **Returning means the session ended**, which is what lowers health.
    ///
    /// - Parameters:
    ///   - handler: What each event is given to.
    ///   - reading: Called once, as soon as this is subscribed and an event
    ///     sent now would reach `handler`. The caller waits for it before
    ///     identifying, because a reader that has only been *scheduled* is
    ///     not a reader: the chat library hands out a fresh continuation at
    ///     the moment of subscription and replays nothing, so an opening
    ///     event fanned out first is gone for good. Source order does not
    ///     order a task against the `await` inside it, so this is a signal
    ///     rather than a comment.
    func deliver(
        to handler: @escaping @Sendable (ChatEvent) async -> Void,
        onceReading reading: @escaping @Sendable () -> Void
    ) async

    /// Closes the session.
    func stop() async
}

/// Reading and writing one member's roles.
///
/// Separate from ``Surface/RoleApplier``, which applies a whole
/// ``Gating/RoleDecision`` and knows about managed and unmanaged roles. This
/// is the flatter pair the composition root's own seam declares: read what
/// they hold, write exactly what they should hold.
public protocol GuildMemberRoles: Sendable {

    /// Every role the member holds now.
    ///
    /// - Parameter member: The member, as the service names them.
    /// - Throws: When the roles could not be read. A failed read is
    ///   **unknown**, never an empty set: acting on an empty set would strip
    ///   a member nobody could look at.
    func roleIds(ofMember member: String) async throws -> Set<String>

    /// Sets the member's roles to exactly this set.
    ///
    /// - Parameters:
    ///   - member: The member, as the service names them.
    ///   - roleIds: Exactly what they should hold afterwards, including the
    ///     roles this build manages nothing about and must preserve.
    func setRoles(ofMember member: String, to roleIds: Set<String>) async throws
}

/// Something that carries out what the router decided.
///
/// ``ReplySending`` is the live one. The protocol exists so the gateway can be
/// watched answering without a client, because "did every interaction get an
/// answer" is the question this layer is for.
public protocol InteractionReplying: Sendable {

    /// Carries out every action, in order.
    ///
    /// - Parameters:
    ///   - actions: What the router decided.
    ///   - request: The interaction they answer.
    func perform(_ actions: [RouterAction], for request: InteractionRequest) async
}
