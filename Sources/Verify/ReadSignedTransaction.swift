import Foundation

/// What came out of a submitted blob.
///
/// The transaction bytes are a **slice of the input**, carried alongside the
/// range they were taken from so a caller can prove it. Nothing here is
/// rebuilt: a re-encoding one byte different from what the wallet signed
/// fails a perfectly good proof and looks like a problem with the
/// cryptography, which is the mistake nobody finds quickly.
///
/// There is deliberately no field for a signer named in the envelope. An
/// envelope may carry one and this reader skips it, because a value read out
/// of the blob that could become the key a signature is checked against is the
/// whole attack: anybody could then claim any address they can type.
public struct ReadSignedTransaction: Sendable, Equatable {

    // MARK: - Properties

    /// The sixty four byte Ed25519 signature.
    public let signature: Data

    /// The transaction bytes, exactly as they arrived.
    public let transactionBytes: Data

    /// Where in the decoded blob those bytes came from.
    public let transactionByteRange: Range<Int>

    /// What the transaction turned out to say.
    public let fields: SignedTransactionFields

    // MARK: - Initializers

    /// - Parameters:
    ///   - signature: The sixty four byte signature.
    ///   - transactionBytes: The transaction bytes, sliced from the input.
    ///   - transactionByteRange: Where in the decoded blob they came from.
    ///   - fields: What the transaction says.
    public init(
        signature: Data,
        transactionBytes: Data,
        transactionByteRange: Range<Int>,
        fields: SignedTransactionFields
    ) {
        self.signature = signature
        self.transactionBytes = transactionBytes
        self.transactionByteRange = transactionByteRange
        self.fields = fields
    }
}
