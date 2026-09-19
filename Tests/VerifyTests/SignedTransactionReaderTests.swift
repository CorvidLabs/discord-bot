import Foundation
import Testing
import Algorand
import Verify

/// The reader gets the most hostile suite in the module, because it is hand
/// written binary parsing that will one day be reachable from the internet,
/// in a process that will later hold a signing key (BUILD-2, BUILD-2.a).
@Suite("Reading a submitted signed transaction")
struct SignedTransactionReaderTests {

    // MARK: - Fixture

    /// One canonically encoded proof, and the pieces every case below is
    /// built out of.
    struct Canonical {
        let blob: String
        let decoded: Data
        let signature: Data
        let transactionBytes: Data
        let account: Account
    }

    static func canonical() throws -> Canonical {
        // Repeated until the base64 exercises both characters the two
        // alphabets disagree about, so the URL-safe case is a real case
        // rather than the standard one under another name.
        for _ in 0..<32 {
            let account = try ProofFixtures.account()
            let payment = ProofFixtures.proofPayment(for: account, note: Data("a note".utf8))
            let decoded = try ProofFixtures.envelopeBytes(payment, signedBy: account)
            let blob = decoded.base64EncodedString()
            guard blob.contains("+") || blob.contains("/") else { continue }
            let read = try SignedTransactionReader.read(decoded)
            return Canonical(
                blob: blob,
                decoded: decoded,
                signature: read.signature,
                transactionBytes: read.transactionBytes,
                account: account
            )
        }
        throw FixtureFailure.connectRefused(.blobUnreadable)
    }

    // MARK: - Base64 tolerance

    @Test("Five spellings of one blob yield the same bytes")
    func everySpellingDecodesTheSame() throws {
        // Goes red against accepting only what the canonical encoder emits,
        // which is the bug that works on a laptop and fails on a phone.
        let fixture = try Self.canonical()
        let urlSafe = fixture.blob
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let unpadded = String(fixture.blob.reversed().drop { $0 == "=" }.reversed())
        let spellings = [
            fixture.blob,
            urlSafe,
            unpadded,
            String(urlSafe.reversed().drop { $0 == "=" }.reversed()),
            "  \n" + fixture.blob + " \t"
        ]
        for spelling in spellings {
            #expect(try SignedTransactionReader.decode(spelling) == fixture.decoded)
        }
    }

