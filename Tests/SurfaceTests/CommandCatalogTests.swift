import Foundation
import Testing

@testable import Surface

/// What is registered, and what is deliberately not.
@Suite("Command catalogue")
struct CommandCatalogTests {

    @Test("Exactly four commands ship: ping, help, verify, unlink (LEARN-3, LEARN-4, VERIFY-1, VERIFY-3)")
    func exactlyFour() throws {
        let catalog = try Fixture.catalog()
        #expect(catalog.names == ["ping", "help", "verify", "unlink"])
    }

    @Test("A community that only wants roles still gets a catalogue (SPEND-6.c, PLAY-9)")
    func rolesOnlyStillBoots() throws {
        let catalog = try CommandCatalog.build(features: .rolesOnly)
        #expect(catalog.names == ["ping", "help", "verify", "unlink"])
    }

    @Test("With verification off, nothing offers to prove an account (ADOPT-10, ADOPT-10.b)")
    func verificationOffRemovesItsCommands() throws {
        let catalog = try CommandCatalog.build(features: SurfaceFeatures(enabled: []))
        #expect(catalog.names == ["ping", "help"])
        #expect(catalog.command(named: "verify") == nil)
    }

    @Test("Every shipped command declares how long it may take")
    func policiesAreDeclared() throws {
        let catalog = try Fixture.catalog()
        #expect(catalog.command(named: "ping")?.acknowledge == .immediate)
        #expect(catalog.command(named: "help")?.acknowledge == .immediate)
        // Both of these reach a portal or a store before they can answer, and
        // three seconds is not a promise either can keep.
        #expect(catalog.command(named: "verify")?.acknowledge == .deferEphemeral)
        #expect(catalog.command(named: "unlink")?.acknowledge == .deferEphemeral)
    }

    @Test("`/unlink` takes one optional option, so listing does not need an address first")
    func unlinkOptionIsOptional() throws {
        let unlink = try #require(Fixture.catalog().command(named: "unlink"))
        #expect(unlink.options.count == 1)
        #expect(unlink.options[0].name == CommandCatalog.unlinkAccountOption)
        #expect(unlink.options[0].required == false)
    }

    @Test("No shipped command is operator only, so none needs a permission bit to be safe")
    func nothingShippedIsOperatorOnly() throws {
        for command in try Fixture.catalog().commands {
            #expect(command.isOperatorOnly == false)
        }
    }
}
