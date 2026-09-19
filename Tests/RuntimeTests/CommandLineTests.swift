import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// The four verbs, and what each one costs.
///
/// ADOPT-4 is a clean machine to a running process from the README alone, and
/// RUN-9 is pointing a new version at your settings before taking it. Both
/// rest on the two verbs that touch nothing being honest about touching
/// nothing.
@Suite("What the binary takes")
internal struct CommandLineTests {

    // MARK: - Parsing

    @Test("No argument is run, which is what bare `swift run` does")
    internal func noArgumentIsRun() {
        #expect(RuntimeCommand.parse([]) == .success(.run))
    }

    @Test("Each of the four verbs parses")
    internal func theFourVerbs() {
        for command in RuntimeCommand.allCases {
            #expect(RuntimeCommand.parse([command.rawValue]) == .success(command))
        }
        #expect(RuntimeCommand.allCases.count == 4)
    }

    @Test("An argument nobody recognises exits with the usage code and prints the four")
    internal func unknownArgumentIsUsage() async {
        switch RuntimeCommand.parse(["sweep"]) {
        case .success(let command):
            Issue.record("`sweep` parsed as \(command)")
        case .failure(let failure):
            #expect(failure.code == .usage)
        }

        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(arguments: ["sweep"], settings: Fixture.settings())
        #expect(result.exitCode == .usage)
        let printed = await output.outText
        #expect(printed.contains("run"))
        #expect(printed.contains("check"))
        #expect(printed.contains("rehearse"))
        #expect(printed.contains("help"))
    }

    @Test("A verb with extra arguments is a usage error rather than a silently ignored one")
    internal func extraArgumentsAreUsage() {
        switch RuntimeCommand.parse(["check", "--verbose"]) {
        case .success(let command):
            Issue.record("parsed as \(command)")
        case .failure(let failure):
            #expect(failure.code == .usage)
        }
    }

    // MARK: - help

    @Test("help prints the four and exits cleanly")
    internal func helpPrintsTheFour() async {
        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(.help, settings: Settings([:]))
        #expect(result.exitCode == .ok)
        let printed = await output.outText
        #expect(printed.contains("usage: bot [run|check|rehearse|help]"))
        #expect(printed.contains("78 the configuration is wrong"))
    }

    // MARK: - check

    @Test("check with nothing set prints the whole catalogue and the first refusal (RT-026)")
    internal func checkOnAnEmptyMachine() async {
        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(.check, settings: Settings([:]))
        #expect(result.exitCode == .configuration)

        let printed = await output.outText
        for entry in SettingsCatalogue.entries {
            #expect(printed.contains(entry.pattern), "\(entry.pattern) is not in the listing")
        }
        #expect(printed.contains("UNSET, and required"))

        let errors = await output.errorText
        #expect(errors.contains(TokenProfile.assetIdKey))
        // The refusal reports the first thing wrong, because the loaders
        // throw on the first bad value. Naming the command that lists the
        // rest is what turns that into one round trip rather than four
        // (RT-009).
        #expect(errors.contains(BootFailure.listingCommand))
    }

    @Test("check opens no file and makes no request, proved with a path that cannot exist")
    internal func checkTouchesNothing() async {
        // A store path in a directory that does not exist and a node URL
        // that would fail. A `check` that opened either would refuse; it
        // exits cleanly instead.
        let settings = Fixture.settings(
            storePath: "/nonexistent-\(UUID().uuidString)/store.db",
            extras: [ChainEnvironment.nodeURL: "https://node.invalid"]
        )
        let output = RecordingOutput()
        let result = await Runtime(
            seams: Fixture.seams(
                output: output,
                store: RefusingStoreOpener(.unusable(path: "x", reason: "nobody should open this")),
                chain: StubChainSource(failure: ChainError.network("nobody should ask"))
            )
        ).execute(.check, settings: settings)
        #expect(result.exitCode == .ok)

        let printed = await output.outText
        #expect(printed.contains("Nothing below was opened, bound or asked"))
        #expect(printed.contains("Not checked here: whether this volume can promise a write"))
        #expect(!printed.contains("nobody should open this"))
    }

    @Test("check prints the same understanding a start would")
    internal func checkPrintsTheSameReport() async {
        let output = RecordingOutput()
        _ = await Runtime(seams: Fixture.seams(output: output))
            .execute(.check, settings: Fixture.settings())
        let printed = await output.outText
        #expect(printed.contains("Token: asset 4242"))
        #expect(printed.contains("Ladder, 2 rungs"))
        #expect(printed.contains("This build cannot move anything"))
    }

    @Test("check reports a variable nothing read, and still exits cleanly")
    internal func checkReportsNearMisses() async {
        let output = RecordingOutput()
        let result = await Runtime(seams: Fixture.seams(output: output))
            .execute(.check, settings: Fixture.settings(extras: ["TIER_1_MIM": "100"]))
        #expect(result.exitCode == .ok)
        let printed = await output.outText
        #expect(printed.contains("TIER_1_MIM is set and nothing read it. Did you mean TIER_1_MIN?"))
    }
}
