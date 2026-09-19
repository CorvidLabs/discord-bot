@preconcurrency import Foundation
import Surface

#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

/// The other half of verification, over HTTP.
///
/// Exactly the contract in `docs/VERIFICATION.md`, and the two places it is
/// unforgiving are unforgiving here too.
///
/// **`201` on create is compared exactly.** A portal that answers `200` with
/// a perfect body has created the session and issued the challenge, and the
/// member is told verification failed. Nothing in the response tells the two
/// apart, which is why a new portal appears to work when tested with `curl`
/// and does not work from Discord.
///
/// **`404` on the lookup is not an error.** A member with no account is the
/// ordinary case, and treating it as a failure turns every first verification
/// into an error message.
///
/// It lives in the adapter rather than in `Surface` on purpose. `BUILD-2.a`
/// asks that nothing in the test suite can reach a real host whatever is
/// configured on the machine running it, and `SurfaceTests` does not depend
/// on this target, so it has no way to construct one of these.
public struct HTTPVerificationClient: VerificationClient {

    // MARK: - Properties

    /// The base URL, with no trailing slash and no path.
    public let baseURL: String

    /// The one secret both halves hold.
    private let sharedSecret: String

    /// How long any one call may take.
    private let timeout: TimeInterval

    /// What performs the request. A parameter so this type is testable at
    /// all; the default is the one the process uses.
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    // MARK: - Initializers

    /// - Parameters:
    ///   - baseURL: The base URL, with no trailing slash.
    ///   - sharedSecret: The one secret both halves hold.
    ///   - timeout: How long any one call may take.
    ///   - perform: What performs the request.
    public init(
        baseURL: String,
        sharedSecret: String,
        timeout: TimeInterval = 5,
        perform: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.sharedSecret = sharedSecret
        self.timeout = timeout
        self.perform = perform ?? { request in try await URLSession.shared.data(for: request) }
    }

    // MARK: - Public Methods

    public func health() async throws {
        // No key on this one, by contract. It is also what a deploy gate
        // polls, so it must not be behind authentication.
        let (_, status) = try await send(path: "/health", method: "GET", keyed: false, body: nil)
        guard status == 200 else {
            throw VerificationError.unreachable("health answered \(status)")
        }
    }

    public func probeSharedSecret() async throws -> SharedSecretProbe {
        // A keyed, side-effect-free call. The contract does not require a
        // portal to offer one, so anything other than 200 or 401 is read as
        // "nothing to probe" rather than as agreement: an operator whose
        // portal cannot answer this should be told the check is not running,
        // not told it passed.
        let (_, status) = try await send(
            path: "/api/v1/verification/health",
            method: "GET",
            keyed: true,
            body: nil
        )
        switch status {
        case 200:
            return .agreed
        case 401, 403:
            return .disagreed
        default:
            return .notOffered
        }
    }

    public func account(externalId: String, guildId: String) async throws -> PortalAccount? {
        let (data, status) = try await send(
            path: "/api/v1/verification/\(externalId)?guildId=\(guildId)",
            method: "GET",
            keyed: true,
            body: nil
        )
        switch status {
        case 404:
            return nil
        case 401:
            throw VerificationError.secretRejected
        case 200:
            break
        default:
            throw VerificationError.unexpectedStatus(expected: 200, received: status)
        }
        do {
            let decoded = try JSONDecoder().decode(AccountBody.self, from: data)
            return PortalAccount(address: decoded.walletAddress, balanceBaseUnits: decoded.balance)
        } catch {
            throw VerificationError.malformedResponse(String(describing: error))
        }
    }

    public func createSession(externalId: String, guildId: String) async throws -> VerificationSession {
        let body = try JSONEncoder().encode(CreateBody(discordId: externalId, guildId: guildId))
        let (data, status) = try await send(
            path: "/api/v1/verification",
            method: "POST",
            keyed: true,
            body: body
        )
        if status == 401 { throw VerificationError.secretRejected }
        // Exactly 201. See this type's documentation.
        guard status == 201 else {
            throw VerificationError.unexpectedStatus(expected: 201, received: status)
        }
        do {
            let decoded = try JSONDecoder().decode(SessionBody.self, from: data)
            return VerificationSession(
                token: decoded.token,
                url: decoded.url,
                expiresAt: Self.parseTimestamp(decoded.expiresAt) ?? Date()
            )
        } catch {
            throw VerificationError.malformedResponse(String(describing: error))
        }
    }

    public func deleteSession(externalId: String, guildId: String) async throws {
        let (_, status) = try await send(
            path: "/api/v1/verification/\(externalId)?guildId=\(guildId)",
            method: "DELETE",
            keyed: true,
            body: nil
        )
        if status == 401 { throw VerificationError.secretRejected }
        // 404 included. A portal that has nothing to delete has already done
        // what was asked, and it says so with 200.
        guard status == 200 else {
            throw VerificationError.unexpectedStatus(expected: 200, received: status)
        }
    }

    // MARK: - Private Methods

    /// ISO 8601 with a `Z`, which is what the contract says `expiresAt` is.
    ///
    /// Built per call rather than shared. A formatter is not `Sendable` and
    /// carries mutable state, and this is parsed once per `/verify`: the cost
    /// of building one is not worth a shared object two tasks can reach.
    private static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// One call, and the status it came back with.
    private func send(
        path: String,
        method: String,
        keyed: Bool,
        body: Data?
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else {
            throw VerificationError.unreachable("\(baseURL)\(path) is not a URL")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        if keyed {
            request.setValue(sharedSecret, forHTTPHeaderField: "X-API-Key")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        do {
            let (data, response) = try await perform(request)
            guard let http = response as? HTTPURLResponse else {
                throw VerificationError.malformedResponse("not an HTTP response")
            }
            return (data, http.statusCode)
        } catch let error as VerificationError {
            throw error
        } catch {
            throw VerificationError.unreachable(String(describing: error))
        }
    }

    /// The body sent to create a session. Snowflakes as strings, never as
    /// JSON numbers: one does not fit in a double and a portal that parses it
    /// as a number corrupts it on the way back out.
    private struct CreateBody: Encodable {
        let discordId: String
        let guildId: String
    }

    /// The body a created session comes back as. All three fields are
    /// required by the decode even though two are never read.
    private struct SessionBody: Decodable {
        let token: String
        let url: String
        let expiresAt: String
    }

    /// The body a lookup comes back as. Five fields required, two read.
    private struct AccountBody: Decodable {
        let discordId: String
        let walletAddress: String
        let balance: UInt64
        let tier: String
        let isPublic: Bool
    }
}
