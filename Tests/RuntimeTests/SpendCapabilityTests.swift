import Foundation
import Testing
@testable import Runtime

/// Whether this build can move anything, and why no variable can change it.
///
/// BUILD-3 asks for a build that cannot spend to be unmistakably different
/// from one that can, and BUILD-3.a forbids a setting that merely quietens
/// output from being mistakable for one that stops money moving.
@Suite("Spending is a parameter, never a reading")
internal struct SpendCapabilityTests {

    // MARK: - No path from a setting

    @Test("Every catalogue variable, truthy and then falsy, leaves the capability alone")
    internal func noVariableChangesIt() async {
        for value in ["1", "true", "yes", "on", "0", "false", "no", "off", ""] {
            var values: [String: String] = [:]
            for entry in SettingsCatalogue.entries where !entry.isFamily {
                values[entry.pattern] = value
            }
            let output = RecordingOutput()
            let seams = Fixture.seams(output: output, spending: .cannotSpend)
            _ = await BootSequence(seams: seams).run(settings: Settings(values))
            let printed = await output.outText
            #expect(printed.contains("This build cannot move anything"), "with every variable `\(value)`")
            #expect(!printed.contains("This build can sign"), "with every variable `\(value)`")
        }
    }

    @Test("A caller that passes the other case gets the other banner, and nothing else does")
    internal func theCapabilityIsExactlyWhatWasPassed() async {
        let output = RecordingOutput()
        let seams = Fixture.seams(output: output, spending: .canSpend(FakePayer()))
        _ = await BootSequence(seams: seams).run(settings: Fixture.settings())
        let printed = await output.outText
        #expect(printed.contains("This build can sign"))
        #expect(printed.contains("PUBLIC-ACCOUNT"))
    }

    // MARK: - What the banner says

    @Test("At this commit every real build prints the cannot-spend banner (HOST-7, HOST-7.a)")
    internal func everyRealBuildCannotSpend() {
        // A consequence of the graph rather than of a default: nothing in the
        // package implements the payer protocol, so making a build that can
        // spend means adding a target, which is an edge in the manifest and a
        // line in the disclosure document.
        #expect(!SpendCapability.cannotSpend.canSign)
        #expect(
            SpendCapability.cannotSpend.banner
                == "This build cannot move anything: no payer is compiled in, and no setting "
                    + "can add one."
        )
    }

    @Test("The parts list says spending is off, and says no setting switches it on (SPEND-6.c)")
    internal func partsSaysSpendingIsOff() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.parts(
            configuration: configuration,
            capability: .cannotSpend,
            chainOutcome: nil
        ).lines.joined(separator: "\n")
        #expect(text.contains("no payer is compiled into this build"))
        #expect(text.contains("No setting can switch it on, and none stops it either"))
    }
}
