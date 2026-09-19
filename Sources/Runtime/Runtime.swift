import Chain
import Foundation
import Gating

/// What running a verb came to.
public enum RuntimeResult: Sendable {

    /// Nothing is left running, and this is what the process exits with.
    case finished(ExitCode)

    /// The instance is up and the caller waits on it.
    case running(RunningInstance)

    // MARK: - Public Methods

    /// The exit code, or nil while something is still running.
    public var exitCode: ExitCode? {
        switch self {
        case .finished(let code): return code
        case .running: return nil
        }
    }
}

/// The composition root.
///
/// Everything that decides what happens and in what order is here, and
/// everything that touches the machine is in the executable. This type is
/// handed its seams and can therefore be driven entirely from a test; nothing
/// in this module reads the process environment, opens a file it was not
/// given a path to, or knows a chat library exists (RT-003, RT-002).
public struct Runtime: Sendable {

    // MARK: - Properties

    private let seams: RuntimeSeams

    // MARK: - Initializers

    /// - Parameter seams: Everything live, handed in.
    public init(seams: RuntimeSeams) {
        self.seams = seams
    }

    // MARK: - Public Methods

    /// Runs one verb.
    ///
    /// - Parameters:
    ///   - command: What to do.
    ///   - settings: The one snapshot of the machine's variables.
    public func execute(_ command: RuntimeCommand, settings: Settings) async -> RuntimeResult {
        switch command {
        case .help:
            await seams.output.write(RuntimeCommand.usage)
            return .finished(.ok)
        case .check:
            return .finished(await check(settings: settings))
        case .rehearse:
            return .finished(await rehearse(settings: settings))
        case .run:
            switch await BootSequence(seams: seams).run(settings: settings) {
            case .running(let instance):
                return .running(instance)
            case .refused(let failure, _, _):
                return .finished(failure.code)
            }
        }
    }

    /// Runs whatever `arguments` asks for, refusing an argument nobody
    /// recognises.
    ///
    /// - Parameters:
    ///   - arguments: The process arguments **without** the program name.
    ///   - settings: The one snapshot of the machine's variables.
    public func execute(arguments: [String], settings: Settings) async -> RuntimeResult {
        switch RuntimeCommand.parse(arguments) {
        case .success(let command):
            return await execute(command, settings: settings)
        case .failure(let failure):
            await seams.output.writeError(failure.lines)
            await seams.output.write(RuntimeCommand.usage)
            return .finished(failure.code)
        }
    }

    // MARK: - Private Methods

    /// Loads the settings, prints the report a start would, and touches
    /// nothing: no socket, no store file, no network (RT-026, RUN-9).
    ///
    /// It reports the **first** refusal rather than every one, because the
    /// loaders throw on the first bad value and changing that would be a
    /// change to four merged contracts. The catalogue listing is what stops
    /// that being unhelpful: the refusal says what is wrong, and the listing
    /// says what is still missing.
    private func check(settings: Settings) async -> ExitCode {
        var report = StartupReport()
        report.append(StartupReportWriter.opening(capability: seams.spending))
        report.append(
            ReportSection(
                title: "Dry run",
                lines: [
                    "Nothing below was opened, bound or asked. This is what a start would make "
                        + "of your settings, and it costs you no socket, no store and no request.",
                    "It cannot tell you whether the volume under \(RuntimeEnvironment.storePath) "
                        + "can promise a write, and it cannot tell you whether the node answers. "
                        + "A start does both, and the second costs one request."
                ]
            )
        )
        report.append(StartupReportWriter.catalogue(settings: settings))

        let loaded: LoadedConfiguration
        do {
            loaded = try LoadedConfiguration.load(settings)
        } catch {
            let failure = BootFailure.configuration(error)
            await write(report)
            await writeError(failure, settings: settings)
            return failure.code
        }
        report.append(StartupReportWriter.understanding(configuration: loaded))
        report.append(
            StartupReportWriter.parts(
                configuration: loaded,
                capability: seams.spending,
                chainOutcome: nil
            )
        )
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        report.appendIfAny(StartupReportWriter.audit(audit))
        report.appendIfAny(storeCheck(loaded.runtime))

        await write(report)
        if let refusal = audit.refusal {
            await writeError(refusal, settings: settings)
            return refusal.code
        }
        return .ok
    }

    /// Loads the operator's own configuration and runs the role rules over
    /// members it invents (RT-027).
    private func rehearse(settings: Settings) async -> ExitCode {
        var report = StartupReport()
        report.append(StartupReportWriter.opening(capability: seams.spending))
        let loaded: LoadedConfiguration
        do {
            loaded = try LoadedConfiguration.load(settings)
        } catch {
            let failure = BootFailure.configuration(error)
            await write(report)
            await writeError(failure, settings: settings)
            return failure.code
        }
        report.append(StartupReportWriter.understanding(configuration: loaded))
        for section in Rehearsal.report(configuration: loaded.gating) {
            report.append(section)
        }
        await write(report)
        return .ok
    }

    /// What a dry run can say about the store without opening it.
    ///
    /// Only that the path is absolute and that its parent exists and can be
    /// written. Whether the volume can promise a flush is
    /// `StoreSQLite.DurableVolume`'s question and that type is internal to
    /// its module, so a store on a network filesystem is refused at a start
    /// and not here. That is the one place this dry run is weaker than the
    /// real thing, and saying so is better than implying it checked.
    private func storeCheck(_ runtime: RuntimeSettings) -> ReportSection {
        let parent = (runtime.storePath as NSString).deletingLastPathComponent
        var lines = ["Path: \(runtime.storePath)"]
        if FileManager.default.fileExists(atPath: runtime.storePath) {
            lines.append("A store is already there. A start would open it and migrate it.")
        } else if FileManager.default.isWritableFile(atPath: parent) {
            lines.append(
                "Nothing is there yet. A start would CREATE one, which is what a volume that "
                    + "did not mount also looks like."
            )
        } else {
            lines.append(
                "Nothing is there and \(parent) cannot be written, so a start would refuse."
            )
        }
        lines.append(
            "Not checked here: whether this volume can promise a write. A start checks that, "
                + "and refuses a network filesystem."
        )
        return ReportSection(title: "Store, without opening it", lines: lines)
    }

    /// The report as it was rendered.
    ///
    /// Not filtered, because it cannot need filtering: it is rendered from
    /// the catalogue, and an entry marked secret has no path that yields its
    /// value. Filtering it as well would mangle an ordinary sentence whenever
    /// a secret happened to be a short common word, which teaches the next
    /// reader that the output is unreliable.
    private func write(_ report: StartupReport) async {
        await seams.output.write(report.lines)
    }

    private func writeError(_ failure: BootFailure, settings: Settings) async {
        await seams.output.writeError(
            failure.lines.map { SecretRedaction.applied(to: $0, settings: settings) }
        )
    }
}
