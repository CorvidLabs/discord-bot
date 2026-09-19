@preconcurrency import Foundation
import Chain
import Gating
import Store
import Testing

@testable import Surface

/// Values every suite here builds on.
///
/// Nothing in this file names a real server, a real asset, a real account or
/// a real host, and nothing in it reaches one. That is `BUILD-2.a`: the suite
/// cannot be pointed at anything live by whatever happens to be configured on
/// the machine running it.
enum Fixture {

    /// A token that is nobody's.
    static func token(
        logoURL: String? = nil,
        cardColor: UInt32? = 0x3366FF,
        links: [TokenLink] = []
    ) throws -> TokenProfile {
        try TokenProfile(
            assetId: 1,
            symbol: "TKN",
            displayName: "Test Token",
            decimals: 6,
            logoURL: logoURL,
            cardColor: cardColor,
            links: links
        )
    }

    /// Two rungs, each granting a role.
    static func gating(pools: LiquidityPoolCatalog = LiquidityPoolCatalog()) throws -> GatingConfiguration {
        let ladder = TierLadder(rungs: [
            Tier(id: "one", name: "One", minimumBaseUnits: 100),
            Tier(id: "two", name: "Two", minimumBaseUnits: 1_000)
        ])
        return GatingConfiguration(
            token: try token(),
            tiers: LoadedTiers(ladder: ladder, roleIds: ["one": "role-one", "two": "role-two"]),
            pools: pools,
            verifiedRoleId: "role-verified"
        )
    }

    /// The words on a card, with nothing inherited.
    static func chrome() throws -> CardChrome {
        CardChrome(botName: "Gatekeeper", token: try token())
    }

    /// Who runs this instance, as this instance's operator wrote it.
    static let disclosure = DisclosureSettings(
        operatorName: "The Example Server team",
        visibilityNote: "Your rung is visible; your account is not.",
        contact: "#support"
    )

    /// A slash command interaction from the served server.
    static func command(
        _ name: String,
        guildId: String = "guild-1",
        options: [String: OptionValue] = [:],
        userExternalId: String = "100000000000000001",
        roleIds: [String] = [],
        permissionBits: UInt64? = nil,
        receivedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> InteractionRequest {
        InteractionRequest(
            kind: .command,
            commandName: name,
            options: options,
            guildId: guildId,
            userExternalId: userExternalId,
            memberRoleIds: roleIds,
            permissionBits: permissionBits,
            interactionId: "i-1",
            token: "t-1",
            receivedAt: receivedAt
        )
    }

    /// The four-command catalogue, with everything switched on.
    static func catalog() throws -> CommandCatalog {
        try CommandCatalog.build(features: SurfaceFeatures(enabled: Set(SurfaceFeature.allCases)))
    }
}

/// A verification portal that answers from values, not from a network.
actor FakeVerificationClient: VerificationClient {

    var healthError: (any Error)?
    var probe: SharedSecretProbe = .agreed
    var existingAccount: PortalAccount?
    var session = VerificationSession(
        token: "session-token",
        url: "https://verify.example.test/s/abc",
        expiresAt: Date(timeIntervalSince1970: 2_000)
    )
    var createError: (any Error)?
    private(set) var deletedFor: [String] = []

    init() {}

    func setHealthError(_ error: (any Error)?) { healthError = error }
    func setProbe(_ value: SharedSecretProbe) { probe = value }
    func setCreateError(_ error: (any Error)?) { createError = error }

    func health() async throws {
        if let healthError { throw healthError }
    }

    func probeSharedSecret() async throws -> SharedSecretProbe { probe }

    func account(externalId: String, guildId: String) async throws -> PortalAccount? { existingAccount }

    func createSession(externalId: String, guildId: String) async throws -> VerificationSession {
        if let createError { throw createError }
        return session
    }

    func deleteSession(externalId: String, guildId: String) async throws {
        deletedFor.append(externalId)
    }
}

/// A role applier that remembers rather than calls.
actor RecordingRoleApplier: RoleApplier {

    private(set) var applied: [(decision: RoleDecision, externalId: String)] = []
    private var current: Set<String>
    private var readFails: Bool
    private var applyFails: Bool

    init(current: Set<String> = [], readFails: Bool = false, applyFails: Bool = false) {
        self.current = current
        self.readFails = readFails
        self.applyFails = applyFails
    }

    var applyCount: Int { applied.count }

    var lastDecision: RoleDecision? { applied.last?.decision }

    func currentRoleIds(externalId: String) async throws -> Set<String> {
        if readFails { throw FixtureError.refused }
        return current
    }

    func apply(_ decision: RoleDecision, externalId: String) async throws {
        if applyFails { throw FixtureError.refused }
        applied.append((decision, externalId))
    }
}

/// An account reader that answers from a table.
struct FixtureAccountReader: AccountHoldingsReader {

    var checks: [String: WalletCheck] = [:]
    var unreadable: Set<String> = []

    func check(address: String, for caller: RequestCaller) async throws -> WalletCheck {
        if unreadable.contains(address) { throw FixtureError.refused }
        guard let check = checks[address] else { throw FixtureError.refused }
        return check
    }
}

/// Something that went wrong, in a test.
enum FixtureError: Error, Equatable {
    case refused
}
