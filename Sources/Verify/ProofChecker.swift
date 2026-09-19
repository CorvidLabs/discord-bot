import Foundation
import Crypto

/// What came of checking a proof against an expectation.
public enum ProofCheckOutcome: Sendable, Equatable {

    /// The signature checked out over exactly the right bytes.
    ///
    /// - Parameter usedAuthorizingKey: Whether it checked out against the key
    ///   the caller vouched for rather than against the account's own.
    case accepted(usedAuthorizingKey: Bool)

    /// It did not, and this is the first reason in the order that held.
    case refused(ProofRefusalReason)
}

/// The ordered check: thirteen of the fifteen reasons, in order.
///
/// The first two belong to a session and are ``VerificationCoordinator``'s.
/// Everything from the blob onwards is here, and it is deliberately separate
/// from sessions: a future route that delivers a proof some other way is a
/// new caller of this, not a new checker.
///
/// **A later reason is never returned while an earlier one holds**, and that
/// is a property rather than an accident of the order the code happens to be
/// written in. Two things come out of it. A member whose wallet had the wrong
/// account selected is told the sender did not match, which is something they
/// can fix, instead of being told their signature was bad, which is not. And
/// the one refusal a caller may act on, the signature, is reachable only when
/// nothing else was wrong, so a chain read for an authorising address is
/// spent on a member who might actually be rekeyed.
public enum ProofChecker: Sendable {

    // MARK: - Public Methods

    /// Checks one submitted blob against one expectation.
    ///
    /// - Parameters:
    ///   - blob: What the page posted, base64.
    ///   - expectation: What the proof has to match.
    ///   - authorizingKeyRetryAvailable: Whether the caller may still read an
    ///     authorising address and ask again. Reported on the signature
    ///     refusal and nowhere else.
    /// - Returns: Accepted, or the first reason in the order that held.
    public static func check(
        blob: String,
        against expectation: ProofExpectation,
        authorizingKeyRetryAvailable: Bool
    ) -> ProofCheckOutcome {
        // 3. The blob decodes.
        let decoded: Data
        do {
            decoded = try SignedTransactionReader.decode(blob)
        } catch {
            return .refused(.blobUnreadable)
        }

        // 4. The bytes are a signed transaction, canonically spelled.
        let read: ReadSignedTransaction
        do {
            read = try SignedTransactionReader.read(decoded)
        } catch {
            return .refused(.transactionUnparsable)
        }

        // 5. It carries what a proof has to carry. The amount and the fee are
        //    deliberately not in this list: a canonical encoder omits both
        //    when they are zero, so requiring either refuses every correctly
        //    formed proof.
        let fields = read.fields
        guard let type = fields.type else { return .refused(.missingField(.type)) }
        guard let sender = fields.sender else { return .refused(.missingField(.sender)) }
        guard let receiver = fields.receiver else { return .refused(.missingField(.receiver)) }
        guard let note = fields.note else { return .refused(.missingField(.note)) }

        // 6. It is a payment.
        guard type == ProofShape.transactionType else { return .refused(.notAPayment) }

        // 7. On a pinned session, it came from the account the member named.
        //    Before the sender check, because "this is not the account you
        //    named" is the sentence the member can act on whenever both hold.
        if let pinned = expectation.pinnedAddressBytes, sender != pinned {
            return .refused(.pinnedAddressMismatch)
        }

        // 8. It came from the account that was connected.
        guard sender == expectation.addressBytes else { return .refused(.senderMismatch) }

        // 9. It pays that same account and nobody else.
        guard receiver == expectation.addressBytes else { return .refused(.receiverMismatch) }

        // 10. It moves nothing. An absent key is zero.
        guard fields.amountOrZero == 0 else { return .refused(.amountNotZero) }

        // 11. Its fee is inside the bound. An absent key is zero here too,
        //     never unknown and never unbounded.
        guard fields.feeOrZero <= ProofShape.maximumFeeMicroAlgos else {
            return .refused(.feeAboveBound)
        }

        // 12. It carries nothing that could empty or reassign the account.
        if let forbidden = fields.forbiddenFields.first {
            return .refused(.forbiddenField(forbidden))
        }

        // 13. The prompt that was signed names this session's own member.
        //     Read out of the submitted note, not rebuilt from the stored
        //     challenge, and before the note rather than after it.
        if let submittedSubject = VerificationChallenge.subject(inNote: note),
            submittedSubject != expectation.challenge.subject {
            return .refused(.subjectMismatch)
        }

        // 14. What was signed is this session's challenge, byte for byte.
        guard note == expectation.challenge.bytes else { return .refused(.noteMismatch) }

        // 15. The signature is over the prefix and the bytes that arrived,
        //     sliced rather than rebuilt.
        var preimage = ProofShape.signingPrefix
        preimage.append(read.transactionBytes)
        if isValid(signature: read.signature, over: preimage, by: expectation.addressBytes) {
            return .accepted(usedAuthorizingKey: false)
        }
        if let authorizingKey = expectation.authorizingKey,
            isValid(signature: read.signature, over: preimage, by: authorizingKey) {
            return .accepted(usedAuthorizingKey: true)
        }
        return .refused(.signatureInvalid(authorizingKeyRetryAvailable: authorizingKeyRetryAvailable))
    }

