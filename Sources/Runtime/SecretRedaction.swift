import Foundation

/// The one place a value is turned into something safe to print.
///
/// The report is rendered from the catalogue rather than by each subsystem
/// printing what it feels like, and this is why that matters: the renderer has
/// no access to a value except through an entry, and an entry marked secret
/// has no path here that yields one (CATALOG-6.a, ADOPT-9.a).
///
/// It is also applied to refusals. A loader's refusal quotes the value it
/// could not use, and a node URL with a credential in its path is a value: a
/// refusal that pasted it into a container log would defeat the report's whole
/// rule one line further down.
public enum SecretRedaction: Sendable {

    // MARK: - Properties

    /// What stands in for a value that may not be printed.
    public static let placeholder = "<redacted>"

    // MARK: - Public Methods

    /// A URL as scheme, host and port, and nothing else.
    ///
    /// The path and the query go, because some node providers put the
    /// credential in the path and the report is meant to be safe to paste
    /// into an issue. The host survives, which is what says which network
    /// this is (ADOPT-12.b).
    ///
    /// - Parameter value: The URL as it was written.
    public static func host(of value: String) -> String {
        guard
            let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme,
            let host = url.host
        else { return placeholder }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Every occurrence of a value this build must not print, taken out of
    /// `text`.
    ///
    /// Applied to a refusal on its way to standard error. Secrets are
    /// replaced outright; URLs are cut back to scheme, host and port, so the
    /// sentence still says which node refused.
    ///
    /// - Parameters:
    ///   - text: What is about to be printed.
    ///   - settings: The one snapshot, so the values to take out are known.
    public static func applied(to text: String, settings: Settings) -> String {
        var out = text
        for name in settings.names {
            guard
                let entry = SettingsCatalogue.entry(for: name),
                let raw = settings.value(name)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            else { continue }
            switch entry.secrecy {
            case .plain:
                continue
            case .secret:
                out = out.replacingOccurrences(of: raw, with: placeholder)
            case .url:
                // Longest first would matter if a value contained another;
                // replacing the whole URL with its host form leaves nothing
                // of the path or query behind either way.
                out = out.replacingOccurrences(of: raw, with: host(of: raw))
            }
        }
        return out
    }
}