    @Test("A short hyphenated word is not a blob")
    func ordinaryTextStaysInvalid() {
        // Goes red against translating a hyphen to a plus unconditionally,
        // which turns words into something that decodes and then fails much
        // later with a useless reason.
        #expect(throws: SignedTransactionReadError.blobNotBase64) {
            _ = try SignedTransactionReader.decode("not-base64")
        }
    }

    @Test("A blob of nothing but whitespace is refused")
    func emptyIsRefused() {
        #expect(throws: SignedTransactionReadError.blobEmpty) {
            _ = try SignedTransactionReader.decode("   \n  ")
        }
    }

    @Test(
        "A group of one character left over is not base64, however it is padded",
        arguments: ["AAAAA", "this is not base64 and never will be"]
    )
    func aLeftoverCharacterIsRefused(spelling: String) {
        // One character is six bits, which is never a whole byte, so no
        // padding turns a leftover group into base64.
        //
        // Foundation differs here and the difference is why this case
        // exists. Padding such a group to four appends three `=`, and
        // `Data(base64Encoded:)` refuses that on Darwin while on Linux it
        // decodes the characters in front of it and hands back bytes. The
        // blob then reached the parser on one platform and not the other,
        // and the member read the fourth refusal instead of the third
        // depending on which machine answered.
        #expect(throws: SignedTransactionReadError.blobNotBase64) {
            _ = try SignedTransactionReader.decode(spelling)
        }
    }

    @Test(
        "Padding is the last one or two characters of the last group, or it is not padding",
        arguments: ["AA=A", "A===", "====", "=AAA", "AB==CD==", "AAAAA===", "AA=", "="]
    )
    func paddingBelongsOnlyAtTheEnd(spelling: String) {
        // The two Foundations disagree about these and disagree in opposite
        // directions: `Data(base64Encoded:)` takes `AA=A` and `====` on
        // Darwin and refuses them on Linux, and takes `A===` and `AAAAA===`
        // on Linux and refuses them on Darwin. None of them is base64, so
        // the reader settles the shape itself rather than inheriting
        // whichever Foundation it was built against.
        #expect(throws: SignedTransactionReadError.blobNotBase64) {
            _ = try SignedTransactionReader.decode(spelling)
        }
    }

    @Test("A blob longer than the ceiling is refused before parsing begins")
    func theCeilingIsFirst() {
        // Goes red against parsing first and refusing later, which lets a
        // stranger choose how much work the process does per request. The
        // string is not valid base64 either, so the case only passes if the
        // ceiling really is what fires.
        let ceiling = SignedTransactionReader.blobCeilingByteCount
        let oversized = String(repeating: "!", count: ceiling + 1)
        #expect(
            throws: SignedTransactionReadError.blobOverCeiling(
                byteCount: ceiling + 1,
                ceiling: ceiling
            )
        ) {
            _ = try SignedTransactionReader.decode(oversized)
        }
    }

    // MARK: - The accepted shapes

    @Test("The three accepted shapes yield one identical transaction slice")
    func everyShapeYieldsTheSameTransaction() throws {
        // Goes red against handling only the shape the tests were written
        // against, which is how the codec this was ported from grew every
        // branch it has.
        let fixture = try Self.canonical()
        let bare = fixture.decoded
        var wrapped = MessagePackBytes.array(1)
        wrapped.append(bare)
        let withSigner = MessagePackBytes.envelope([
            ("sgnr", MessagePackBytes.binary(fixture.account.address.bytes)),
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("txn", fixture.transactionBytes)
        ])

        for shape in [bare, wrapped, withSigner] {
            let read = try SignedTransactionReader.read(shape)
            #expect(read.transactionBytes == fixture.transactionBytes)
            #expect(read.signature == fixture.signature)
        }
    }

    @Test("The returned transaction bytes are a sub-range of the input, by offset and length")
    func theSliceIsTheInput() throws {
        // Goes red against any implementation that rebuilds the bytes. This
        // is the one mistake that fails a perfectly good proof and looks
        // like a problem with the cryptography, and the assertion has to be
        // on identity rather than on equality of parsed fields, or it does
        // not catch it.
        let fixture = try Self.canonical()
        let read = try SignedTransactionReader.read(fixture.decoded)
        let range = read.transactionByteRange
        #expect(range.lowerBound > 0)
        #expect(range.upperBound == fixture.decoded.count)
        #expect(Data(fixture.decoded[range]) == read.transactionBytes)
    }

    @Test("An envelope carrying a signer key parses and the signer has nowhere to be surfaced")
    func theSignerKeyIsSkipped() throws {
        // Goes red against returning it, after which somebody wires it to
        // the authorising key and the blob names the key that validates it.
        let fixture = try Self.canonical()
        let stranger = try ProofFixtures.account()
        let read = try SignedTransactionReader.read(
            MessagePackBytes.envelope([
                ("sgnr", MessagePackBytes.binary(stranger.address.bytes)),
                ("sig", MessagePackBytes.binary(fixture.signature)),
                ("txn", fixture.transactionBytes)
            ])
        )
        // The absence is structural: there is no field on the value that
        // could hold it, so this asserts what a reader can assert, which is
        // that the position was not lost and nothing else changed.
        #expect(read.signature == fixture.signature)
        #expect(read.transactionBytes == fixture.transactionBytes)
    }

    @Test("An unknown key of any type is skipped without losing position")
    func anUnknownKeyDoesNotShiftTheFieldsAfterIt() throws {
        // Goes red against a skip that guesses a length, which shifts every
        // field after it and produces a wrong slice rather than an error.
        let fixture = try Self.canonical()
        var nested = MessagePackBytes.map(2)
        nested.append(MessagePackBytes.string("a"))
        nested.append(MessagePackBytes.array(2))
        nested.append(MessagePackBytes.uint(1))
        nested.append(MessagePackBytes.null)
        nested.append(MessagePackBytes.string("b"))
        nested.append(MessagePackBytes.binary(Data([0x01, 0x02, 0x03])))

        let read = try SignedTransactionReader.read(
            MessagePackBytes.envelope([
                ("lsig", nested),
                ("sig", MessagePackBytes.binary(fixture.signature)),
                ("txn", fixture.transactionBytes)
            ])
        )
        #expect(read.transactionBytes == fixture.transactionBytes)
    }

    // MARK: - Absent is zero

    @Test("An absent amount key reads as zero")
    func anAbsentAmountIsZero() throws {
        // The fixture is a real signed zero amount payment, which omits the
        // key because the canonical encoder drops a field holding its zero
        // value. Goes red against requiring it, which refuses every
        // correctly formed proof.
        let fixture = try Self.canonical()
        let read = try SignedTransactionReader.read(fixture.decoded)
        #expect(read.fields.amount == nil)
        #expect(read.fields.amountOrZero == 0)
    }

    @Test("An absent fee key reads as zero rather than as unknown")
    func anAbsentFeeIsZero() throws {
        // Two things now that the fee is a bound rather than an equality.
        // Requiring the key refuses every correctly formed proof, as with
        // the amount. Reading a missing key as unknown is worse and is newly
        // reachable: under an equality both readings refused and the mistake
        // hid, and under a bound it is an accepted proof whose fee nobody
        // checked.
        let fixture = try Self.canonical()
        let read = try SignedTransactionReader.read(fixture.decoded)
        #expect(read.fields.fee == nil)
        #expect(read.fields.feeOrZero == 0)
        #expect(read.fields.feeOrZero <= ProofShape.maximumFeeMicroAlgos)
    }

    @Test("A fee at the bound is carried through as the number it is")
    func aPresentFeeIsRead() throws {
        let account = try ProofFixtures.account()
        let payment = ProofFixtures.proofPayment(
            for: account,
            note: Data("a note".utf8),
            fee: ProofShape.maximumFeeMicroAlgos
        )
        let read = try SignedTransactionReader.read(
            try ProofFixtures.envelopeBytes(payment, signedBy: account)
        )
        #expect(read.fields.fee == ProofShape.maximumFeeMicroAlgos)
    }

    // MARK: - Canonicality

    @Test("A duplicate key at envelope depth is refused")
    func aDuplicateEnvelopeKeyIsRefused() throws {
        // Goes red against last key wins, which is what the parser this was
        // ported from does. A checker that blesses a document meaning two
        // things is not checking one.
        let fixture = try Self.canonical()
        let bytes = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("txn", fixture.transactionBytes)
        ])
        #expect(throws: SignedTransactionReadError.duplicateKey("sig")) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("A duplicate key inside the transaction map is refused")
    func aDuplicateTransactionKeyIsRefused() throws {
        // The concrete attack: `amt` twice, zero first and a large value
        // second, is one document a wallet can display one way and a reader
        // take the other way, under one signature that stays valid over
        // whichever reading is carried off, because the reader slices rather
        // than re-encoding.
        let fixture = try Self.canonical()
        var transaction = MessagePackBytes.map(3)
        transaction.append(MessagePackBytes.string("amt"))
        transaction.append(MessagePackBytes.uint(0))
        transaction.append(MessagePackBytes.string("amt"))
        transaction.append(MessagePackBytes.uint(99))
        transaction.append(MessagePackBytes.string("type"))
        transaction.append(MessagePackBytes.string("pay"))

        let bytes = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("txn", transaction)
        ])
        #expect(throws: SignedTransactionReadError.duplicateKey("amt")) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("An envelope whose keys do not ascend is read, because the reader this came from read it")
    func keysInAnyOrderAreRead() throws {
        // The reader this was ported from switched over keys in whatever
        // order they arrived, and its own regression fixture for a rekeyed
        // account emits `sig`, `txn`, `sgnr` in that order. Refusing that
        // shape is a dead end at step 4, and a submission refused at step 4
        // is never offered the authorising key retry, so the one member the
        // whole seam exists for would have no path at all. Order is not
        // what stops a blob saying two things: a duplicate key is, and that
        // is still refused.
        let fixture = try Self.canonical()
        let read = try SignedTransactionReader.read(
            MessagePackBytes.envelope([
                ("sig", MessagePackBytes.binary(fixture.signature)),
                ("txn", fixture.transactionBytes),
                ("sgnr", MessagePackBytes.binary(fixture.account.address.bytes))
            ])
        )
        #expect(read.signature == fixture.signature)
        #expect(read.transactionBytes == fixture.transactionBytes)

        var transaction = MessagePackBytes.map(2)
        transaction.append(MessagePackBytes.string("type"))
        transaction.append(MessagePackBytes.string("pay"))
        transaction.append(MessagePackBytes.string("amt"))
        transaction.append(MessagePackBytes.uint(0))
        let outOfOrder = try SignedTransactionReader.read(
            MessagePackBytes.envelope([
                ("sig", MessagePackBytes.binary(fixture.signature)),
                ("txn", transaction)
            ])
        )
        #expect(outOfOrder.fields.type == "pay")
        #expect(outOfOrder.fields.amountOrZero == 0)
    }

    @Test("Any byte after the end of the envelope is refused")
    func trailingBytesAreRefused() throws {
        // Goes red against stopping at the first complete value, which lets
        // a blob carry a second document nobody looked at.
        let fixture = try Self.canonical()
        var bytes = fixture.decoded
        bytes.append(0xC0)
        #expect(throws: SignedTransactionReadError.trailingBytes) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    // MARK: - Hostile input

    @Test("Truncation at every byte offset is refused, and none of them traps")
    func everyTruncationIsRefused() throws {
        // A loop over every prefix. Goes red against an unchecked index,
        // which is a crash the whole process takes, reachable by anybody who
        // can post to the route.
        let fixture = try Self.canonical()
        for length in 0..<fixture.decoded.count {
            let prefix = fixture.decoded.prefix(length)
            #expect(throws: (any Error).self) {
                _ = try SignedTransactionReader.read(Data(prefix))
            }
        }
    }

    @Test("A signature that is not sixty four bytes is refused by the reader")
    func aShortSignatureIsRefused() throws {
        // Goes red against handing a short buffer to the cryptography
        // library and trusting whatever comes back.
        let fixture = try Self.canonical()
        let short = Data(fixture.signature.prefix(63))
        let bytes = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(short)),
            ("txn", fixture.transactionBytes)
        ])
        #expect(throws: SignedTransactionReadError.signatureWrongLength(byteCount: 63)) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("A declared length longer than the bytes that arrived is refused without allocating")
    func aDeclaredLengthIsNotBelieved() throws {
        // Goes red against sizing a buffer from a number the input chose,
        // which is how a short hostile blob becomes a large allocation. The
        // header claims a four gigabyte string and three bytes follow it.
        var bytes = MessagePackBytes.map(1)
        bytes.append(contentsOf: [0xDB, 0xFF, 0xFF, 0xFF, 0xFF])
        bytes.append(contentsOf: [0x01, 0x02, 0x03])
        #expect(throws: (any Error).self) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("A declared map count longer than the bytes that arrived is refused")
    func aDeclaredCountIsNotBelieved() {
        // Fifteen pairs declared and two bytes to hold them.
        var bytes = MessagePackBytes.map(15)
        bytes.append(contentsOf: [0xA0, 0xC0])
        #expect(throws: SignedTransactionReadError.declaredLengthExceedsInput) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("A value nested past the depth limit is refused in bounded time")
    func deepNestingIsRefused() throws {
        // Goes red against unbounded recursion, which is a crash by a
        // different route.
        let fixture = try Self.canonical()
        var nested = Data()
        for _ in 0..<(SignedTransactionReader.nestingDepthLimit + 4) {
            nested.append(MessagePackBytes.array(1))
        }
        nested.append(MessagePackBytes.null)
        let bytes = MessagePackBytes.envelope([
            ("lsig", nested),
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("txn", fixture.transactionBytes)
        ])
        #expect(throws: SignedTransactionReadError.nestedTooDeep) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("A map keyed by something that is not a string is refused at any depth")
    func nonStringKeysAreRefused() throws {
        // Comparing such keys for duplicates is not something this reader is
        // prepared to do, and no Algorand encoder produces one, so it is
        // refused rather than walked past.
        let fixture = try Self.canonical()
        var nested = MessagePackBytes.map(1)
        nested.append(MessagePackBytes.uint(1))
        nested.append(MessagePackBytes.null)
        let bytes = MessagePackBytes.envelope([
            ("lsig", nested),
            ("sig", MessagePackBytes.binary(fixture.signature)),
            ("txn", fixture.transactionBytes)
        ])
        #expect(throws: SignedTransactionReadError.notAString) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }

    @Test("An envelope with no signature and one with no transaction are each refused by name")
    func anIncompleteEnvelopeIsRefused() throws {
        let fixture = try Self.canonical()
        #expect(throws: SignedTransactionReadError.signatureMissing) {
            _ = try SignedTransactionReader.read(MessagePackBytes.envelope([("txn", fixture.transactionBytes)]))
        }
        #expect(throws: SignedTransactionReadError.transactionMissing) {
            _ = try SignedTransactionReader.read(
                MessagePackBytes.envelope([("sig", MessagePackBytes.binary(fixture.signature))])
            )
        }
    }

    @Test("An array of more than one signed transaction is refused")
    func onlyASingleElementArrayIsUnwrapped() throws {
        let fixture = try Self.canonical()
        var bytes = MessagePackBytes.array(2)
        bytes.append(fixture.decoded)
        bytes.append(fixture.decoded)
        #expect(throws: (any Error).self) {
            _ = try SignedTransactionReader.read(bytes)
        }
    }
}
