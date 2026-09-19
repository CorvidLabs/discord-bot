import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// What an operator reads back at every start.
///
/// ADOPT-9 is that they read back what the bot made of their settings, not
/// that the settings loaded. The difference is the section a dropped rung
/// shows up in, minutes before a sweep acts on it (ADOPT-9.a).
@Suite("The startup report")
internal struct StartupReportTests {

    // MARK: - The banner and the version

    @Test("The banner is the first line of every start (BUILD-3.b, SPEND-6.c)")
    internal func bannerIsFirst() async {
        let output = RecordingOutput()
        _ = await BootSequence(seams: Fixture.seams(output: output)).run(settings: Settings([:]))
        let lines = await output.out
        #expect(lines.first == "discord-bot")
        #expect(lines.dropFirst().first?.contains("cannot move anything") == true)
    }

    @Test("The version says it is what the source claimed, not what was built (SEE-12)")
    internal func versionIsHonestAboutItself() {
        let section = StartupReportWriter.opening(capability: .cannotSpend)
        #expect(section.lines.contains { $0.contains(RuntimeVersion.current) })
        #expect(section.lines.contains { $0.contains("not a stamp of what was built") })
    }

    // MARK: - What it made of them

    @Test("Every rung prints its name, its whole tokens and its smallest units (RT-021)")
    internal func everyRungIsPrinted() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let section = StartupReportWriter.understanding(configuration: configuration)
        let text = section.lines.joined(separator: "\n")
        #expect(text.contains("Bronze: 100 whole (100,000,000 smallest units)"))
        #expect(text.contains("Silver: 1,000 whole (1,000,000,000 smallest units)"))
        #expect(text.contains("role-bronze"))
    }

    @Test("A dropped rung reads as a shorter ladder, naming where the list stopped (ADOPT-9.a)")
    internal func aDroppedRungIsVisible() throws {
        // Two rungs set, the third left out, a fourth written by mistake.
        // The gap ends the ladder, and the report says which variable it
        // stopped at rather than leaving an operator to count.
        let settings = Fixture.settings(extras: [
            "TIER_4_NAME": "Gold",
            "TIER_4_MIN": "10000"
        ])
        let configuration = try LoadedConfiguration.load(settings)
        #expect(configuration.gating.ladder.rungs.count == 2)
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Ladder, 2 rungs"))
        #expect(text.contains("the ladder stopped at TIER_3_NAME, which is not set"))
        #expect(!text.contains("Gold"))
    }

    @Test("An empty catalogue of collections or pools prints as empty (ADOPT-6.b)")
    internal func emptyCataloguesArePrinted() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Collections: none"))
        #expect(text.contains("Pools: none"))
        #expect(text.contains("Token links: none"))
    }

    @Test("An empty administrator list prints as nobody, which is legitimate")
    internal func emptyAllowlistIsNobody() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Administrators: nobody"))
        #expect(text.contains("stopped at ADMIN_WALLET_1"))
    }

    @Test("The administrator list prints in full when there is one (CATALOG-7)")
    internal func allowlistPrintsInFull() throws {
        let configuration = try LoadedConfiguration.load(
            Fixture.settings(extras: ["ADMIN_WALLET_1": "ADMIN-ONE", "ADMIN_WALLET_2": "ADMIN-TWO"])
        )
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Administrators, 2"))
        #expect(text.contains("ADMIN-ONE"))
        #expect(text.contains("ADMIN-TWO"))
    }

    @Test("The token prints its asset, ticker, name and precision")
    internal func tokenIsPrinted() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Token: asset 4242, TOKEN, TOKEN, 6 decimal places"))
    }

    @Test("The node prints as a host, which is what says which network this is (ADOPT-12.b)")
    internal func nodePrintsAsAHost() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.understanding(configuration: configuration)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("Node: https://node.example"))
    }

    // MARK: - Parts

    @Test("Each part that is off says why it is off (ADOPT-10.a, BUILD-1.a)")
    internal func offPartsSayWhy() throws {
        let configuration = try LoadedConfiguration.load(Fixture.settings())
        let text = StartupReportWriter.parts(
            configuration: configuration,
            capability: .cannotSpend,
            chainOutcome: .confirmed
        ).lines.joined(separator: "\n")
        #expect(text.contains("off  collections, because no COLLECTION_1_ID is set"))
        #expect(text.contains("off  pools, because no POOL_1_ID is set"))
        #expect(text.contains("off  chat surface"))
        #expect(text.contains("off  spending"))
        #expect(text.contains("on   store"))
    }

    // MARK: - The store and the socket

    @Test("A start that made the store says so, loudly")
    internal func createdStoreIsLoud() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(output: output, store: InMemoryStoreOpener(createdFile: true))
        ).run(settings: Fixture.settings())
        let printed = await output.outText
        #expect(printed.contains("This start CREATED the store"))
        #expect(printed.contains("Migrations applied by this start: 0001-initial"))
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    @Test("The report cannot be turned off by any setting (RT-019)")
    internal func noSettingSuppressesIt() async {
        // There is no variable that suppresses it, so the check is that
        // setting everything in the catalogue still prints one.
        var values: [String: String] = [:]
        for entry in SettingsCatalogue.entries where !entry.isFamily {
            values[entry.pattern] = "0"
        }
        let output = RecordingOutput()
        _ = await BootSequence(seams: Fixture.seams(output: output)).run(settings: Settings(values))
        let printed = await output.outText
        #expect(printed.contains("discord-bot"))
        #expect(printed.contains("Settings"))
    }
}
