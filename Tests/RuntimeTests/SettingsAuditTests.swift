import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// What the build makes of variables it did not read.
///
/// Three answers, and the difference between them is the point: read is
/// ordinary, owned and unread is a probable typo that is reported, and
/// reserved for a part this build does not have is a refusal (ADOPT-9.a,
/// RUN-9.a).
@Suite("Variables set, and what became of them")
internal struct SettingsAuditTests {

    // MARK: - Owned, and read by nothing

    @Test("An owned variable nothing read is reported and does not refuse (ADOPT-9.a)")
    internal func ownedAndUnreadIsReportedOnly() throws {
        let settings = Fixture.settings(extras: ["TIER_1_MIM": "100"])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.refusal == nil)
        #expect(audit.unread.map(\.name) == ["TIER_1_MIM"])
    }

    @Test("The entry it is one edit from is offered beside it")
    internal func nearMissIsOffered() throws {
        let settings = Fixture.settings(extras: ["TIER_1_MIM": "100"])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.unread.first?.nearest == "TIER_1_MIN")
    }

    @Test("A family suggestion carries the operator's own number, not a hash")
    internal func familySuggestionKeepsTheNumber() throws {
        let settings = Fixture.settings(extras: ["TIER_9_NAM": "Gold"])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.unread.first?.nearest == "TIER_9_NAME")
    }

    @Test("A variable nothing near is still named, with no guess attached")
    internal func noSuggestionRatherThanAWrongOne() throws {
        let settings = Fixture.settings(extras: ["TOKEN_COMPLETELY_ELSE": "x"])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.unread.map(\.name) == ["TOKEN_COMPLETELY_ELSE"])
        #expect(audit.unread.first?.nearest == nil)
    }

    @Test("Somebody else's variable is ignored, not reported")
    internal func unownedIsIgnored() throws {
        let settings = Fixture.settings(extras: ["PATH": "/usr/bin", "HOME": "/root"])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.unread.isEmpty)
        #expect(audit.reserved.isEmpty)
    }

    // MARK: - Reserved for a part this build has not got

    @Test("A chat token refuses the boot by name, because nothing here would read it (RUN-9.a)")
    internal func chatTokenRefuses() async throws {
        let settings = Fixture.settings(extras: ["DISCORD_BOT_TOKEN": "a-token"])
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output)).run(settings: settings)

        let failure = try #require(outcome.failure)
        #expect(failure.variable == "DISCORD_BOT_TOKEN")
        #expect(failure.code == .configuration)
        #expect(failure.summary.contains("chat surface"))
        // A process that starts, answers healthy and never appears in the
        // server is the outage the SEE family opens with, so this stops
        // before the store is even opened (SEE-1.a).
        #expect(outcome.gatesPassed == [.banner])
    }

    @Test("A verification variable refuses too, and says which part is missing")
    internal func verificationVariableRefuses() {
        let settings = Fixture.settings(extras: ["VERIFY_PORTAL_URL": "https://portal.example"])
        let audit = SettingsAudit.of(settings: settings, keysRead: [])
        #expect(audit.refusal?.variable == "VERIFY_PORTAL_URL")
        #expect(audit.refusal?.summary.contains("wallet verification") == true)
    }

    @Test("A variable set to nothing at all is unset, which is what every loader says (RUN-9.a)")
    internal func anEmptyValueIsNotASetVariable() async throws {
        // `environment: DISCORD_BOT_TOKEN: ${DISCORD_BOT_TOKEN}` in a compose
        // file with nothing in the variable puts an empty one in the
        // environment, and so does a filled-in env template with a line left
        // blank. Every loader in the package already reads blank as unset
        // (`NumberedEnvironment.nonEmpty`), so an audit that refused the boot
        // over one would be this layer refusing what the next one accepts.
        let settings = Fixture.settings(extras: [
            "DISCORD_BOT_TOKEN": "",
            "VERIFY_PORTAL_URL": "   "
        ])
        let audit = SettingsAudit.of(settings: settings, keysRead: [])
        #expect(audit.refusal == nil)
        #expect(audit.reserved.isEmpty)

        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: settings)
        #expect(outcome.failure == nil)
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    @Test("An owned variable set to nothing is not reported as one nothing read")
    internal func anEmptyOwnedVariableIsNotReported() throws {
        let settings = Fixture.settings(extras: ["TIER_9_NAME": ""])
        let loaded = try LoadedConfiguration.load(settings)
        let audit = SettingsAudit.of(settings: settings, keysRead: loaded.keysRead)
        #expect(audit.unread.isEmpty)
    }

    @Test("The refusal reads as a sentence, article and all")
    internal func theRefusalIsASentence() {
        let settings = Fixture.settings(extras: ["DISCORD_BOT_TOKEN": "a-token"])
        let audit = SettingsAudit.of(settings: settings, keysRead: [])
        #expect(audit.refusal?.summary.contains("this build has no chat surface") == true)
        #expect(audit.refusal?.summary.contains("no a chat surface") == false)
    }

    @Test("The reserved prefixes are stated, not left to whoever reads this")
    internal func reservedPrefixesAreStated() {
        #expect(SettingsCatalogue.reservedPrefixes == ["DISCORD_", "VERIFY_"])
        #expect(SettingsCatalogue.reservedPrefix(of: "DISCORD_BOT_TOKEN") == "DISCORD_")
        #expect(SettingsCatalogue.reservedPrefix(of: "TOKEN_ASSET_ID") == nil)
    }

    @Test("The undescribed key outranks the reserved one, because it is ours and not theirs")
    internal func undescribedOutranksReserved() {
        let settings = Fixture.settings(extras: ["DISCORD_BOT_TOKEN": "a-token"])
        let audit = SettingsAudit.of(settings: settings, keysRead: ["NOT_IN_THE_CATALOGUE"])
        #expect(audit.refusal?.code == .internalError)
    }
}
