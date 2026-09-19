import Foundation
import Testing
import Algorand
import Verify

/// The ordered check: fifteen reasons, one case per reason, each constructed
/// so that **every later reason is also violated** (VERIFY-1, VERIFY-2,
/// VERIFY-4).
///
/// That construction is the whole point. A suite that violates one rule at a
/// time passes against an implementation that evaluates them in any order at
/// all, and the order is what stands between a member who mis-tapped and a
/// member told their signature is bad.
@Suite("Refusing a proof, in order")
struct ProofRefusalTests {

    // MARK: - Fixtures

    /// A submission that fails everything from the blob onwards.
    static let rubbish: String = "this is not base64 and never will be"

    /// Bytes no key ever signed.
    static let deadSignature: Data = Data(repeating: 0, count: 64)

    /// A transaction map violating every field rule at once, with whichever
    /// of them a case wants put right.
    ///
    /// Keys are written in ascending order because that is what the reader
    /// insists on, and the cases about key order live in the reader's own
    /// suite rather than here.
    static func wrongTransaction(
        type: String = "pay",
        sender: Data = Data(repeating: 0x44, count: 32),
        receiver: Data = Data(repeating: 0x22, count: 32),
        amount: UInt8 = 99,
        fee: UInt16 = 5_000,
        forbidden: Bool = true,
        note: Data
    ) -> Data {
        var pairs: [(String, Data)] = []
        if amount > 0 {
            pairs.append(("amt", MessagePackBytes.uint(amount)))
        }
        if fee > 0 {
            pairs.append(("fee", MessagePackBytes.uint16(fee)))
        }
        pairs.append(("note", MessagePackBytes.binary(note)))
        pairs.append(("rcv", MessagePackBytes.binary(receiver)))
        if forbidden {
            pairs.append(
                (
                    ForbiddenTransactionField.rekey.wireName,
                    MessagePackBytes.binary(Data(repeating: 0x33, count: 32))
                )
            )
        }
        pairs.append(("snd", MessagePackBytes.binary(sender)))
        if !type.isEmpty {
            pairs.append(("type", MessagePackBytes.string(type)))
        }
        return MessagePackBytes.envelope(pairs)
    }

