import Chain
import Foundation
import Gating
import Testing
@testable import Runtime

/// The rule that a secret never leaves.
///
/// One test rather than one assertion per field: a unique sentinel as the
/// value of every secret entry in the catalogue, the report rendered, and a
/// failure if any sentinel appears anywhere in it. A secret added later
/// without a thought is caught by the same test (CATALOG-6.a, ADOPT-9.a).
@Suite("Nothing prints a secret")
internal struct StartupReportSecretTests {

    // MARK: - Properties

    /// Nothing that could be mistaken for a real credential, and unique
    /// enough that a substring match means something.
    private static func sentinel(_ name: String) -> String {
        "SENTINEL-\(name)-b7f3c1"
    }

    // MARK: - Tests

    @Test("No secret's value appears anywhere in a report that was told all of them")
    internal func noSentinelSurvivesTheReport() async throws {
        var values = Fixture.settings().dictionary
        var sentinels: [String] = []
        for entry in SettingsCatalogue.entries where entry.secrecy == .secret {
            #expect(!entry.isFamily, "a secret family needs its own case here")
            let value = Self.sentinel(entry.pattern)
            values[entry.pattern] = value
            sentinels.append(value)
        }
        // And one inside a node URL's query string, because some providers
        // put the credential in the path and the report is meant to be safe
        // to paste into an issue.
        let inTheURL = Self.sentinel("IN-URL")
        values[ChainEnvironment.nodeURL] = "https://node.example/v2?token=\(inTheURL)"
        sentinels.append(inTheURL)

        #expect(sentinels.count >= 2)

        let settings = Settings(values)
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: settings)

        let everything = await output.allText
        for sentinel in sentinels {
            #expect(!everything.contains(sentinel), "\(sentinel) reached the report")
        }
        #expect(everything.contains("https://node.example"))
        if case .running(let instance) = outcome {
            await instance.shutDown()
        }
    }

    @Test("A secret is reported as set, and not as a length, a prefix or a hash")
    internal func setAndNothingElse() {
        let settings = Settings([ChainEnvironment.apiToken: "a-very-long-secret-value"])
        let text = StartupReportWriter.catalogue(settings: settings)
            .lines
            .joined(separator: "\n")
        #expect(text.contains("set (a secret, never printed)"))
        // A hash of a low entropy secret is a crackable secret, and a length
        // is enough to confirm a guess.
        #expect(!text.contains("24"))
        #expect(!text.contains("a-ve"))
    }

    @Test("A refusal is redacted too, because a loader quotes the value it could not use")
    internal func refusalsAreRedacted() async {
        let secret = Self.sentinel("REFUSAL")
        let settings = Fixture.settings(extras: [
            ChainEnvironment.apiToken: secret,
            TokenProfile.decimalsKey: "99"
        ])
        let output = RecordingOutput()
        _ = await BootSequence(seams: Fixture.seams(output: output)).run(settings: settings)
        let everything = await output.allText
        #expect(!everything.contains(secret))
        #expect(everything.contains(TokenProfile.decimalsKey))
    }

    @Test("A URL is cut back to scheme, host and port wherever it is printed")
    internal func urlsAreCutBack() {
        #expect(
            SecretRedaction.host(of: "https://node.example/v2/status?token=abc")
                == "https://node.example"
        )
        #expect(SecretRedaction.host(of: "http://node.example:8080/x") == "http://node.example:8080")
        #expect(SecretRedaction.host(of: "not a url at all") == "<redacted>")
    }

    @Test("The only derived fact a secret may produce is one the catalogue names")
    internal func onlyNamedDerivedFactsAppear() {
        // The case this exists for is a signing key, whose public account an
        // operator must be able to read to check they funded the right one.
        // There is no payer in this build, so the banner is the cannot-spend
        // form and no derived fact appears at all.
        #expect(SpendCapability.cannotSpend.banner.contains("no payer is compiled in"))
        let payer = FakePayer()
        #expect(SpendCapability.canSpend(payer).banner.contains("PUBLIC-ACCOUNT"))
        #expect(!SpendCapability.canSpend(payer).banner.contains("secret"))
    }
}

/// A payer that exists only so the other half of the banner can be read.
///
/// Nothing in the package conforms to ``SpendingPayer``, which is the point:
/// a build that can spend is a build with a target that did.
internal struct FakePayer: SpendingPayer {

    internal let payerName = "a payer that exists only in this test"
    internal let publicAccount = "PUBLIC-ACCOUNT"
}
