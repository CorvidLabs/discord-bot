import Foundation

/// One header copied from a provider's own answer.
public struct ProofField: Sendable, Equatable {

    // MARK: - Properties

    /// The header's name, as configured.
    public let name: String

    /// What the provider sent.
    public let value: String

    // MARK: - Initializers

    /// One header and what the provider put in it.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Proof of which provider actually served a request.
///
/// Some providers stamp their answers with headers saying which tier, token or
/// region served the call. Copying those onto a health answer is how an
/// operator checks from outside that the paid path is really the one in use,
/// without the health answer having to dump anything about the node itself.
///
/// **Which headers those are is configuration.** The version this was ported
/// from named one company's five headers in the source, which is useless to
/// anybody using a different provider and faintly rude to the ones it does not
/// name.
///
/// Nothing here ever invents a value. A probe that failed contributes no
/// fields, because a health answer that fabricates proof is worse than one
/// that admits it has none.
public struct ProviderProof: Sendable, Equatable {

    // MARK: - Properties

    /// The headers that were present, in the order they were configured.
    public let fields: [ProofField]

    // MARK: - Initializers

    /// Proof built from fields that were really present.
    public init(fields: [ProofField]) {
        self.fields = fields
    }

    // MARK: - Public Methods

    /// Picks the configured headers out of a response's headers.
    ///
    /// Lookup is case insensitive, because header names are, and a blank value
    /// counts as absent.
    /// - Returns: The proof, or nil when none of the configured headers were
    ///   present, which is the ordinary case for a provider that does not
    ///   stamp its answers.
    public static func parse(headers: [String: String], names: [String]) -> ProviderProof? {
        var fields: [ProofField] = []
        for name in names {
            let target = name.lowercased()
            let match = headers.first { $0.key.lowercased() == target }
            guard let value = match?.value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            fields.append(ProofField(name: name, value: value))
        }
        return fields.isEmpty ? nil : ProviderProof(fields: fields)
    }

    /// The same, from the loosely typed header dictionary a URL response has.
    public static func parse(responseHeaders: [AnyHashable: Any], names: [String]) -> ProviderProof? {
        var flattened: [String: String] = [:]
        for (key, value) in responseHeaders {
            guard let name = string(from: key), let text = string(from: value) else { continue }
            flattened[name] = text
        }
        return parse(headers: flattened, names: names)
    }

    /// The fields as headers to copy onto a health answer.
    public var httpHeaders: [String: String] {
        var headers: [String: String] = [:]
        for field in fields {
            headers[field.name] = field.value
        }
        return headers
    }

    // MARK: - Private Methods

    private static func string(from value: Any) -> String? {
        if let string = value as? String { return string }
        if let nsString = value as? NSString { return nsString as String }
        if let hashable = value as? AnyHashable { return hashable.base as? String }
        return nil
    }
}

/// Whether the instance is doing its job.
public enum ChainHealthStatus: String, Sendable, Equatable {

    /// Everything the instance has to reach, it has reached.
    case ok

    /// It is up, and something it needs is not there yet.
    case starting
}

/// One thing the instance has to have reached before it is working.
public struct ChainHealthComponent: Sendable, Equatable {

    // MARK: - Properties

    /// What it is called in the health answer.
    public let name: String

    /// Whether this instance has actually reached it.
    public let reached: Bool

    // MARK: - Initializers

    /// One thing the instance has to reach, and whether it has.
    public init(name: String, reached: Bool) {
        self.name = name
        self.reached = reached
    }
}

/// What a health check answers.
///
/// **A health answer is not "the process is alive".** The incident this exists
/// for ran for three hours: the process was up, the port answered, the check
/// said ok, every one of those was true and none of them was useful, and the
/// first anybody knew was somebody asking whether the bot was down. A check
/// that comes back fine must never mean only that something is listening.
///
/// So the answer states what this instance has actually reached. A listener
/// that is bound while the connection it exists to serve has not been made
/// reports `starting`, and names what it is waiting for. That also stops a
/// deployment gate treating a bound socket as a working bot and replacing a
/// version that worked with one that does not.
public struct ChainHealthReport: Sendable, Equatable {

    // MARK: - Properties

    /// The things this instance has to reach, and whether it has.
    public let components: [ChainHealthComponent]

    /// Proof of which provider served the last probe, when there is any.
    public let proof: ProviderProof?

    // MARK: - Initializers

    /// - Parameters:
    ///   - components: What the instance must have reached. An empty list is
    ///     `ok`, so a host that has nothing to wait for does not have to
    ///     invent something.
    ///   - proof: Whatever the last successful probe showed, or nil.
    public init(components: [ChainHealthComponent], proof: ProviderProof? = nil) {
        self.components = components
        self.proof = proof
    }

    // MARK: - Public Methods

    /// `ok` only when every component has been reached.
    public var status: ChainHealthStatus {
        components.allSatisfy(\.reached) ? .ok : .starting
    }

    /// What is not there yet, in the order it was declared.
    public var waitingOn: [String] {
        components.filter { !$0.reached }.map(\.name)
    }

    /// The answer as JSON.
    ///
    /// Hand built rather than encoded, because the shape of this string is
    /// what a monitoring check greps for and an encoder is free to reorder a
    /// dictionary between releases.
    public var jsonBody: String {
        var parts = ["\"status\":\"\(status.rawValue)\""]
        if !waitingOn.isEmpty {
            let names = waitingOn.map { "\"\(Self.escaped($0))\"" }.joined(separator: ",")
            parts.append("\"waiting\":[\(names)]")
        }
        if let proof, !proof.fields.isEmpty {
            let fields = proof.fields
                .map { "\"\(Self.escaped($0.name))\":\"\(Self.escaped($0.value))\"" }
                .joined(separator: ",")
            parts.append("\"provider\":{\(fields)}")
        }
        return "{\(parts.joined(separator: ","))}"
    }

    // MARK: - Private Methods

    /// Escapes a string for JSON by hand.
    ///
    /// A provider's header is somebody else's text arriving over the network.
    /// Interpolating it into a hand built body without escaping it is how a
    /// health answer stops being parseable, or stops being only a health
    /// answer.
    private static func escaped(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                escaped += "\\\""
            case "\\":
                escaped += "\\\\"
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}
