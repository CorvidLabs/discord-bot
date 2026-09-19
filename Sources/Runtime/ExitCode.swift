import Foundation

/// How the process ends, and why.
///
/// Distinct codes rather than one, because the thing reading them is a
/// supervisor or a deploy script and a single number tells it nothing it can
/// act on: a wrong token, a full disk and a duplicate instance all deserve
/// different responses, and only ``unavailable`` belongs in a do-not-restart
/// list (RUN-3, SEE-11).
///
/// The values are the conventional `sysexits` ones so that nobody has to learn
/// a private table.
public enum ExitCode: Int32, Sendable, Equatable, CaseIterable {

    /// Stopped cleanly, on a signal.
    case ok = 0

    /// An argument nobody recognises.
    case usage = 64

    /// Something is already here, or cannot be used: the store is held by
    /// another process, the address is in use, the volume cannot promise a
    /// write.
    case unavailable = 69

    /// This program is wrong, rather than its configuration. A key read that
    /// the catalogue does not describe is the case that exists today.
    case internalError = 70

    /// The configuration is wrong: a missing variable, a bad value, an asset
    /// the node has never heard of.
    case configuration = 78

    // MARK: - Public Methods

    /// One word for the code, for a report line an operator reads.
    public var label: String {
        switch self {
        case .ok: return "ok"
        case .usage: return "usage"
        case .unavailable: return "unavailable"
        case .internalError: return "internal"
        case .configuration: return "configuration"
        }
    }
}
