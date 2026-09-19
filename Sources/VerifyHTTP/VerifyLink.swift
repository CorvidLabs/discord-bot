@preconcurrency import Foundation
import Verify

/// Why a link could not be built.
public enum VerifyLinkError: Error, Sendable, Equatable, CustomStringConvertible {

    /// The base was empty.
    case baseMissing(field: String)

    /// The base already carried a query string or a fragment, so a session
    /// id appended to it would not arrive.
    case baseCarriesQueryOrFragment(field: String)

    /// The base was not an `https` origin.
    case baseNotSecure(field: String)

    // MARK: - Public Methods

    public var description: String {
        switch self {
        case .baseMissing(let field):
            return "\(field) is required and was empty"
        case .baseCarriesQueryOrFragment(let field):
            return "\(field) may not carry a query string or a fragment"
        case .baseNotSecure(let field):
            return "\(field) must be an https origin"
        }
    }
}

/// The one link a member is given, and the one place the session id is
/// allowed to be.
///
/// **After the `#`, always.** A fragment is the one part of an address a
/// browser never sends to a server: it is not in the request line, so it is
/// not in the server's access log, not in a proxy's, and not in a referrer
/// header sent to anything the page reaches. A query string is the opposite
/// of all four. The id is a bearer credential, so the difference between the
/// two characters is the difference between a credential that lives in the
/// member's tab and a credential written into every log on the path
/// (REQ-verify-003, REQ-verify-009).
public enum VerifyLink: Sendable {

    // MARK: - Public Methods

    /// The link a member opens.
    ///
    /// - Parameters:
    ///   - base: The origin this surface is served from, as the operator
    ///     configured it, with no trailing path.
    ///   - sessionId: The session the link is for.
    ///   - field: The name of the variable the base came from, so a refusal
    ///     names what to fix.
    /// - Returns: The link, with the id in the fragment.
    /// - Throws: ``VerifyLinkError`` for a base that could not carry a
    ///   fragment.
    public static func link(
        base: String,
        sessionId: VerificationSessionIdentifier,
        field: String = "verify base URL"
    ) throws -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VerifyLinkError.baseMissing(field: field) }
        guard !trimmed.contains("?"), !trimmed.contains("#") else {
            throw VerifyLinkError.baseCarriesQueryOrFragment(field: field)
        }
        // Refused rather than upgraded. A wallet connector will not run on a
        // page served over plain HTTP, and a member's session id crossing a
        // network in the clear is the one thing this whole file is about.
        //
        // Loopback is the one exception, and it is exactly loopback: nothing
        // addressed to this machine leaves it, and a rule that makes the
        // flow impossible to run locally is a rule somebody turns off
        // wholesale rather than works around.
        guard Self.isSecure(trimmed) || Self.isLoopback(trimmed) else {
            throw VerifyLinkError.baseNotSecure(field: field)
        }
        let origin = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return origin + VerifyRouting.pagePath + "#" + sessionId.value
    }

    // MARK: - Private Methods

    /// Whether a base is an `https` origin.
    private static func isSecure(_ base: String) -> Bool {
        base.lowercased().hasPrefix("https://")
    }

    /// Whether a base is plain HTTP to this machine and nowhere else.
    ///
    /// The host is compared whole against the two names loopback goes by,
    /// with only a port or a path allowed after it. A prefix test would
    /// accept `http://localhost.example.test`, which is somebody else's
    /// machine with a reassuring name.
    private static func isLoopback(_ base: String) -> Bool {
        let lowered = base.lowercased()
        guard lowered.hasPrefix("http://") else { return false }
        let rest = lowered.dropFirst("http://".count)
        let host = rest.prefix { $0 != ":" && $0 != "/" }
        return host == "localhost" || host == "127.0.0.1"
    }
}
