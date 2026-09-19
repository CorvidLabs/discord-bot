import Foundation
import Gating

/// Putting one decision into effect in the chat service.
///
/// Two calls rather than one, and the split is the point. Reading a member's
/// current roles can fail, and a failed read is **unknown**, never an empty
/// set: a decision computed against no roles at all revokes every managed
/// role the member has, for a member nobody could look at. So the read
/// throws, and ``RoleSweep`` records that member as missed instead of
/// writing anything (ROLE-1.a).
///
/// Declared here rather than imported so this target links no chat library
/// and no surface. The signatures are deliberately the ones the Discord
/// adapter in this package already satisfies, so wiring it up is one empty
/// extension rather than a shim with its own bugs.
public protocol RoleGateway: Sendable {

    /// Every role this member holds now, including ones this bot manages
    /// nothing about.
    ///
    /// - Parameter externalId: The member, as the chat service names them.
    /// - Throws: When the roles could not be read. The caller holds rather
    ///   than applying a decision built against an empty set.
    func currentRoleIds(externalId: String) async throws -> Set<String>

    /// Applies one decision.
    ///
    /// **Only ``Gating/RoleDecision/managed`` may be touched.** A badge a
    /// moderator hands out by hand is outside that set and survives every
    /// sweep (ROLE-5).
    ///
    /// - Parameters:
    ///   - decision: What the rules decided.
    ///   - externalId: The member, as the chat service names them.
    func apply(_ decision: RoleDecision, externalId: String) async throws
}

/// One member of the served server, as the chat service lists them.
///
/// Carries the roles as well as the id because the orphan pass already has
/// to list the whole server: reading each member's roles again afterwards
/// would be one request per member for something the listing just said.
public struct ServerMember: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The member, as the chat service names them.
    public let externalId: String

    /// Every role they hold, including ones this bot knows nothing about.
    public let roleIds: Set<String>

    // MARK: - Initializers

    /// - Parameters:
    ///   - externalId: The member, as the chat service names them.
    ///   - roleIds: Every role they hold.
    public init(externalId: String, roleIds: Set<String>) {
        self.externalId = externalId
        self.roleIds = roleIds
    }
}

/// Listing the server, which is the only way to find somebody still holding
/// a role this bot granted and has no record of any more.
///
/// Separate from ``RoleGateway``, and optional to supply, because listing a
/// whole server is a different permission and a different cost from reading
/// one member. A host that does not supply one gets no orphan pass at all,
/// which leaves roles alone: the safe direction, and the same direction
/// every other refusal in this target takes.
public protocol ServerRoster: Sendable {

    /// Every member holding at least one of these roles.
    ///
    /// The filter is the roster's to apply because a chat service pages its
    /// member list, and paging the whole server into memory to throw most of
    /// it away is the sort of thing that works on a test server and falls
    /// over on a real one.
    ///
    /// - Parameter roleIds: The roles this bot manages.
    /// - Throws: When the server could not be listed. The orphan pass then
    ///   takes nothing from anybody.
    func members(holdingAnyOf roleIds: Set<String>) async throws -> [ServerMember]
}
