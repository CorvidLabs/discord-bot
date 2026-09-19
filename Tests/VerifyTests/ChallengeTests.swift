import Foundation
import Testing
import Verify

/// The five lines a member reads in their wallet (VERIFY-1, VERIFY-4,
/// VERIFY-6, ADOPT-1.c).
@Suite("The challenge")
struct ChallengeTests {

    // MARK: - Shape

    @Test("A challenge is five lines, with the subject on the third")
    func fiveLinesWithTheSubjectThird() throws {
        let challenge = try VerificationChallenge(
            label: "Wing and Claw verification",
            instanceIdentity: "instance-a",
            subject: "0f1e2d3c4b5a69788796a5b4c3d2e1f0",
            code: "K7QMZ4",
            nonce: String(repeating: "a", count: 32)
        )
        // The exact bytes, line breaks included. A rendering that varies by
        // platform changes what the member's wallet shows and invalidates
        // every challenge already issued.
        #expect(challenge.text == """
            Wing and Claw verification
            Server: instance-a
            Member: 0f1e2d3c4b5a69788796a5b4c3d2e1f0
            Code: K7QMZ4
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            """)
        let lines = challenge.bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        #expect(lines.count == VerificationChallenge.lineCount)
        #expect(VerificationChallenge.subjectLineIndex == 2)
    }

    @Test("The label is the operator's, byte for byte")
    func theLabelIsTheOperatorsOwn() throws {
        // Goes red against a built in label, which puts another community's
        // words in front of the member's wallet (ADOPT-1.c).
        let challenge = try VerificationChallenge.mint(
            label: "  a label with   odd spacing ",
            instanceIdentity: "instance-a",
            subject: "s"
        )
        let firstLine = challenge.text.split(separator: "\n", omittingEmptySubsequences: false).first
        #expect(firstLine.map(String.init) == "  a label with   odd spacing ")
    }

    @Test("The code shown to the member is the code inside the signed bytes")
    func theCodeIsOneValue() throws {
        // Goes red against a code rendered separately for the reply and for
        // the challenge, which is the anti-phishing device silently not
        // working while looking like it works.
        let challenge = try VerificationChallenge.mint(
            label: "L",
            instanceIdentity: "instance-a",
            subject: "s"
        )
        #expect(challenge.code.count == VerificationChallenge.codeCharacterCount)
        #expect(challenge.text.contains(VerificationChallenge.codeLinePrefix + challenge.code))
    }

    // MARK: - Five lines is enforced

    @Test(
        "A label carrying a line break is refused at the mint",
        arguments: ["\u{000A}", "\u{000D}", "\u{2028}", "\u{2029}"]
    )
    func aLabelWithALineBreakIsRefused(breakCharacter: String) throws {
        // Goes red against rendering it anyway, which makes a six line
        // challenge and moves the nonce into the slot the subject check
        // reads by index.
        #expect(throws: VerifyError.challengeValueCarriesLineBreak(field: "challenge label")) {
            _ = try VerificationChallenge.mint(
                label: "before" + breakCharacter + "after",
                instanceIdentity: "instance-a",
                subject: "s"
            )
        }
    }

    @Test("A carriage return followed by a line feed is refused, although it is one Character")
    func aCarriageReturnLineFeedIsRefused() throws {
        // The trap this rule is written against: in Swift "\r\n" is a single
        // Character, so a search for a line feed inside it finds nothing and
        // the check that looked right passes over the one sequence most
        // likely to arrive.
        //
        // Stated over Characters and scalars rather than over
        // `String.contains(_: String)`, because that call is not the same
        // call on both platforms: on Darwin it resolves to the standard
        // library's search over Characters and is false here, and on Linux
        // it resolves to Foundation's substring search and is true. The
        // rule the mint holds is about scalars, so the case is written
        // about scalars and reads the same wherever it runs.
        let label = "before\r\nafter"
        #expect(label.count == 12)
        #expect(!label.contains(where: { $0 == "\n" }))
        #expect(label.unicodeScalars.count == 13)
        #expect(label.unicodeScalars.contains("\u{000D}"))
        #expect(label.unicodeScalars.contains("\u{000A}"))
        #expect(throws: VerifyError.challengeValueCarriesLineBreak(field: "challenge label")) {
            _ = try VerificationChallenge.mint(label: label, instanceIdentity: "i", subject: "s")
        }
    }

    @Test("A label one byte over the bound is refused and one byte under is accepted")
    func theLabelBoundIsExact() throws {
        let underneath = String(repeating: "x", count: VerificationChallenge.maximumLabelByteCount)
        #expect(throws: Never.self) {
            _ = try VerificationChallenge.mint(label: underneath, instanceIdentity: "i", subject: "s")
        }
        let over = underneath + "x"
        #expect(
            throws: VerifyError.challengeLabelTooLong(
                byteCount: VerificationChallenge.maximumLabelByteCount + 1,
                limit: VerificationChallenge.maximumLabelByteCount
            )
        ) {
            _ = try VerificationChallenge.mint(label: over, instanceIdentity: "i", subject: "s")
        }
    }

    @Test("The bound is UTF-8 bytes rather than characters")
    func theBoundIsMeasuredInBytes() throws {
        // Fifty characters that are two bytes each is a hundred bytes, which
        // fits; fifty one does not. A bound counted in characters lets an
        // operator put twice as much in front of a member's wallet.
        let fits = String(repeating: "\u{00E9}", count: 50)
        #expect(fits.utf8.count == 100)
        #expect(throws: Never.self) {
            _ = try VerificationChallenge.mint(label: fits, instanceIdentity: "i", subject: "s")
        }
        #expect(throws: VerifyError.self) {
            _ = try VerificationChallenge.mint(
                label: fits + "\u{00E9}",
                instanceIdentity: "i",
                subject: "s"
            )
        }
    }

    @Test("A subject or an instance identity carrying a line break is refused too")
    func everyRenderedValueIsHeldToTheSameRule() throws {
        #expect(throws: VerifyError.challengeValueCarriesLineBreak(field: "subject")) {
            _ = try VerificationChallenge.mint(label: "L", instanceIdentity: "i", subject: "a\nb")
        }
        #expect(throws: VerifyError.challengeValueCarriesLineBreak(field: "instance identity")) {
            _ = try VerificationChallenge.mint(label: "L", instanceIdentity: "a\nb", subject: "s")
        }
    }

    // MARK: - The subject line

    @Test("The subject line carries the opaque subject the caller supplied and nothing else")
    func theSubjectLineIsTheCallersOwnValue() throws {
        // Goes red against leaving the subject out. Without it a link handed
        // to somebody else produces a genuine looking prompt whose signature
        // binds their wallet to whoever sent the link, because in that
        // attack nothing moves between sessions: the signature is produced
        // for the session it is submitted to (VERIFY-1, VERIFY-6).
        let challenge = try VerificationChallenge.mint(
            label: "L",
            instanceIdentity: "instance-a",
            subject: CoordinatorFixtures.subject
        )
        #expect(VerificationChallenge.subject(inNote: challenge.bytes) == CoordinatorFixtures.subject)
    }

    @Test("A note that is not five lines names no subject")
    func aNoteOfTheWrongShapeNamesNoSubject() {
        #expect(VerificationChallenge.subject(inNote: Data("one\ntwo\nthree".utf8)) == nil)
        #expect(VerificationChallenge.subject(inNote: Data()) == nil)
        #expect(VerificationChallenge.subject(inNote: Data([0xFF, 0x0A, 0x0A, 0x0A, 0x0A])) == nil)
    }

    @Test("A five line note without the subject prefix names no subject")
    func aNoteWithoutThePrefixNamesNoSubject() {
        let note = Data("L\nServer: i\nsomething else\nCode: ABCDEF\nnonce".utf8)
        #expect(VerificationChallenge.subject(inNote: note) == nil)
    }

    // MARK: - The nonce

    @Test("Two thousand mints produce two thousand distinct challenges")
    func theNonceDoesNotCollide() throws {
        // A collision probe rather than a single comparison. A nonce narrow
        // enough to collide under a crowd is fine for two mints a day apart
        // and a single inequality assertion would never see it: the
        // reference this was ported from takes thirty two bits from the
        // front of a UUID.
        var seen: Set<String> = []
        for _ in 0..<2_000 {
            let challenge = try VerificationChallenge.mint(
                label: "L",
                instanceIdentity: "instance-a",
                subject: CoordinatorFixtures.subject
            )
            seen.insert(challenge.nonce)
        }
        #expect(seen.count == 2_000)
    }

    @Test("The nonce is a hundred and twenty eight bits of hexadecimal")
    func theNonceIsFullWidth() throws {
        let challenge = try VerificationChallenge.mint(label: "L", instanceIdentity: "i", subject: "s")
        #expect(challenge.nonce.count == VerificationChallenge.nonceCharacterCount)
        #expect(challenge.nonce.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("The same arguments twice give different challenges")
    func nothingIsDerivedFromTheArguments() throws {
        // Goes red against seeding from the subject or from the clock, which
        // gives two members who run the command together the same challenge
        // and gives anybody who knows when it was minted a head start.
        let first = try VerificationChallenge.mint(label: "L", instanceIdentity: "i", subject: "s")
        let second = try VerificationChallenge.mint(label: "L", instanceIdentity: "i", subject: "s")
        #expect(first != second)
    }

    // MARK: - Comparison

    @Test("A challenge is compared as bytes, whole")
    func challengesAreComparedWhole() throws {
        // Goes red against a trimmed, case folded or prefix comparison, each
        // of which accepts something the member did not sign.
        let base = try VerificationChallenge(
            label: "L", instanceIdentity: "i", subject: "s", code: "ABCDEF", nonce: "0"
        )
        let sameBytes = try VerificationChallenge(
            label: "L", instanceIdentity: "i", subject: "s", code: "ABCDEF", nonce: "0"
        )
        let oneByteDifferent = try VerificationChallenge(
            label: "L", instanceIdentity: "i", subject: "s", code: "ABCDEF", nonce: "1"
        )
        #expect(base == sameBytes)
        #expect(base != oneByteDifferent)
    }
}
