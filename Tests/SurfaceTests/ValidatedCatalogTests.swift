import Foundation
import Testing

@testable import Surface

/// Proof that a catalogue was checked, and what it is worth.
///
/// An invalid bulk registration is a `400`, the boot waiting on it fails, and
/// under a supervisor that restarts the process it fails again for ever. The
/// validator has always existed; what is new is that nothing can register
/// without having run it (`ADOPT-2`).
@Suite("The validated catalogue")
struct ValidatedCatalogTests {

    // MARK: - What it proves

    @Test("The validator is the only thing that makes one")
    func onlyTheValidatorMakesOne() throws {
        // What this asserts by existing rather than by running: the
        // initialiser is internal to `Surface`, so
        //
        //     ValidatedCatalog(catalog: CommandCatalog(commands: [broken]))
        //
        // does not compile outside this module, and the registrar takes this
        // type. Inside the module it does compile, which is why the gate
        // that counts is the source check over `Sources/` in the adapter's
        // own suite: exactly one file calls the initialiser.
        let catalog = try CommandCatalog.build(features: .rolesOnly)
        let validated = try CommandValidator.validated(catalog)
        #expect(validated.catalog == catalog)
        #expect(validated.commands == catalog.commands)
        #expect(validated.names == catalog.names)
    }

    @Test("A catalogue that breaks a rule produces no proof at all")
    func abrokenCatalogueProducesNothing() {
        let broken = CommandCatalog(commands: [
            CommandDefinition(name: "Shouty", description: "", acknowledge: .immediate)
        ])
        #expect(throws: CommandCatalogInvalid.self) {
            _ = try CommandValidator.validated(broken)
        }
    }

    @Test("The rule the original paid for is still the one that fails first")
    func requiredAfterOptionalStillFails() throws {
        let broken = CommandCatalog(commands: [
            CommandDefinition(
                name: "thing",
                description: "A thing",
                options: [
                    CommandOption(type: .string, name: "first", description: "Optional", required: false),
                    CommandOption(type: .string, name: "second", description: "Required", required: true)
                ],
                acknowledge: .immediate
            )
        ])
        let failure = try #require(
            throws: CommandCatalogInvalid.self,
            performing: { _ = try CommandValidator.validated(broken) }
        )
        #expect(failure.issues.contains { $0.rule == .requiredAfterOptional })
    }

    @Test("The shipped catalogue passes, whichever parts are switched on")
    func everyShippedCombinationPasses() throws {
        let everything = SurfaceFeatures(enabled: Set(SurfaceFeature.allCases))
        for features in [SurfaceFeatures(enabled: []), .rolesOnly, everything] {
            #expect(throws: Never.self) {
                _ = try CommandValidator.validated(CommandCatalog.build(features: features))
            }
        }
    }

    @Test("With nothing switched on, two commands survive and they need nothing")
    func nothingSwitchedOnLeavesTwo() throws {
        // What the assembled executable registers today. `/verify` and
        // `/unlink` need a half that is not wired into it, and a command
        // that cannot finish is never offered (`ADOPT-10.b`).
        let catalog = try CommandCatalog.build(features: SurfaceFeatures(enabled: []))
        #expect(catalog.names == [CommandCatalog.ping, CommandCatalog.help])
    }
}
