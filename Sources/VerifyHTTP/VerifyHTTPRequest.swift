@preconcurrency import Foundation

/// One HTTP request, parsed, with no socket anywhere near it.
///
/// Parsing lives in a value rather than inside the accept loop because every
/// rule this surface enforces is then a unit test rather than something only
/// a live browser can exercise (BUILD-2).
///
/// **This is deliberately a second parser, beside the one the callback
/// listener already owns.** Sharing it would mean this target depending on
/// the surface target, and through it on a store, a chain reader and a role
/// engine, which is exactly the reach the verification module gave up in
/// order to be able to say it reads nothing. The two also answer different
/// questions: a portal callback is one small JSON body from a cooperating
/// service, and this serves a browser, which is why the read here honours
/// `Content-Length` rather than taking whatever one `recv` produced.
public struct VerifyHTTPRequest: Sendable, Equatable {

    // MARK: - Properties

    /// The header the read loop's framing is decided by.
    public static let contentLengthHeader: String = "content-length"

    /// The most bytes one request may be, headers and body together.
    ///
    /// A signed proof is a few hundred bytes of base64 and the largest body
    /// this surface accepts is smaller still. The ceiling is here so that a
    /// peer cannot make this process hold memory by declaring a body it
    /// never sends.
    public static let maximumRequestBytes: Int = 16_384

    /// `GET`, `POST`, and so on, exactly as it arrived.
    public let method: String

    /// The request target, query string included, exactly as it arrived.
    ///
    /// Nothing in this target ever reads a value out of a query string, and
    /// ``carriesQuery`` is the only question asked about one.
    public let target: String

    /// Header names lowercased, values trimmed.
    public let headers: [String: String]

    /// Everything after the first empty line.
    public let body: String

    /// The path, with any query string taken off.
    public var path: String {
        target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
    }

    /// Whether the target carries a query string at all.
    ///
    /// Asked, and never read. A session id is a bearer credential and a query
    /// string is the one part of a request that lands in every access log,
    /// every proxy log and the browser's own history, so this surface refuses
    /// a request carrying one rather than serving it and hoping the id was
    /// somewhere else.
    public var carriesQuery: Bool {
        target.contains("?")
    }

    /// What the sender says the body is, in bytes, or nil when it said
    /// nothing.
    public var declaredBodyByteCount: Int? {
        guard let value = headers["content-length"] else { return nil }
        return Int(value)
    }

    /// Whether the whole body the sender declared has arrived.
    ///
    /// A browser is free to put the headers in one segment and the body in
    /// the next, so a listener that reads once and answers is a listener that
    /// intermittently loses a submission. The read loop asks this after every
    /// read.
    public var isComplete: Bool {
        body.utf8.count >= (declaredBodyByteCount ?? 0)
    }

    // MARK: - Initializers

    /// - Parameters:
    ///   - method: The method.
    ///   - target: The request target, query string included.
    ///   - headers: Header names lowercased, values trimmed.
    ///   - body: Everything after the first empty line.
    public init(method: String, target: String, headers: [String: String], body: String) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }

    // MARK: - Public Methods

    /// One request out of what has arrived so far, or nil.
    ///
    /// It answers nil until the header block has been terminated, so a caller
    /// reading from a socket can use it as the test for "is there a request
    /// here yet" rather than keeping a second copy of the same rule.
    ///
    /// It also answers nil for a message whose framing cannot be trusted: a
    /// `Content-Length` that is not a count, or two of them that disagree.
    /// RFC 9112 6.3 says to reject that message, and here it is the field
    /// the read loop's own "has the body arrived" question is decided by, so
    /// taking the last one would let the sender pick which bytes this
    /// surface reads as the body.
    ///
    /// - Parameter raw: What has been read, decoded as UTF-8.
    /// - Returns: The request, or nil when no complete header block has
    ///   arrived, or when what has arrived has no usable framing.
    public static func parse(_ raw: String) -> VerifyHTTPRequest? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        var bodyStart: Int?
        for (index, line) in lines.enumerated().dropFirst() {
            if line.isEmpty {
                bodyStart = index + 1
                break
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<separator].lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if name == contentLengthHeader {
                guard isByteCount(value) else { return nil }
                if let already = headers[name], already != value { return nil }
            }
            headers[name] = value
        }
        // No empty line means the headers are still arriving. Answering with
        // a request here is how a body gets read as a header and a header as
        // a request line.
        guard let bodyStart else { return nil }

        let body = bodyStart < lines.count
            ? lines[bodyStart...].joined(separator: "\r\n")
            : ""
        return VerifyHTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            headers: headers,
            body: body
        )
    }

    // MARK: - Private Methods

    /// Whether a value is a count of bytes and nothing else.
    ///
    /// Digits only: `Int` would take a sign and surrounding space, and a
    /// negative or padded length is a sender describing its message in a
    /// way this one will not guess at.
    ///
    /// - Parameter value: The header value.
    private static func isByteCount(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 19 else { return false }
        return value.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }
}
