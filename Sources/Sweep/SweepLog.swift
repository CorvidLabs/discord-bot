@preconcurrency import Foundation

/// Where a sweep's lines go.
///
/// A seam of one method, so this target pulls in no logging package and a
/// test can read back exactly what an operator would have seen. Every line
/// written through ``RoleSweep`` is prefixed with that sweep's run id, which
/// is the whole of SEE-6: one sweep is followed from start to finish without
/// guessing which lines belong to it, even when a scheduled run and a
/// hand-started one overlap in the same stream.
///
/// The method is `async` so an implementation that has to serialise its
/// lines can be an actor. The alternative is a lock inside every log in
/// every host, and a log whose lines arrive out of order is a log that
/// cannot be used to reconstruct what happened.
public protocol SweepLog: Sendable {

    /// Writes one line.
    ///
    /// - Parameter line: The line, already carrying its run id.
    func write(_ line: String) async
}

/// A log that keeps nothing. The default, so a host opts in to output.
public struct SilentSweepLog: SweepLog {

    // MARK: - Initializers

    /// A log that discards every line.
    public init() {}

    // MARK: - Public Methods

    public func write(_ line: String) async {}
}

/// A log that writes to standard error.
///
/// Standard error rather than standard output, because standard output is
/// where a report a person asked for goes and mixing a background sweep into
/// it makes both harder to read.
public struct StandardErrorSweepLog: SweepLog {

    // MARK: - Initializers

    /// A log that writes each line to standard error.
    public init() {}

    // MARK: - Public Methods

    public func write(_ line: String) async {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}

/// One sweep's log, with its run id already on the front.
///
/// Internal, and taken by every function that writes a line, so the prefix
/// cannot be forgotten at one call site: the compiler has nothing else to
/// hand it.
internal struct RunLog: Sendable {

    // MARK: - Properties

    /// Where the lines go.
    internal let log: any SweepLog

    /// The sweep these lines belong to.
    internal let runId: String

    // MARK: - Internal Methods

    /// Writes one line, tagged with the run id.
    internal func write(_ text: String) async {
        await log.write("[\(runId)] \(text)")
    }
}
