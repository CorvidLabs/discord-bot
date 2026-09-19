@preconcurrency import Dispatch
@preconcurrency import Foundation
import Runtime

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The program.
///
/// Everything here touches the machine and nothing here decides anything: the
/// environment, the arguments, the signals and the exit. It is deliberately
/// short enough to read in one sitting, because the answer to "what can this
/// build reach" should be one function rather than a search (RT-001).
///
/// **This is the only place in `Sources/` that reads the process
/// environment.** One snapshot, at the top, handed to ``Runtime/Settings``.
/// Every layer then sees the same values, a variable changed under a running
/// process cannot half take effect, and reading the environment while another
/// thread writes it, which is a data race on Linux, cannot happen twice
/// (RT-003, BUILD-2.a).
@main
internal struct BotMain {

    // MARK: - Internal Methods

    internal static func main() async {
        // Before anything opens a socket or writes a line. A write to a peer
        // that has gone away, or to a closed pipe on standard output, raises
        // SIGPIPE, and its default disposition kills the process outright: no
        // report, no exit code from the documented set, no clean shutdown.
        // Ignored here so the write returns EPIPE and the caller handles it
        // like any other failed write.
        signal(SIGPIPE, SIG_IGN)

        let settings = Settings(ProcessInfo.processInfo.environment)
        let arguments = Array(CommandLine.arguments.dropFirst())

        let output = StandardStreams()

        // The verb first, and the surface only for the two verbs that need
        // one. Parsed twice rather than threaded through, because parsing is
        // pure and the alternative is this function deciding what to print
        // for a word it does not recognise.
        //
        // **Building the surface above this was every verb gated on the chat
        // settings.** `bot help` is the one command that has to work on a
        // machine where nothing is configured, and `bot check` exists to
        // list what is wrong with the settings: a refusal that pre-empts it
        // disables the one diagnostic verb with exactly the class of fault
        // it is for, and then tells the operator to run it (RT-026, RUN-9).
        let parsed = RuntimeCommand.parse(arguments)
        // A word this does not recognise builds nothing either: the answer to
        // `bot wibble` is the usage text, not a variable to change.
        let needsSurface = (try? parsed.get())?.needsChatSurface ?? false

        // Built from the same snapshot every other layer reads, so nothing
        // can disagree about what was set.
        //
        // A `run` refusal is printed here rather than carried into the boot,
        // and it is printed **before** the banner. That is the one place in
        // this program where a refusal arrives out of order, and the trade
        // is deliberate: the alternative is a composition root that either
        // builds the surface itself, which is the dependency the whole graph
        // is arranged to prevent, or that is handed a factory instead of a
        // value, which hides the construction from the one function that is
        // meant to show it.
        var chat: (any ChatGateway)?
        var chatRefusal: BootFailure?
        if needsSurface {
            do {
                chat = try await ChatSurface.gateway(settings: settings, log: ChatSurface.log)
            } catch let failure as BootFailure {
                // A dry run keeps the refusal and prints it after its
                // listing, which is the order an operator can act on: what
                // this build reads, then the first thing wrong with it. It is
                // handed a surface that only describes itself, so the listing
                // is the one a start would print rather than the one a build
                // with no chat surface would.
                guard case .success(.check) = parsed else {
                    await output.writeError(
                        failure.lines.map { SecretRedaction.applied(to: $0, settings: settings) }
                    )
                    exit(failure.code.rawValue)
                }
                chat = ChatSurface.described()
                chatRefusal = failure
            } catch {
                await output.writeError([
                    "refused",
                    "  The chat surface could not be built: \(error)",
                    "  This is a fault in the program rather than in your settings."
                ])
                exit(ExitCode.internalError.rawValue)
            }
        }

        let runtime = Runtime(
            seams: RuntimeSeams(
                store: DurableStoreOpener(),
                chain: NodeChainSource(),
                // Nil when no token is configured, and then this build runs
                // exactly as one with no chat surface: it starts, serves its
                // health endpoint and identifies to nothing (RT-014).
                chat: chat,
                output: output,
                // A parameter, never a reading. No payer is compiled into
                // this build, and no variable exists that would add one
                // (BUILD-3, BUILD-3.a).
                spending: .cannotSpend
            )
        )

        switch await runtime.execute(arguments: arguments, settings: settings) {
        case .finished(let code):
            // Last, and after the listing it belongs under. A dry run that
            // found nothing else wrong still exits on this one.
            if let chatRefusal {
                await output.writeError(
                    chatRefusal.lines.map { SecretRedaction.applied(to: $0, settings: settings) }
                )
                exit(chatRefusal.code.rawValue)
            }
            exit(code.rawValue)
        case .running(let instance):
            await stayUp(instance)
        }
    }

    // MARK: - Private Methods

    /// Waits, and puts the port and the lease back on the way out.
    ///
    /// A first signal unwinds properly: the listener stops, the store closes,
    /// which releases the lease that keeps a second instance out, and the
    /// exit is clean. A second signal exits at once, because somebody sending
    /// one has decided that waiting is no longer the right answer (RT-028).
    private static func stayUp(_ instance: RunningInstance) async {
        let sources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                Task {
                    guard await Signals.shared.firstArrival() else {
                        exit(ExitCode.ok.rawValue)
                    }
                    await instance.shutDown()
                }
            }
            source.resume()
            // The default disposition has to go, or the process dies on the
            // signal before the handler above ever runs.
            signal(number, SIG_IGN)
            return source
        }
        await instance.waitUntilStopped()
        for source in sources {
            source.cancel()
        }
        // Zero for a signal, which is the ordinary way out, and something a
        // supervisor will restart on when the instance stopped because a part
        // of it failed.
        exit(await instance.exitCode().rawValue)
    }
}

/// Which signal this is.
///
/// An actor rather than a flag, because two signals can arrive from two
/// threads and the whole question is which of them was first.
internal actor Signals {

    // MARK: - Properties

    /// The one counter for this process.
    internal static let shared = Signals()

    private var seen = 0

    // MARK: - Internal Methods

    /// Whether this is the first signal.
    internal func firstArrival() -> Bool {
        seen += 1
        return seen == 1
    }
}
