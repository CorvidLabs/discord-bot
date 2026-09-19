import Foundation
import Algorand
import Verify

/// A real signer, with no network, no wallet and no key anybody had to be
/// trusted with (BUILD-2, BUILD-2.a, BUILD-2.b).
///
/// Every key here is generated inside the test from the platform's own
/// randomness, every signature is produced by the dependency's own signing
/// path, and every blob is produced by its own encoder. The production path
/// then runs unchanged, which is the whole reason this module needs no test
/// flag: a test that skips the code under test is not a test of it.
///
/// **A fixture that names a wire key names it the way the encoder does.**
/// None of `rekey`, `close`, `aclose`, `lx` or `grp` is written into bytes by
/// hand anywhere in this suite. A hand built fixture carries whatever name
/// the code carries and goes green over a hole; one built by the encoder
/// cannot, and a rename in the dependency turns this suite red rather than
/// turning a check off.
///
/// Three limits, stated because they bound what this evidence is worth. It
/// emits only the canonical shape, so every other accepted spelling is made
/// by re-encoding the blob this produced. It proves the checker and not any
/// wallet. And it proves nothing about a page, because there is no page.
enum ProofFixtures {

    // MARK: - Properties

    /// A genesis that belongs to nobody. Made up here so that no network's
    /// own identifier and no real account is carried into this repository.
    static let genesisIdentifier: String = "verify-suite-v1"

    /// Thirty two bytes that are not all zero, so the canonical encoder keeps
    /// the field rather than omitting it.
    static let genesisHash: Data = Data(repeating: 0x2A, count: 32)

    /// The round window every fixture is built in. Fixed, so nothing in this
    /// suite depends on when it ran.
    static let firstValid: UInt64 = 1_000
    static let lastValid: UInt64 = 2_000

    // MARK: - Methods

    /// A fresh account from the platform's randomness.
    static func account() throws -> Account {
        try Account()
    }

    /// The shape a page is asked to build: a zero amount self payment
    /// carrying the challenge in its note.
    static func proofPayment(
        for account: Account,
        note: Data,
        amount: UInt64 = 0,
        fee: UInt64 = 0,
        receiver: Address? = nil,
        lease: Data? = nil,
        rekeyTo: Address? = nil,
        closeRemainderTo: Address? = nil
    ) -> PaymentTransaction {
        PaymentTransaction(
            sender: account.address,
            receiver: receiver ?? account.address,
            amount: MicroAlgos(amount),
            fee: MicroAlgos(fee),
            firstValid: firstValid,
            lastValid: lastValid,
            genesisID: genesisIdentifier,
            genesisHash: genesisHash,
            note: note,
            lease: lease,
            rekeyTo: rekeyTo,
            closeRemainderTo: closeRemainderTo
        )
    }

    /// An asset transfer, which is the only transaction whose encoder emits
    /// `aclose`, and which a proof is refused for being at all.
    static func assetTransfer(
        for account: Account,
        note: Data,
        closeRemainderTo: Address? = nil
    ) -> AssetTransferTransaction {
        AssetTransferTransaction(
            sender: account.address,
            receiver: account.address,
            assetID: 7,
            amount: 0,
            closeRemainderTo: closeRemainderTo,
            fee: MicroAlgos(0),
            firstValid: firstValid,
            lastValid: lastValid,
            genesisID: genesisIdentifier,
            genesisHash: genesisHash,
            note: note
        )
    }

    /// A signed envelope, base64, exactly as a page would post it.
    static func blob(
        _ transaction: any Transaction,
        signedBy account: Account,
        groupID: Data? = nil
    ) throws -> String {
        let signed = try SignedTransaction.sign(transaction, with: account, groupID: groupID)
        return try signed.encode().base64EncodedString()
    }

    /// The decoded envelope bytes, for a suite that wants to compare a slice
    /// against the input it came from.
    static func envelopeBytes(
        _ transaction: any Transaction,
        signedBy account: Account,
        groupID: Data? = nil
    ) throws -> Data {
        try SignedTransaction.sign(transaction, with: account, groupID: groupID).encode()
    }

    /// A signature over the right preimage by the wrong key, carried in an
    /// envelope that does not name its signer.
    ///
    /// The plain envelope initialiser is used on purpose: with the signing
    /// path the envelope would carry `sgnr`, and this fixture is for the case
    /// where nothing in the blob says who signed it.
    static func blobSignedByStranger(
        _ transaction: any Transaction,
        signedBy stranger: Account
    ) throws -> String {
        let signature = try stranger.sign(try transaction.bytesToSign())
        let signed = SignedTransaction(transaction: transaction, signature: signature)
        return try signed.encode().base64EncodedString()
    }

    /// What a signature is checked over: the prefix, then the transaction.
    static func preimage(_ transaction: any Transaction, groupID: Data? = nil) throws -> Data {
        try transaction.bytesToSign(groupID: groupID)
    }
}