    /// That transaction in an envelope, under a signature nothing produced.
    static func unsignedBlob(_ transaction: Data) -> String {
        MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(deadSignature)),
            ("txn", transaction)
        ]).base64EncodedString()
    }

    /// A challenge of the right shape minted for somebody else.
    static func otherSubjectChallenge() throws -> VerificationChallenge {
        try VerificationChallenge.mint(
            label: CoordinatorFixtures.label,
            instanceIdentity: CoordinatorFixtures.instance,
            subject: CoordinatorFixtures.otherSubject
        )
    }

    // MARK: - 1. Session state

    @Test("A proof against a consumed session reports session state, though it is also expired")
    func consumedComesFirst() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let good = try ProofFixtures.blob(payment, signedBy: account)
        guard case .proved = try await coordinator.submit(
            blob: good,
            to: session.id,
            now: CoordinatorFixtures.now
        ) else {
            Issue.record("the first submission should have been accepted")
            return
        }

        // Also expired, and also rubbish. State still wins.
        let outcome = try await coordinator.submit(
            blob: Self.rubbish,
            to: session.id,
            now: session.expiresAt.addingTimeInterval(60)
        )
        #expect(outcome.refusalReason == .sessionUnavailable)
    }

    @Test("A session that has spent its allowance reports its own reason, at the same step")
    func exhaustionHasItsOwnReason() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        for _ in 0..<VerificationLimits.maximumSubmissionsPerSession {
            _ = try await coordinator.submit(blob: Self.rubbish, to: session.id, now: CoordinatorFixtures.now)
        }
        let outcome = try await coordinator.submit(
            blob: Self.rubbish,
            to: session.id,
            now: session.expiresAt.addingTimeInterval(60)
        )
        #expect(outcome.refusalReason == .submissionsExhausted(.session))
        #expect(ProofRefusalReason.submissionsExhausted(.session).step == 1)
        #expect(ProofRefusalReason.submissionsExhausted(.subject).step == 1)
    }

    // MARK: - 2. Expiry

    @Test("An expired session reports expiry, though the blob is also rubbish")
    func expiryComesBeforeTheBlob() async throws {
        // Goes red against reporting the decode failure, which sends a
        // member off to debug their wallet when what they need is a new
        // link.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let outcome = try await coordinator.submit(
            blob: Self.rubbish,
            to: session.id,
            now: session.expiresAt
        )
        #expect(outcome.refusalReason == .sessionExpired)
    }

    // MARK: - 3 to 15, through the checker the coordinator calls

    /// One expectation for an account, its challenge, and an optional pin.
    static func expectation(
        for account: Account,
        challenge: VerificationChallenge,
        pinnedTo pinned: Address? = nil,
        authorizingKey: Data? = nil
    ) throws -> ProofExpectation {
        try ProofExpectation(
            address: account.address.description,
            challenge: challenge,
            pinnedAddress: pinned?.description,
            authorizingKey: authorizingKey
        )
    }

    static func challenge() throws -> VerificationChallenge {
        try VerificationChallenge.mint(
            label: CoordinatorFixtures.label,
            instanceIdentity: CoordinatorFixtures.instance,
            subject: CoordinatorFixtures.subject
        )
    }

    static func refusal(
        _ blob: String,
        _ expectation: ProofExpectation,
        retryAvailable: Bool = true
    ) -> ProofRefusalReason? {
        switch ProofChecker.check(
            blob: blob,
            against: expectation,
            authorizingKeyRetryAvailable: retryAvailable
        ) {
        case .refused(let reason): return reason
        case .accepted: return nil
        }
    }

    @Test("A malformed blob reports the decode failure, though what is inside would also have failed")
    func decodeComesThird() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        #expect(Self.refusal(Self.rubbish, expectation) == .blobUnreadable)
    }

    @Test("Bytes that decode but do not parse report the parse failure")
    func parseComesFourth() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let notATransaction = Data([0xC0]).base64EncodedString()
        #expect(Self.refusal(notATransaction, expectation) == .transactionUnparsable)
    }

    @Test("A transaction missing a required field reports that field by name")
    func missingFieldsComeFifth() throws {
        // Every later reason is violated too: the type is absent so it is
        // not a payment, the sender is absent so it matches nothing, the
        // amount and the fee are wrong, a rekey is present, and nothing
        // signed it.
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = MessagePackBytes.envelope([
            ("amt", MessagePackBytes.uint(99)),
            ("fee", MessagePackBytes.uint16(5_000)),
            (
                ForbiddenTransactionField.rekey.wireName,
                MessagePackBytes.binary(Data(repeating: 0x33, count: 32))
            )
        ])
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .missingField(.type))
    }

    @Test(
        "Each required field missing is reported by its own name",
        arguments: RequiredTransactionField.allCases
    )
    func everyMissingFieldIsNamed(missing: RequiredTransactionField) throws {
        // Goes red against one reason for every failure, which tells the
        // member nothing they can act on. Each case leaves out one field and
        // carries every earlier one, so the name that comes back is the name
        // of the field that is actually absent.
        let account = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let expectation = try Self.expectation(for: account, challenge: challenge)
        var pairs: [(String, Data)] = [("amt", MessagePackBytes.uint(99))]
        if missing != .note {
            pairs.append(("note", MessagePackBytes.binary(try Self.otherSubjectChallenge().bytes)))
        }
        if missing != .receiver {
            pairs.append(("rcv", MessagePackBytes.binary(Data(repeating: 0x22, count: 32))))
        }
        if missing != .sender {
            pairs.append(("snd", MessagePackBytes.binary(Data(repeating: 0x44, count: 32))))
        }
        if missing != .type {
            pairs.append(("type", MessagePackBytes.string("pay")))
        }
        let blob = Self.unsignedBlob(MessagePackBytes.envelope(pairs))
        #expect(Self.refusal(blob, expectation) == .missingField(missing))
    }

    @Test("A transaction whose type is not a payment is refused before the sender is looked at")
    func transactionTypeComesSixth() throws {
        // Goes red against reading a transaction's fields without asking
        // what kind of transaction it is, which is how a shape nobody
        // designed for reaches checks written for a payment.
        let account = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let expectation = try Self.expectation(for: account, challenge: challenge)
        let transaction = Self.wrongTransaction(
            type: "axfer",
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .notAPayment)
        #expect(challenge.subject == CoordinatorFixtures.subject)
    }

    @Test("A real signed asset transfer is refused before anything reads it as a payment")
    func anAssetTransferIsNotAProof() throws {
        // An asset transfer names its receiver `arcv`, so what a payment
        // calls `rcv` is not there at all and the missing field fires one
        // step before the type does. That is the order the contract fixes,
        // and it is the right way round: the member is told a field is
        // missing rather than being left to work out that their wallet sent
        // a different kind of transaction. The type refusal has its own
        // case above, over a transaction that carries all four fields.
        let account = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let transfer = ProofFixtures.assetTransfer(for: account, note: challenge.bytes)
        let blob = try ProofFixtures.blob(transfer, signedBy: account)
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(Self.refusal(blob, expectation) == .missingField(.receiver))
    }

    @Test("A proof on a pinned session reports the pinned address, not the sender")
    func pinnedAddressComesSeventh() throws {
        // Goes red against folding the pin into the sender check. The two
        // are different sentences: this is not the account you named, and
        // this is not the account you connected. Whenever both hold the
        // first is the one the member can act on, because they chose it. A
        // case asserting only "refused" passes against an implementation
        // that never returns the pinned reason at all.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let expectation = try ProofExpectation(
            address: stranger.address.description,
            challenge: challenge,
            pinnedAddress: account.address.description
        )
        let transaction = Self.wrongTransaction(
            sender: Data(repeating: 0x44, count: 32),
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .pinnedAddressMismatch)
    }

    @Test("An unpinned session skips the pinned position, and sender is the first address reason")
    func anUnpinnedSessionSkipsThePin() throws {
        // Goes red against a pin defaulted to something, after which a
        // member who named no wallet is refused for not matching an address
        // they never chose.
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = Self.wrongTransaction(note: try Self.otherSubjectChallenge().bytes)
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .senderMismatch)
    }

    @Test("A proof signed by a different account reports the sender, not the signature")
    func senderComesEighth() throws {
        // A member with the wrong account selected must be told that: it is
        // something they can fix and a bad signature is not.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let payment = ProofFixtures.proofPayment(for: stranger, note: challenge.bytes)
        let blob = try ProofFixtures.blob(payment, signedBy: stranger)
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(Self.refusal(blob, expectation) == .senderMismatch)
    }

    @Test("A transaction paying somebody else reports the receiver")
    func receiverComesNinth() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = Self.wrongTransaction(
            sender: account.address.bytes,
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .receiverMismatch)
    }

    @Test("A non-zero amount is refused")
    func amountComesTenth() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = Self.wrongTransaction(
            sender: account.address.bytes,
            receiver: account.address.bytes,
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .amountNotZero)
    }

    @Test("A fee above the network minimum is refused, with a valid signature over it")
    func feeComesEleventh() throws {
        // Three things at once. Asking the page for a zero fee and never
        // checking it, which is what an earlier draft of this contract did:
        // a hostile page builds the self payment with the right note and
        // the fee set to the member's whole balance, the bot certifies it
        // as proof of ownership, and the page still holds the blob and can
        // submit it. Pinning the check at zero instead of at the minimum,
        // which refuses every wallet that raises a fee on the member's
        // behalf. And a bound written one either way, which is why both
        // edges are asserted rather than one.
        let account = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let expectation = try Self.expectation(for: account, challenge: challenge)

        let atBound = ProofFixtures.proofPayment(
            for: account,
            note: challenge.bytes,
            fee: ProofShape.maximumFeeMicroAlgos
        )
        #expect(
            ProofChecker.check(
                blob: try ProofFixtures.blob(atBound, signedBy: account),
                against: expectation,
                authorizingKeyRetryAvailable: true
            ) == .accepted(usedAuthorizingKey: false)
        )

        let overBound = ProofFixtures.proofPayment(
            for: account,
            note: challenge.bytes,
            fee: ProofShape.maximumFeeMicroAlgos + 1
        )
        #expect(
            Self.refusal(try ProofFixtures.blob(overBound, signedBy: account), expectation)
                == .feeAboveBound
        )
    }

    @Test("A fee set to a whole balance is refused at the fee step, before the forbidden fields")
    func feeComesBeforeForbiddenFields() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = Self.wrongTransaction(
            sender: account.address.bytes,
            receiver: account.address.bytes,
            amount: 0,
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(Self.refusal(Self.unsignedBlob(transaction), expectation) == .feeAboveBound)
    }

    @Test("A forbidden field is refused before the subject and the note")
    func forbiddenFieldsComeTwelfth() throws {
        let account = try ProofFixtures.account()
        let expectation = try Self.expectation(for: account, challenge: try Self.challenge())
        let transaction = Self.wrongTransaction(
            sender: account.address.bytes,
            receiver: account.address.bytes,
            amount: 0,
            fee: 0,
            note: try Self.otherSubjectChallenge().bytes
        )
        #expect(
            Self.refusal(Self.unsignedBlob(transaction), expectation)
                == .forbiddenField(.rekey)
        )
    }

    @Test("A proof whose challenge names another subject reports the subject, not the note")
    func subjectComesThirteenth() throws {
        // Two things. Building the expected challenge out of the submitted
        // note, which is a tempting simplification and turns the note
        // comparison into a tautology. And placing the subject reason after
        // the note: the note is compared byte for byte, a proof naming
        // another subject differs in the note as well, so the note reason
        // fires first and the subject reason is unreachable. A case
        // asserting only "refused" passes against that, so this asserts
        // which reason.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let relayed = try Self.otherSubjectChallenge()
        let payment = ProofFixtures.proofPayment(for: account, note: relayed.bytes)
        // Signed by the wrong key as well, so the signature reason is also
        // violated and the order is what decides which comes back.
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: stranger)
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(Self.refusal(blob, expectation) == .subjectMismatch)
    }

    @Test("A proof minted for another session is refused at the note, disclosing nothing")
    func noteComesFourteenth() throws {
        // Goes red against comparing against any challenge this instance
        // issued, which makes every open session of every member
        // interchangeable.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let mine = try Self.challenge()
        let otherSession = try Self.challenge()
        #expect(mine != otherSession)
        let payment = ProofFixtures.proofPayment(for: account, note: otherSession.bytes)
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: stranger)
        let expectation = try Self.expectation(for: account, challenge: mine)
        #expect(Self.refusal(blob, expectation) == .noteMismatch)
    }

    @Test("A proof minted by another instance is refused, with the nonce identical")
    func theInstanceIdentityIsInsideTheSignedBytes() throws {
        // Goes red against leaving the server line out, after which one
        // community's proof is another community's proof and VERIFY-4 and
        // HOST-6 are words rather than properties. Every other field is the
        // same, the nonce included.
        let account = try ProofFixtures.account()
        let here = try VerificationChallenge(
            label: CoordinatorFixtures.label,
            instanceIdentity: CoordinatorFixtures.instance,
            subject: CoordinatorFixtures.subject,
            code: "K7QMZ4",
            nonce: String(repeating: "b", count: 32)
        )
        let elsewhere = try VerificationChallenge(
            label: CoordinatorFixtures.label,
            instanceIdentity: CoordinatorFixtures.otherInstance,
            subject: CoordinatorFixtures.subject,
            code: "K7QMZ4",
            nonce: String(repeating: "b", count: 32)
        )
        let payment = ProofFixtures.proofPayment(for: account, note: elsewhere.bytes)
        let blob = try ProofFixtures.blob(payment, signedBy: account)
        let expectation = try Self.expectation(for: account, challenge: here)
        #expect(Self.refusal(blob, expectation) == .noteMismatch)
    }

    @Test("A signature from a key that is not the claimed account is refused")
    func signatureComesFifteenth() throws {
        // This is the whole attack: trust the blob's own signer field and
        // anybody can claim any address they can type and take what it
        // earns.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let payment = ProofFixtures.proofPayment(for: account, note: challenge.bytes)
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: stranger)
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(
            Self.refusal(blob, expectation)
                == .signatureInvalid(authorizingKeyRetryAvailable: true)
        )
    }

    @Test("A blob naming its own signer does not have that signer used")
    func theBlobsOwnSignerIsNotTrusted() throws {
        // The envelope carries the stranger's address as its signer, and
        // the signature is the stranger's. Nothing here reads it.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let payment = ProofFixtures.proofPayment(for: account, note: challenge.bytes)
        let signed = try SignedTransaction.sign(payment, with: stranger)
        #expect(signed.authAddr == stranger.address)
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(
            Self.refusal(try signed.encode().base64EncodedString(), expectation)
                == .signatureInvalid(authorizingKeyRetryAvailable: true)
        )
    }

    @Test("A valid signature over the wrong preimage is refused")
    func thePreimageIsThePrefixAndTheSlice() throws {
        // Goes red against verifying over the bare transaction, over the
        // whole envelope, or over the challenge string alone. Each accepts
        // a signature the member produced for some other purpose.
        let account = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let payment = ProofFixtures.proofPayment(for: account, note: challenge.bytes)
        let transactionBytes = try payment.encode()
        let overTheBareTransaction = try account.sign(transactionBytes)
        let blob = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(overTheBareTransaction)),
            ("txn", transactionBytes)
        ]).base64EncodedString()
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(
            Self.refusal(blob, expectation)
                == .signatureInvalid(authorizingKeyRetryAvailable: true)
        )
    }

    @Test("An all zero signature against an all zero address is refused")
    func theIdentityEdgeIsNotAPass() throws {
        // This case is not theoretical and it is not about reading the
        // library's result wrongly. An all-zero key with an all-zero
        // signature satisfies the Ed25519 verification equation for every
        // message, and the libraries this builds against **return true**
        // for it. An address is a public key here, so without the
        // small-order check this passes and the handful of addresses whose
        // bytes are small-order points become claimable by anybody.
        let zeroAddress = try Address(bytes: Data(repeating: 0, count: 32))
        let challenge = try Self.challenge()
        let transaction = MessagePackBytes.envelope([
            ("note", MessagePackBytes.binary(challenge.bytes)),
            ("rcv", MessagePackBytes.binary(zeroAddress.bytes)),
            ("snd", MessagePackBytes.binary(zeroAddress.bytes)),
            ("type", MessagePackBytes.string("pay"))
        ])
        let blob = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(Self.deadSignature)),
            ("txn", transaction)
        ]).base64EncodedString()
        let expectation = try ProofExpectation(
            address: zeroAddress.description,
            challenge: challenge
        )
        #expect(
            Self.refusal(blob, expectation)
                == .signatureInvalid(authorizingKeyRetryAvailable: true)
        )
    }

    @Test("Every published small-order encoding is refused, in either spelling")
    func everySmallOrderEdgeIsRefused() throws {
        // The whole class rather than the one instance that happens to be
        // easy to write down. Each of these is an address as far as the
        // checksum is concerned, and each is a key that verifies whatever
        // it is handed.
        let encodings: [Data] = [
            Data(repeating: 0, count: 32),
            Data([0x01] + [UInt8](repeating: 0, count: 31)),
            Data([0xEC] + [UInt8](repeating: 0xFF, count: 30) + [0x7F]),
            Data([0xEC] + [UInt8](repeating: 0xFF, count: 30) + [0xFF]),
            Data([0xED] + [UInt8](repeating: 0xFF, count: 30) + [0x7F]),
            Data([0xEE] + [UInt8](repeating: 0xFF, count: 30) + [0x7F])
        ]
        let challenge = try Self.challenge()
        for encoding in encodings {
            let address = try Address(bytes: encoding)
            let transaction = MessagePackBytes.envelope([
                ("note", MessagePackBytes.binary(challenge.bytes)),
                ("rcv", MessagePackBytes.binary(address.bytes)),
                ("snd", MessagePackBytes.binary(address.bytes)),
                ("type", MessagePackBytes.string("pay"))
            ])
            let blob = MessagePackBytes.envelope([
                ("sig", MessagePackBytes.binary(Self.deadSignature)),
                ("txn", transaction)
            ]).base64EncodedString()
            let expectation = try ProofExpectation(
                address: address.description,
                challenge: challenge
            )
            #expect(
                Self.refusal(blob, expectation)
                    == .signatureInvalid(authorizingKeyRetryAvailable: true),
                "\(address.description) was not refused"
            )
        }
    }

    @Test("No key anybody generates is mistaken for one of those points")
    func theSmallOrderListIsNotOverBroad() throws {
        // The cost of being wrong in the direction of too many entries. Two
        // hundred generated accounts each prove their own wallet, so a
        // blacklist that caught anything a member could hold would be red
        // here rather than discovered by the member.
        for _ in 0..<200 {
            let account = try ProofFixtures.account()
            let challenge = try Self.challenge()
            let payment = ProofFixtures.proofPayment(for: account, note: challenge.bytes)
            let outcome = ProofChecker.check(
                blob: try ProofFixtures.blob(payment, signedBy: account),
                against: try Self.expectation(for: account, challenge: challenge),
                authorizingKeyRetryAvailable: true
            )
            #expect(outcome == .accepted(usedAuthorizingKey: false))
        }
    }

    @Test("A claimed address that fails its checksum is refused")
    func anAddressMustParseWhole() throws {
        // Goes red against taking whatever base32 decodes, which accepts a
        // typo as a different account.
        let account = try ProofFixtures.account()
        let canonical = account.address.description
        let typo = String(canonical.dropLast()) + (canonical.hasSuffix("A") ? "B" : "A")
        #expect(throws: VerifyError.addressNotCanonical(field: "address")) {
            _ = try ProofExpectation(address: typo, challenge: try Self.challenge())
        }
    }

    // MARK: - Forbidden fields, named by the encoder

    @Test("Every forbidden wire name is the name the dependency's own encoder emits")
    func theWireNamesCannotDrift() throws {
        // This is the check that would have caught `rekeyto`, which is the
        // name of the field on the dependency's transaction type and is not
        // the name it puts on the wire. Coded literally, the refusal would
        // have matched nothing, the tolerant reader would have skipped the
        // real key as unknown, and every rekeying proof would have been
        // accepted with a valid signature.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let note = Data("a note".utf8)

        let payment = ProofFixtures.proofPayment(
            for: account,
            note: note,
            lease: Data(repeating: 0x5A, count: 32),
            rekeyTo: stranger.address,
            closeRemainderTo: stranger.address
        )
        let paymentBytes = try payment.encode(groupID: Data(repeating: 0x6B, count: 32))
        for field in [
            ForbiddenTransactionField.rekey,
            .close,
            .lease,
            .group
        ] {
            #expect(
                paymentBytes.range(of: MessagePackBytes.string(field.wireName)) != nil,
                "\(field.wireName) is not what the payment encoder emits"
            )
        }

        let transfer = ProofFixtures.assetTransfer(
            for: account,
            note: note,
            closeRemainderTo: stranger.address
        )
        let transferBytes = try transfer.encode()
        #expect(
            transferBytes.range(
                of: MessagePackBytes.string(ForbiddenTransactionField.assetClose.wireName)
            ) != nil,
            "aclose is not what the asset transfer encoder emits"
        )
    }

    @Test(
        "A rekey, a close, a lease and a group are each refused with their own reason",
        arguments: [
            ForbiddenTransactionField.rekey,
            .close,
            .lease,
            .group
        ]
    )
    func eachForbiddenFieldHasItsOwnReason(field: ForbiddenTransactionField) throws {
        // Each fixture is built by the dependency's own encoder and carries
        // a **valid** signature, so the refusal cannot be the signature's.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let payment = ProofFixtures.proofPayment(
            for: account,
            note: challenge.bytes,
            lease: field == .lease ? Data(repeating: 0x5A, count: 32) : nil,
            rekeyTo: field == .rekey ? stranger.address : nil,
            closeRemainderTo: field == .close ? stranger.address : nil
        )
        let blob = try ProofFixtures.blob(
            payment,
            signedBy: account,
            groupID: field == .group ? Data(repeating: 0x6B, count: 32) : nil
        )
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(Self.refusal(blob, expectation) == .forbiddenField(field))
    }

    @Test("An asset close in a payment is refused with its own reason, under a valid signature")
    func anAssetCloseIsRefused() throws {
        // `aclose` is emitted only by an asset transaction, which this
        // module refuses one step earlier for not being a payment, so the
        // name is asserted against that encoder's output above and used
        // here in a payment the test signs itself. Both cases are needed:
        // the type refusal does not exercise this one.
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let challenge = try Self.challenge()
        let transaction = MessagePackBytes.envelope([
            (
                ForbiddenTransactionField.assetClose.wireName,
                MessagePackBytes.binary(stranger.address.bytes)
            ),
            ("note", MessagePackBytes.binary(challenge.bytes)),
            ("rcv", MessagePackBytes.binary(account.address.bytes)),
            ("snd", MessagePackBytes.binary(account.address.bytes)),
            ("type", MessagePackBytes.string("pay"))
        ])
        var preimage = ProofShape.signingPrefix
        preimage.append(transaction)
        let signature = try account.sign(preimage)
        let blob = MessagePackBytes.envelope([
            ("sig", MessagePackBytes.binary(signature)),
            ("txn", transaction)
        ]).base64EncodedString()
        let expectation = try Self.expectation(for: account, challenge: challenge)
        #expect(Self.refusal(blob, expectation) == .forbiddenField(.assetClose))
    }

    // MARK: - The authorising key

    @Test("A proof signed by a supplied authorising key is accepted, and the outcome records it")
    func theAuthorizingKeyPathWorks() async throws {
        // Goes red against refusing rekeyed accounts outright, which
        // silently excludes a real and blameless class of member, and
        // against accepting one without recording it, after which nothing
        // downstream can tell a proof by the account's own key from a proof
        // by a key somebody vouched for.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let authorizing = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: authorizing)

        let refused = try await coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        #expect(refused.refusalReason == .signatureInvalid(authorizingKeyRetryAvailable: true))

        let outcome = try await coordinator.submit(
            blob: blob,
            to: session.id,
            authorizingKey: authorizing.publicKey,
            now: CoordinatorFixtures.now
        )
        guard case .proved(let proved) = outcome else {
            Issue.record("the retry with the authorising key should have been accepted")
            return
        }
        #expect(proved.usedAuthorizingKey)
        #expect(proved.address == account.address.description)
        #expect(proved.subject == CoordinatorFixtures.subject)
    }

    @Test("The retry is reported as available at most once per session")
    func theRetryIsOfferedOnce() async throws {
        // Goes red against "at most once per session" living only in a
        // design sentence, which is a habit rather than a bound, and which
        // nothing can fail against. Before this, one command followed by a
        // loop of field correct proofs signed by a throwaway key would have
        // spent a chain read every time (RUN-11).
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: stranger)

        let first = try await coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        #expect(first.refusalReason == .signatureInvalid(authorizingKeyRetryAvailable: true))
        let second = try await coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        #expect(second.refusalReason == .signatureInvalid(authorizingKeyRetryAvailable: false))
    }

    @Test("An authorising key that is not a key at all is refused rather than tried")
    func theAuthorizingKeyIsChecked() throws {
        #expect(throws: VerifyError.authorizingKeyWrongLength(byteCount: 3)) {
            _ = try ProofExpectation(
                address: try ProofFixtures.account().address.description,
                challenge: try Self.challenge(),
                authorizingKey: Data([1, 2, 3])
            )
        }
    }

    @Test("A key of the wrong width reaches the caller, and costs the member no attempt")
    func aBadAuthorizingKeyIsNotDressedUpAsADeadLink() async throws {
        // Goes red against swallowing it into a refusal. The member is then
        // told their link is no longer usable, which is false, and the new
        // link they are told to fetch reproduces it on the first submission
        // while the attempt they just spent is gone. A `VerifyError` is the
        // caller's mistake and a `ProofRefusal` is the member's, and this is
        // the caller's.
        let store = InMemoryVerificationSessionStore()
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        await #expect(throws: VerifyError.authorizingKeyWrongLength(byteCount: 3)) {
            _ = try await coordinator.submit(
                blob: Self.rubbish,
                to: session.id,
                authorizingKey: Data([1, 2, 3]),
                now: CoordinatorFixtures.now
            )
        }
        let held = await store.session(id: session.id)
        #expect(held?.submissionCount == 0)
    }

    @Test("The two exhaustion bounds do not share one sentence, because one of them is false")
    func exhaustionSaysWhichBoundRanOut() {
        // A subject that has spent the window's allowance is told to run the
        // command again by a message written for a spent link, and is then
        // refused on a link nobody has tried. Goes red against one reason
        // with one sentence for two remedies that are opposites.
        let session = ProofRefusalReason.submissionsExhausted(.session)
        let subject = ProofRefusalReason.submissionsExhausted(.subject)
        #expect(session != subject)
        #expect(session.message != subject.message)
        #expect(session.message.contains("Run the command again"))
        #expect(!subject.message.contains("Run the command again for a new one"))
    }

    // MARK: - What a refusal carries

    @Test("A refusal carries a reason and a handle, and never the session id")
    func aRefusalCarriesNothingReplayable() async throws {
        // Goes red against putting the challenge in an error message, which
        // hands a replayable value to whatever reads errors, and against
        // returning the session id, which may never reach a log and which a
        // refusal is exactly what ends up in one.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let outcome = try await coordinator.submit(
            blob: Self.rubbish,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        guard case .refused(let refusal) = outcome else {
            Issue.record("a refusal was expected")
            return
        }
        #expect(refusal.reason == .blobUnreadable)
        #expect(refusal.handle.value != session.id.value)
        #expect(refusal.handle.value.count == RefusalHandle.characterCount)
        #expect(!refusal.message.contains(session.id.value))
        #expect(!refusal.message.contains(session.challenge.nonce))
        #expect(!refusal.message.contains(Self.rubbish))
    }

    @Test("The same session yields the same handle, and the handle yields nothing back")
    func theHandleIsStableAndUseless() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let first = try await coordinator.submit(blob: Self.rubbish, to: session.id, now: CoordinatorFixtures.now)
        let second = try await coordinator.submit(blob: Self.rubbish, to: session.id, now: CoordinatorFixtures.now)
        guard case .refused(let one) = first, case .refused(let two) = second else {
            Issue.record("two refusals were expected")
            return
        }
        #expect(one.handle == two.handle)
        #expect(!session.id.value.contains(one.handle.value))
    }

    @Test("Every reason reports the position the contract gives it")
    func theStepsAreTheContract() {
        #expect(ProofRefusalReason.sessionUnavailable.step == 1)
        #expect(ProofRefusalReason.submissionsExhausted(.session).step == 1)
        #expect(ProofRefusalReason.addressAlreadyConnected.step == 1)
        #expect(ProofRefusalReason.sessionExpired.step == 2)
        #expect(ProofRefusalReason.blobUnreadable.step == 3)
        #expect(ProofRefusalReason.transactionUnparsable.step == 4)
        #expect(ProofRefusalReason.missingField(.type).step == 5)
        #expect(ProofRefusalReason.notAPayment.step == 6)
        #expect(ProofRefusalReason.pinnedAddressMismatch.step == 7)
        #expect(ProofRefusalReason.senderMismatch.step == 8)
        #expect(ProofRefusalReason.receiverMismatch.step == 9)
        #expect(ProofRefusalReason.amountNotZero.step == 10)
        #expect(ProofRefusalReason.feeAboveBound.step == 11)
        #expect(ProofRefusalReason.forbiddenField(.rekey).step == 12)
        #expect(ProofRefusalReason.subjectMismatch.step == 13)
        #expect(ProofRefusalReason.noteMismatch.step == 14)
        #expect(ProofRefusalReason.signatureInvalid(authorizingKeyRetryAvailable: false).step == 15)
    }

    @Test("Every reason has a sentence a member can act on")
    func everyReasonSaysSomethingUseful() {
        let reasons: [ProofRefusalReason] = [
            .sessionUnavailable, .submissionsExhausted(.session), .submissionsExhausted(.subject),
            .addressAlreadyConnected, .sessionExpired,
            .blobUnreadable, .transactionUnparsable, .missingField(.sender), .notAPayment,
            .pinnedAddressMismatch, .senderMismatch, .receiverMismatch, .amountNotZero,
            .feeAboveBound, .forbiddenField(.rekey), .subjectMismatch, .noteMismatch,
            .signatureInvalid(authorizingKeyRetryAvailable: true)
        ]
        for reason in reasons {
            #expect(!reason.message.isEmpty)
        }
        // The one a member most needs to be able to act on names the thing
        // to change rather than describing the failure.
        #expect(ProofRefusalReason.senderMismatch.message.contains("Select that account"))
    }
}
