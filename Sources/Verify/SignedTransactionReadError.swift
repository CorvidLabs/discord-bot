import Foundation

/// Why a submitted blob was not something this module would read.
///
/// Two groups, and which group a case is in decides which refusal a member
/// reads. ``SignedTransactionReader/decode(_:)`` raises the first three: the
/// bytes never arrived in a form that is bytes at all. Everything else comes
/// from ``SignedTransactionReader/read(_:)``: the bytes arrived and are not a
/// signed transaction. Conflating the two loses the difference between a
/// wallet that sent the wrong encoding and one that sent the wrong shape, and
/// those are debugged differently.
public enum SignedTransactionReadError: Error, Sendable, Equatable, CustomStringConvertible {

    /// Longer than the ceiling, refused before any parsing began.
    case blobOverCeiling(byteCount: Int, ceiling: Int)

    /// Nothing but whitespace arrived.
    case blobEmpty

    /// Not base64 in either alphabet.
    case blobNotBase64

    /// The bytes ran out in the middle of a value.
    case truncated

    /// A map was expected and the header said something else.
    case notAMap

    /// A string was expected and the header said something else. Keys are
    /// strings at every depth: a map keyed by anything else is not something
    /// any Algorand encoder produces, and comparing such keys for duplicates
    /// is not a thing this reader is prepared to do.
    case notAString

    /// An unsigned integer was expected and the header said something else.
    case notAnUnsignedInteger

    /// Binary was expected and the header said something else.
    case notBinary

    /// A MessagePack type this reader does not carry.
    case unsupportedValue(header: UInt8)

    /// A length or a count the input declared but did not carry.
    ///
    /// Refused without allocating to match it, which is how a short hostile
    /// blob otherwise becomes a large allocation.
    case declaredLengthExceedsInput

    /// A value nested past the depth limit.
    case nestedTooDeep

    /// The same key twice in one map, at some depth.
    ///
    /// Tolerance about how a blob is spelled is not tolerance of a blob that
    /// says two things. The page supplies the unsigned bytes, so it chooses
    /// the encoding: `amt` twice, zero first and a large value second, is one
    /// document a wallet can display one way and a reader take the other way,
    /// under one signature that stays valid over whichever reading is carried
    /// off, because this reader slices rather than re-encoding.
    case duplicateKey(String)

    /// A byte after the end of the envelope, which is a second document
    /// nobody looked at.
    case trailingBytes

    /// A signature field that is not exactly sixty four bytes, refused before
    /// anything is handed to a cryptography library.
    case signatureWrongLength(byteCount: Int)

    /// No signature in the envelope.
    case signatureMissing

    /// No transaction in the envelope.
    case transactionMissing

    // MARK: - Public Methods

    public var description: String {
        switch self {
        case .blobOverCeiling(let byteCount, let ceiling):
            return "the submission is \(byteCount) bytes and the ceiling is \(ceiling)"
        case .blobEmpty: return "the submission was empty"
        case .blobNotBase64: return "the submission is not base64"
        case .truncated: return "the bytes ran out part way through a value"
        case .notAMap: return "a map was expected"
        case .notAString: return "a string was expected"
        case .notAnUnsignedInteger: return "an unsigned integer was expected"
        case .notBinary: return "binary was expected"
        case .unsupportedValue(let header):
            return "a MessagePack type this reader does not carry: 0x\(String(header, radix: 16))"
        case .declaredLengthExceedsInput:
            return "a declared length is longer than the bytes that arrived"
        case .nestedTooDeep: return "a value is nested past the depth limit"
        case .duplicateKey(let key): return "the key \(key) appears twice in one map"
        case .trailingBytes: return "there are bytes after the end of the envelope"
        case .signatureWrongLength(let byteCount):
            return "a signature is 64 bytes and this one is \(byteCount)"
        case .signatureMissing: return "there is no signature in the envelope"
        case .transactionMissing: return "there is no transaction in the envelope"
        }
    }
}
