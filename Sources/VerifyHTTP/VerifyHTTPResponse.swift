@preconcurrency import Foundation

/// One HTTP answer, as a value, so what a route decides can be asserted
/// without a socket.
///
/// **Every answer carries the same headers**, including the page, the script,
/// the stylesheet and every refusal. They are on the value rather than added
/// by whatever writes to the socket, because a header that protects a bearer
/// credential is not something to leave to a second place that might be
/// skipped: `Referrer-Policy: no-referrer` is the one obligation the host
/// carries that a browser, not this process, enforces, and a page that
/// forgets it hands the session id to every asset host the page ever reaches
/// (REQ-verify-009).
public struct VerifyHTTPResponse: Sendable, Equatable {

    // MARK: - Properties

    /// The headers every answer from this surface carries.
    ///
    /// - `Referrer-Policy: no-referrer` so the address of a page that was
    ///   opened with a session id in its fragment is never sent anywhere.
    /// - `Cache-Control: no-store` because the card names a member's chat
    ///   account, and a shared machine's browser cache is somebody else's
    ///   to read. It is on the script and the stylesheet too, which hold
    ///   nothing about anybody, and that costs two requests on every
    ///   reload. The alternative needs a way to make a browser let go of a
    ///   stale asset, and this surface has none: the paths are fixed and it
    ///   refuses a query string, so `app.js?v=2` is a `400` here. A cached
    ///   script paired with a new page, for as long as the cache lasts, is
    ///   worse than the two requests.
    /// - `Content-Security-Policy` with no third party origin in it, so the
    ///   page cannot be made to fetch a script that reads the fragment.
    /// - `X-Content-Type-Options`, `X-Frame-Options` and `frame-ancestors`
    ///   so the page cannot be framed by something that then reads what the
    ///   member types into it.
    public static let securityHeaders: [String: String] = [
        "Referrer-Policy": "no-referrer",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Content-Security-Policy": contentSecurityPolicy
    ]

    /// What the page is allowed to reach.
    ///
    /// Nothing but this origin, and no inline script at all, which is why
    /// the script and the stylesheet are routes of their own rather than
    /// text inside the page. An operator who adds a wallet connector has to
    /// widen `script-src` and `connect-src` to reach it, and widening it is
    /// a change somebody reads rather than a hole that was always open.
    public static let contentSecurityPolicy: String =
        "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; "
        + "img-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"

    /// What a content type is replaced by when it could not be written into
    /// a header block safely.
    ///
    /// A type rather than nothing at all, because a browser handed no
    /// content type sniffs one, and `nosniff` then leaves it with a body it
    /// will not render. This one renders nowhere, which is the right answer
    /// for a response whose own description of itself was unusable.
    public static let fallbackContentType: String = "application/octet-stream"

    /// The status code.
    public let status: Int

    /// What the body is.
    public let contentType: String

    /// The body.
    public let body: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - status: The status code.
    ///   - contentType: What the body is.
    ///   - body: The body.
    public init(status: Int, contentType: String, body: String) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    // MARK: - Public Methods

    /// An answer carrying one of this target's own static assets.
    ///
    /// - Parameters:
    ///   - body: The asset.
    ///   - contentType: What it is.
    public static func asset(_ body: String, contentType: String) -> VerifyHTTPResponse {
        VerifyHTTPResponse(status: 200, contentType: contentType, body: body)
    }

    /// An answer carrying JSON.
    ///
    /// - Parameters:
    ///   - status: The status code.
    ///   - body: The JSON.
    public static func json(status: Int, body: String) -> VerifyHTTPResponse {
        VerifyHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    /// The whole answer as bytes, headers and all.
    ///
    /// Built here rather than in the listener so that the headers a test
    /// asserts are the bytes a browser receives.
    public var wireBytes: [UInt8] {
        // The one header here whose value this type's caller chose. Inside
        // this target every one of them is a literal, but this is a library
        // product other programs serve the same flow with, and a newline in
        // a header value ends the header block early and lets whatever
        // follows be read as a header of its own. A value carrying one is
        // replaced rather than repaired, the way the health endpoint in
        // this package drops one.
        let declaredType = Self.isSafeHeaderValue(contentType) ? contentType : Self.fallbackContentType
        var lines = [
            "HTTP/1.1 \(status) \(Self.reason(for: status))",
            "Content-Type: \(declaredType)",
            "Content-Length: \(body.utf8.count)",
            "Connection: close"
        ]
        for name in Self.securityHeaders.keys.sorted() {
            guard let value = Self.securityHeaders[name] else { continue }
            lines.append("\(name): \(value)")
        }
        return Array((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    /// Whether a value can be written into a header block as it stands.
    ///
    /// - Parameter value: The value.
    public static func isSafeHeaderValue(_ value: String) -> Bool {
        let hasNoBreak = value.utf8.allSatisfy { $0 != 0x0d && $0 != 0x0a }
        return hasNoBreak && !value.isEmpty
    }

    /// The word beside a status code.
    ///
    /// - Parameter status: The status code.
    public static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 413: return "Content Too Large"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}