    // MARK: - Private Methods

    /// The one place a public key is built and a signature is checked.
    ///
    /// One function on purpose, so the keys a signature is ever checked
    /// against can be counted: the claimed address, and the key the caller
    /// vouched for. Nothing read out of the submitted blob reaches here,
    /// because there is nowhere in ``ReadSignedTransaction`` for such a value
    /// to have been put.
    private static func isValid(signature: Data, over preimage: Data, by keyBytes: Data) -> Bool {
        guard !isSmallOrder(keyBytes) else { return false }
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) else {
            return false
        }
        return key.isValidSignature(signature, for: preimage)
    }

    /// Whether a key is one of the points that verify anything at all.
    ///
    /// **This is not tidiness and it is not theoretical.** An all-zero key
    /// with an all-zero signature satisfies the Ed25519 verification
    /// equation for **every** message, and the cryptography libraries this
    /// builds against return true for it rather than refusing. An address is
    /// a public key here, so without this check the handful of addresses
    /// whose bytes are small-order points can be claimed by anybody, and
    /// whatever somebody has sent to one of them decides a role for whoever
    /// claimed it first.
    ///
    /// The list is the published set of small-order encodings, compared with
    /// the sign bit of the last byte masked off so that the non-canonical
    /// spellings of the same points are caught with it. Being wrong in the
    /// direction of too many entries costs nothing: no key anybody generates
    /// will ever land on one, which the suite checks over two thousand of
    /// them. Being wrong in the direction of too few leaves the hole open,
    /// which is why the list is the whole published one rather than the one
    /// entry that happens to be testable.
    private static func isSmallOrder(_ keyBytes: Data) -> Bool {
        guard keyBytes.count == smallOrderPointByteCount else { return true }
        let candidate = Array(keyBytes)
        for point in smallOrderPoints {
            var difference: UInt8 = 0
            for index in 0..<(smallOrderPointByteCount - 1) {
                difference |= candidate[index] ^ point[index]
            }
            difference |= (candidate[smallOrderPointByteCount - 1] & 0x7F) ^ point[smallOrderPointByteCount - 1]
            if difference == 0 { return true }
        }
        return false
    }

    /// Bytes in an encoded point, which is also the width of an address.
    private static let smallOrderPointByteCount: Int = 32

    /// The small-order encodings, with the sign bit of the last byte already
    /// cleared so a masked comparison covers both spellings of each.
    private static let smallOrderPoints: [[UInt8]] = [
        // The point at infinity, and the all-zero encoding beside it.
        [UInt8](repeating: 0x00, count: 32),
        [0x01] + [UInt8](repeating: 0x00, count: 31),
        // The two points of order eight.
        [
            0x26, 0xE8, 0x95, 0x8F, 0xC2, 0xB2, 0x27, 0xB0,
            0x45, 0xC3, 0xF4, 0x89, 0xF2, 0xEF, 0x98, 0xF0,
            0xD5, 0xDF, 0xAC, 0x05, 0xD3, 0xC6, 0x33, 0x39,
            0xB1, 0x38, 0x02, 0x88, 0x6D, 0x53, 0xFC, 0x05
        ],
        [
            0xC7, 0x17, 0x6A, 0x70, 0x3D, 0x4D, 0xD8, 0x4F,
            0xBA, 0x3C, 0x0B, 0x76, 0x0D, 0x10, 0x67, 0x0F,
            0x2A, 0x20, 0x53, 0xFA, 0x2C, 0x39, 0xCC, 0xC6,
            0x4E, 0xC7, 0xFD, 0x77, 0x92, 0xAC, 0x03, 0x7A
        ],
        // The field prime and the two values either side of it, which are
        // non-canonical encodings of the points above.
        [0xEC] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
        [0xED] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
        [0xEE] + [UInt8](repeating: 0xFF, count: 30) + [0x7F]
    ]
}
