@preconcurrency import Foundation

/// Where the report and the refusals go.
///
/// A seam, because the whole of the report is something a test has to be able
/// to read, and because the question of where a report should go when the
/// process is not a terminal is not settled: standard output is the
/// assumption, and a container that captures only standard error would lose
/// it, which would break BUILD-3.b in the environment that matters most.
/// Keeping it behind this protocol is what makes changing that a one line
/// change rather than a sweep.
public protocol RuntimeOutput: Sendable {

    /// Writes lines an operator is meant to read.
    func write(_ lines: [String]) async

    /// Writes lines about something being wrong.
    func writeError(_ lines: [String]) async
}

extension RuntimeOutput {

    /// Writes one line.
    ///
    /// - Parameter line: The line.
    public func write(_ line: String) async {
        await write([line])
    }

    /// Writes one line about something being wrong.
    ///
    /// - Parameter line: The line.
    public func writeError(_ line: String) async {
        await writeError([line])
    }
}

/// The process's own output and error.
///
/// The report goes to standard output and refusals to standard error, so a
/// supervisor capturing only one still sees the refusal.
public struct StandardStreams: RuntimeOutput {

    // MARK: - Initializers

    /// The process's own streams.
    public init() {}

    // MARK: - Public Methods

    public func write(_ lines: [String]) async {
        Self.put(lines, to: FileHandle.standardOutput)
    }

    public func writeError(_ lines: [String]) async {
        Self.put(lines, to: FileHandle.standardError)
    }

    // MARK: - Private Methods

    private static func put(_ lines: [String], to handle: FileHandle) {
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}

/// Output kept in memory, so a test can read what a start printed.
///
/// A real implementation rather than a stub: `check` renders through the same
/// path a boot does, which is the only way the two can be guaranteed to print
/// the same report (RT-026).
public actor RecordingOutput: RuntimeOutput {

    // MARK: - Properties

    /// Every line written to output, in order.
    public private(set) var out: [String] = []

    /// Every line written to error, in order.
    public private(set) var errors: [String] = []

    // MARK: - Initializers

    /// Nothing written yet.
    public init() {}

    // MARK: - Public Methods

    public func write(_ lines: [String]) async {
        out.append(contentsOf: lines)
    }

    public func writeError(_ lines: [String]) async {
        errors.append(contentsOf: lines)
    }

    /// Everything written to output, as one string.
    public var outText: String {
        out.joined(separator: "\n")
    }

    /// Everything written to error, as one string.
    public var errorText: String {
        errors.joined(separator: "\n")
    }

    /// Everything written to either, as one string.
    public var allText: String {
        (out + errors).joined(separator: "\n")
    }
}
