@preconcurrency import Foundation
import Store

/// One member the sweep is going to visit, with the accounts they proved.
///
/// The accounts travel with the member rather than being fetched per member
/// inside the loop, because the sweep reads every account of every member in
/// **one** batched chain call: a pool's reserves are then read once for the
/// whole run instead of once per member, which is the difference between a
/// handful of requests and one per person in the server.
public struct SweptMember: Sendable, Equatable {

    // MARK: - Properties

    /// Who they are to this instance, and to the chat service.
    public let member: MemberRecord

    /// Every account they proved, oldest first.
    ///
    /// Empty is a real answer and is not a failure: it is a member on record
    /// who has proved nothing, and the sweep holds their roles rather than
    /// deciding anything from a wallet list of length zero.
    public let accounts: [AccountRecord]

    // MARK: - Initializers

    /// - Parameters:
    ///   - member: Who they are.
    ///   - accounts: Every account they proved.
    public init(member: MemberRecord, accounts: [AccountRecord]) {
        self.member = member
        self.accounts = accounts
    }

    // MARK: - Public Methods

    /// The addresses to read, in the order they were proved.
    public var addresses: [String] {
        accounts.map(\.address)
    }
}

/// Everybody this instance has on record, as one list.
///
/// A seam rather than a store method because no store protocol in this
/// package enumerates members: ``Store/MemberDirectory`` answers about one
/// member and counts the rest. Enumerating is the sweep's own need, so the
/// sweep declares it, and a host satisfies it from whatever its store can
/// do.
public protocol SweepDirectory: Sendable {

    /// Every member on record, with the accounts they proved.
    ///
    /// - Throws: When the list could not be read. A sweep that cannot find
    ///   out who it serves does nothing at all rather than acting on the
    ///   part of the list it got.
    func verifiedMembers() async throws -> [SweptMember]
}

/// A fixed list, for a test or a host with nothing durable yet.
public struct StaticSweepDirectory: SweepDirectory {

    // MARK: - Properties

    /// The list handed back every time.
    public let members: [SweptMember]

    // MARK: - Initializers

    /// - Parameter members: The list to hand back.
    public init(members: [SweptMember]) {
        self.members = members
    }

    // MARK: - Public Methods

    public func verifiedMembers() async throws -> [SweptMember] {
        members
    }
}
