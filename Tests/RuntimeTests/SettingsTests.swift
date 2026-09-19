import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// Settings as a value, read once, recording what was asked for.
///
/// The recording is not an accounting nicety. It is what makes two otherwise
/// impossible checks possible: a variable this build reads and never
/// documents, and a variable an operator set that nothing read (BUILD-2,
/// ADOPT-9.a).
@Suite("Settings, read once and remembered")
internal struct SettingsTests {

    // MARK: - A value, not a machine

    @Test("A test builds one from a literal with nothing installed (BUILD-2.a)")
    internal func builtFromALiteral() {
        let settings = Settings(["A": "1", "B": ""])
        #expect(settings.value("A") == "1")
        #expect(settings.value("B") == "")
        #expect(settings.value("C") == nil)
        #expect(settings.names == ["A", "B"])
    }

    @Test("Values arrive unchanged, so one layer cannot accept what another refuses")
    internal func valuesAreNotTrimmedHere() {
        // Every loader decides what "set" means through `NumberedEnvironment`.
        // A second opinion at this level is exactly how a value with the
        // trailing newline a file gives it became a value in one layer and a
        // refusal in another.
        let settings = Settings(["A": " 1\n"])
        #expect(settings.value("A") == " 1\n")
        #expect(NumberedEnvironment.nonEmpty("A", settings.value) == "1")
    }

    // MARK: - Recording

    @Test("Every key a loader asked for is recorded, set or not")
    internal func recordsEveryKeyAsked() {
        let settings = Settings(["A": "1"])
        let (value, keysRead) = settings.read { reader -> String? in
            _ = reader.lookup("MISSING")
            return reader.lookup("A")
        }
        #expect(value == "1")
        #expect(keysRead == ["A", "MISSING"])
    }

    @Test("A loader handed the reader is audited without knowing it is")
    internal func loadersAreAuditedThroughTheLookupTheyAlreadyTake() throws {
        let settings = Fixture.settings()
        let (token, keysRead) = try settings.read { reader in
            try TokenProfile.load(reader.lookup)
        }
        #expect(token.assetId == 4_242)
        #expect(keysRead.contains(TokenProfile.assetIdKey))
        #expect(keysRead.contains(TokenProfile.decimalsKey))
    }

    @Test("Keys a dictionary-taking loader read are noted from the catalogue, not retyped")
    internal func dictionaryLoaderKeysAreNoted() {
        let settings = Fixture.settings()
        let (_, keysRead) = settings.read { reader in
            reader.note(SettingsCatalogue.chainNames)
        }
        #expect(keysRead.contains(ChainEnvironment.nodeURL))
        #expect(keysRead.count == SettingsCatalogue.chainNames.count)
    }
}
