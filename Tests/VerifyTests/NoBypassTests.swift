import Foundation
import Testing
import Algorand
import Verify

/// The standing proof that this module has no way to skip the signature
/// check (BUILD-3, BUILD-3.a, BUILD-3.b).
///
/// This suite exists because of a shape that is real rather than imagined:
/// the implementation this was ported from accepts the literal string
/// `test-transaction` in place of a signed transaction when a setting is on,
/// and a second literal does the same for a message path. It is documented
/// and off by default, and it is still an identity bypass behind a flag:
/// with it on, anybody who can reach the endpoint can claim any address they
/// can type and take whatever that address earns.
///
/// It is also the suite most likely to be deleted one day for looking
/// redundant, which is why the reason is written down beside it.
@Suite("No way round the signature")
struct NoBypassTests {

    // MARK: - Fixed strings

    /// The two literals the reference accepts under its flag, and a range of
    /// others including the empty one, so the refusal is a property of
    /// having no signature rather than a denylist of two strings.
    static let fixedStrings: [String] = [
        "test-transaction",
        "test-signature",
        "",
        " ",
        "true",
        "1",
        "ok",
        "null",
        "undefined",
        "AAAA",
        "signed",
        "{\"valid\":true}"
    ]

    @Test("No fixed string is accepted, and none is a special case", arguments: fixedStrings)
    func noFixedStringIsAProof(candidate: String) async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let outcome = try await coordinator.submit(
            blob: candidate,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        // Refused as ordinary malformed input: one of the two reasons any
        // rubbish gets, with no case anywhere that names it.
        let reason = outcome.refusalReason
        #expect(reason == .blobUnreadable || reason == .transactionUnparsable)
    }

    @Test("A signature over an arbitrary message is refused, with or without a wallet prefix")
    func onlyOneProofShapeIsAccepted() async throws {
        // Goes red against keeping a message signing path as a convenience.
        // It is cheaper to check, its support across wallets is patchier,
        // and a second accepted shape is a second thing to get wrong for no
        // gain. It is also worse than that: the implementation this came
        // from accepts a signature over the raw message **or** over the
        // prefixed one, so one signature is valid over two different byte
        // strings and "they signed exactly this" stops being true.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let bare = try account.sign(session.challenge.bytes)
        var prefixed = Data("MX".utf8)
        prefixed.append(session.challenge.bytes)
        let overPrefixed = try account.sign(prefixed)

        for signature in [bare, overPrefixed] {
            let outcome = try await coordinator.submit(
                blob: signature.base64EncodedString(),
                to: session.id,
                now: CoordinatorFixtures.now
            )
            #expect(outcome.refusalReason != nil)
        }
    }

    @Test("The same input gives the same outcome however this was built")
    func noBuildConfigurationChangesAnything() async throws {
        // There is no compilation condition anywhere in the module, which
        // the source shape suite asserts by reading it. This asserts the
        // behaviour a condition would change: the outcome of one fixed
        // input, which is the same in a debug build and a release build
        // because nothing branches on which one this is (BUILD-3.b).
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let outcome = try await coordinator.submit(
            blob: "test-transaction",
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(outcome.refusalReason == .blobUnreadable)
    }

    // MARK: - The two producers

    @Test("A proved account is produced only by consuming a signature and a session")
    func theOnlyWayToAProvedAccountIsThroughTheCheck() async throws {
        // The structural half is that ``ProvedAccount`` has no public
        // initialiser, so the wrong thing does not compile. The half that
        // compiles perfectly well is a public factory beside it, and that is
        // what the source shape suite reads the public surface for. Here is
        // the behaviour: the one call that yields one takes both a blob and
        // a session.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let outcome = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: session.id,
            now: CoordinatorFixtures.now
        )
        guard case .proved(let proved) = outcome else {
            Issue.record("the proof should have been accepted")
            return
        }
        #expect(proved.address == account.address.description)
        #expect(!proved.usedAuthorizingKey)
        #expect(proved.provedAt == CoordinatorFixtures.now)
    }

    @Test("The checker on its own yields an acceptance, never a proved account")
    func theCheckerYieldsNoAccount() throws {
        // A future route that delivers a proof some other way is a new
        // caller of the checker. It still cannot mint the downstream value:
        // the checker says accepted, and only the call that also spends a
        // session turns that into an account.
        let account = try ProofFixtures.account()
        let challenge = try VerificationChallenge.mint(
            label: CoordinatorFixtures.label,
            instanceIdentity: CoordinatorFixtures.instance,
            subject: CoordinatorFixtures.subject
        )
        let payment = ProofFixtures.proofPayment(for: account, note: challenge.bytes)
        let outcome = ProofChecker.check(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            against: try ProofExpectation(address: account.address.description, challenge: challenge),
            authorizingKeyRetryAvailable: true
        )
        #expect(outcome == .accepted(usedAuthorizingKey: false))
    }
}
