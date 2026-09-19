import Foundation

/// Turns what a page posted into a signature and the exact bytes it covers.
///
/// This is the one piece of hand written binary parsing in the module, it will
/// one day be reachable from the internet, and it is therefore written to two
/// rules that pull in opposite directions.
///
/// **Tolerant about how a blob is spelled.** Standard and URL-safe base64,
/// padded or not, with whitespace around it; a bare signature and transaction
/// map, that map wrapped in a one element array, and a map carrying an extra
/// signer key which is skipped. Those shapes are not hypothetical: they are
/// what the implementation this was ported from grew branches for, because a
/// wallet on a phone sent them.
///
/// **Strict about a blob that says two things.** A duplicate key at any
/// depth, a byte after the end of the envelope, a length the input declares
/// but does not carry, a value nested past a limit, and anything at all over
/// a ceiling applied before parsing begins. None of those is tidiness. The
/// page supplies the unsigned bytes, so it chooses the encoding, and a
/// checker that blesses a document meaning two things is not checking one.
///
/// **The order of the keys is not one of them.** A map with unique keys says
/// exactly one thing whatever order they arrive in, so requiring them to
/// ascend buys nothing the duplicate rule has not already bought, and it
/// costs the shape the reader this was ported from was patched to accept: a
/// live flow on a phone failed on an envelope carrying an extra signer key,
/// and the fixture written against that incident emits `sig`, `txn`, `sgnr`
/// in that order. A signer key is present only on a rekeyed account, and a
/// refusal here is a refusal at the fourth step, where the authorising key
/// retry is never reached. Refusing that shape leaves exactly the member the
/// whole seam exists for with no path at all.
///
/// The reader the port came from was last-key-wins with no duplicate
/// detection and no ceiling. Both are changes made here on purpose.
public enum SignedTransactionReader: Sendable {

    // MARK: - Properties

    /// The largest submission this reader will look at, in bytes.
    ///
    /// Applied to what arrived before anything is parsed, and again to what
    /// it decoded to. A signed zero amount self payment is a few hundred
    /// bytes; this is generous by an order of magnitude and still small
    /// enough that nobody posting to the route chooses how much work the
    /// process does.
    public static let blobCeilingByteCount: Int = 8192

    /// How deeply a value may nest before it is refused.
    ///
    /// A signed transaction is two levels. Anything approaching this is
    /// somebody trying to spend the stack rather than a wallet.
    public static let nestingDepthLimit: Int = 8

    /// Bytes in an Ed25519 signature.
    public static let signatureByteCount: Int = 64

    // MARK: - Public Methods

    /// Base64 in either alphabet, padded or not, with whitespace around it.
    ///
    /// Padded or not is the only latitude given: padding is the last one or
    /// two characters of the last group of four or it is not padding, and a
    /// leftover group of one character is six bits and never a whole byte.
    /// Neither is base64, and neither is left to Foundation to judge, which
    /// is the only way the same submission reports the same refusal on every
    /// platform this builds for.
    ///
    /// - Parameter blob: What the page posted.
    /// - Returns: The bytes it stood for.
    /// - Throws: ``SignedTransactionReadError`` naming which of the three
    ///   ways it was not base64.
    public static func decode(_ blob: String) throws -> Data {
        let arrived = blob.utf8.count
        guard arrived <= blobCeilingByteCount else {
            throw SignedTransactionReadError.blobOverCeiling(
                byteCount: arrived,
                ceiling: blobCeilingByteCount
            )
        }
        let compact = blob.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { throw SignedTransactionReadError.blobEmpty }

        // An underscore is never standard base64, so it settles the alphabet
        // on its own. A hyphen does not: short hyphenated words are ordinary
        // text and must stay invalid rather than being translated into
        // something that decodes and then fails much later with a useless
        // reason.
        //
        // Asked of the scalars rather than of the string, because
        // `String.contains(_: String)` is not the same call on both
        // platforms: on Darwin it resolves to the standard library's search
        // over Characters and on Linux to Foundation's substring search.
        // Both answer the same for one ASCII character, and neither is worth
        // depending on in the one function that decides which refusal a
        // member reads.
        let scalars = compact.unicodeScalars
        let urlSafe = scalars.contains("_") || (scalars.contains("-") && scalars.count >= 32)
        var normalized = compact
        if urlSafe {
            normalized = compact
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        }
        guard normalized.unicodeScalars.allSatisfy({ base64Alphabet.contains($0) }) else {
            throw SignedTransactionReadError.blobNotBase64
        }
        let wholeGroups = try padded(normalized)
        guard let decoded = Data(base64Encoded: wholeGroups) else {
            throw SignedTransactionReadError.blobNotBase64
        }
        guard decoded.count <= blobCeilingByteCount else {
            throw SignedTransactionReadError.blobOverCeiling(
                byteCount: decoded.count,
                ceiling: blobCeilingByteCount
            )
        }
        return decoded
    }

    /// The signature, the transaction bytes as a slice, and what they say.
    ///
    /// - Parameter decoded: The bytes ``decode(_:)`` produced.
    /// - Returns: What the envelope held.
    /// - Throws: ``SignedTransactionReadError`` naming what was wrong.
    public static func read(_ decoded: Data) throws -> ReadSignedTransaction {
        guard decoded.count <= blobCeilingByteCount else {
            throw SignedTransactionReadError.blobOverCeiling(
                byteCount: decoded.count,
                ceiling: blobCeilingByteCount
            )
        }
        var cursor = Cursor(bytes: [UInt8](decoded))
        try cursor.unwrapSingleElementArray()
        let envelope = try cursor.readEnvelope()
        guard cursor.index == cursor.bytes.count else {
            throw SignedTransactionReadError.trailingBytes
        }
        return envelope
    }

    /// Base64 in one call: ``decode(_:)`` and then ``read(_:)``.
    ///
    /// - Parameter blob: What the page posted.
    /// - Returns: What the envelope held.
    /// - Throws: ``SignedTransactionReadError``.
    public static func read(blob: String) throws -> ReadSignedTransaction {
        try read(try decode(blob))
    }

    // MARK: - Private Methods

    /// Every character either base64 alphabet uses, after normalisation.
    private static let base64Alphabet: Set<Unicode.Scalar> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".unicodeScalars
    )

    /// Pads a blob to a whole number of groups, and refuses one that is not
    /// a whole number of groups to begin with.
    ///
    /// Two rules. Padding is the last one or two characters of the last
    /// group and nowhere else, and a group of one character is six bits,
    /// which is never a whole byte however it is padded.
    ///
    /// Both are settled here because `Data(base64Encoded:)` is a different
    /// implementation on each platform and the two disagree in opposite
    /// directions: Darwin takes `AA=A` and `====` where Linux refuses them,
    /// and Linux takes `A===` and `AAAAA===` where Darwin refuses them.
    /// Leaving the shape to Foundation therefore sent a malformed blob to
    /// the parser on one platform and refused it at the decode on the
    /// other, so the same submission reported the fourth refusal or the
    /// third depending on which machine answered. Once the shape is settled
    /// the two agree byte for byte, which is why the decode itself is still
    /// Foundation's.
    ///
    /// - Parameter normalized: Compacted characters in the standard alphabet.
    /// - Returns: The same characters, padded to a multiple of four.
    /// - Throws: ``SignedTransactionReadError/blobNotBase64`` when the
    ///   characters are not a base64 document at all.
    private static func padded(_ normalized: String) throws -> String {
        let paddingCount = normalized.reversed().prefix { $0 == "=" }.count
        let body = normalized.dropLast(paddingCount)
        guard !body.isEmpty, !body.unicodeScalars.contains("="), paddingCount <= 2 else {
            throw SignedTransactionReadError.blobNotBase64
        }
        let remainder = body.count % 4
        guard remainder != 1 else { throw SignedTransactionReadError.blobNotBase64 }
        guard paddingCount == 0 || paddingCount == 4 - remainder else {
            throw SignedTransactionReadError.blobNotBase64
        }
        guard remainder != 0 else { return String(body) }
        return body + String(repeating: "=", count: 4 - remainder)
    }
}

// MARK: - Cursor

/// A position in the bytes that arrived, and every read that moves it.
///
/// A struct rather than a set of free functions taking an `inout Int` so that
/// the bytes and the position cannot get separated, which is how a skip that
/// guessed a length shifts every field after it and produces a wrong slice
/// rather than an error.
private struct Cursor {

    // MARK: - Properties

    let bytes: [UInt8]
    var index: Int = 0

    private var remaining: Int { bytes.count - index }

    // MARK: - Envelope

    /// Unwraps a signed transaction handed over inside a one element array.
    ///
    /// One level, which is the shape the port's own reader was written for.
    /// The reader it came from unwrapped up to two, defensively rather than
    /// because two had been seen; one is what the contract names and what the
    /// evidence supports.
    mutating func unwrapSingleElementArray() throws {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        let count: Int
        let headerSize: Int
        if header >= 0x90 && header <= 0x9F {
            count = Int(header & 0x0F)
            headerSize = 1
        } else if header == 0xDC {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            count = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            headerSize = 3
        } else if header == 0xDD {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            count = try readBigEndian32(at: index + 1)
            headerSize = 5
        } else {
            return
        }
        guard count == 1 else { throw SignedTransactionReadError.notAMap }
        index += headerSize
    }

    /// Reads the signed transaction envelope: a signature, a transaction, and
    /// whatever else the wallet chose to carry, which is skipped.
    mutating func readEnvelope() throws -> ReadSignedTransaction {
        let count = try readMapCount()
        var signature: Data?
        var transactionRange: Range<Int>?
        var fields: SignedTransactionFields?
        var keys = KeysSeen()

        for _ in 0..<count {
            let key = try readString()
            try keys.take(key)
            switch key {
            case "sig":
                let value = try readBinary()
                guard value.count == SignedTransactionReader.signatureByteCount else {
                    throw SignedTransactionReadError.signatureWrongLength(byteCount: value.count)
                }
                signature = value
            case "txn":
                let start = index
                fields = try readTransaction(depth: 2)
                transactionRange = start..<index
            default:
                // `sgnr`, `lsig`, `msig`, `pqsig` and anything a wallet adds
                // later. Skipped and never surfaced: there is nowhere in
                // `ReadSignedTransaction` to put it, which is the point.
                try skipValue(depth: 2)
            }
        }

        guard let signature else { throw SignedTransactionReadError.signatureMissing }
        guard let transactionRange, let fields else {
            throw SignedTransactionReadError.transactionMissing
        }
        return ReadSignedTransaction(
            signature: signature,
            transactionBytes: Data(bytes[transactionRange]),
            transactionByteRange: transactionRange,
            fields: fields
        )
    }

    /// Reads the transaction map, keeping the fields that decide a proof and
    /// noting the ones whose presence refuses it.
    mutating func readTransaction(depth: Int) throws -> SignedTransactionFields {
        guard depth <= SignedTransactionReader.nestingDepthLimit else {
            throw SignedTransactionReadError.nestedTooDeep
        }
        let count = try readMapCount()
        var type: String?
        var sender: Data?
        var receiver: Data?
        var amount: UInt64?
        var fee: UInt64?
        var note: Data?
        var forbidden: Set<ForbiddenTransactionField> = []
        var keys = KeysSeen()

        for _ in 0..<count {
            let key = try readString()
            try keys.take(key)
            switch key {
            case "type": type = try readString()
            case "snd": sender = try readBinary()
            case "rcv": receiver = try readBinary()
            case "amt": amount = try readUInt()
            case "fee": fee = try readUInt()
            case "note": note = try readBinary()
            default:
                if let field = ForbiddenTransactionField(wireName: key) {
                    forbidden.insert(field)
                }
                try skipValue(depth: depth + 1)
            }
        }

        return SignedTransactionFields(
            type: type,
            sender: sender,
            receiver: receiver,
            amount: amount,
            fee: fee,
            note: note,
            forbiddenFields: ForbiddenTransactionField.allCases.filter { forbidden.contains($0) }
        )
    }

    // MARK: - Readers

    mutating func readMapCount() throws -> Int {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        let count: Int
        if header >= 0x80 && header <= 0x8F {
            count = Int(header & 0x0F)
            index += 1
        } else if header == 0xDE {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            count = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
        } else if header == 0xDF {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            count = try readBigEndian32(at: index + 1)
            index += 5
        } else {
            throw SignedTransactionReadError.notAMap
        }
        // A pair is at least two bytes, so a count larger than half what is
        // left is a number the input declared and did not carry. Checked
        // before the loop, so the work is bounded by the bytes rather than by
        // the header.
        guard count <= remaining / 2 else {
            throw SignedTransactionReadError.declaredLengthExceedsInput
        }
        return count
    }

    mutating func readArrayCount() throws -> Int {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        let count: Int
        if header >= 0x90 && header <= 0x9F {
            count = Int(header & 0x0F)
            index += 1
        } else if header == 0xDC {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            count = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
        } else if header == 0xDD {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            count = try readBigEndian32(at: index + 1)
            index += 5
        } else {
            throw SignedTransactionReadError.unsupportedValue(header: header)
        }
        guard count <= remaining else {
            throw SignedTransactionReadError.declaredLengthExceedsInput
        }
        return count
    }

    mutating func readString() throws -> String {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        let length: Int
        if header >= 0xA0 && header <= 0xBF {
            length = Int(header & 0x1F)
            index += 1
        } else if header == 0xD9 {
            guard remaining >= 2 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1])
            index += 2
        } else if header == 0xDA {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
        } else if header == 0xDB {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            length = try readBigEndian32(at: index + 1)
            index += 5
        } else {
            throw SignedTransactionReadError.notAString
        }
        let slice = try take(length)
        guard let value = String(bytes: slice, encoding: .utf8) else {
            throw SignedTransactionReadError.notAString
        }
        return value
    }

    mutating func readBinary() throws -> Data {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        let length: Int
        if header == 0xC4 {
            guard remaining >= 2 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1])
            index += 2
        } else if header == 0xC5 {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
        } else if header == 0xC6 {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            length = try readBigEndian32(at: index + 1)
            index += 5
        } else if header >= 0xA0 && header <= 0xBF {
            // A wallet that sends these as a string rather than as binary is
            // still telling the truth about the bytes, and the signature is
            // over what arrived either way.
            length = Int(header & 0x1F)
            index += 1
        } else if header == 0xD9 {
            guard remaining >= 2 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1])
            index += 2
        } else if header == 0xDA {
            guard remaining >= 3 else { throw SignedTransactionReadError.truncated }
            length = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
        } else if header == 0xDB {
            guard remaining >= 5 else { throw SignedTransactionReadError.truncated }
            length = try readBigEndian32(at: index + 1)
            index += 5
        } else {
            throw SignedTransactionReadError.notBinary
        }
        return Data(try take(length))
    }

    mutating func readUInt() throws -> UInt64 {
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]
        if header <= 0x7F {
            index += 1
            return UInt64(header)
        }
        let width: Int
        switch header {
        case 0xCC: width = 1
        case 0xCD: width = 2
        case 0xCE: width = 4
        case 0xCF: width = 8
        default: throw SignedTransactionReadError.notAnUnsignedInteger
        }
        guard remaining >= 1 + width else { throw SignedTransactionReadError.truncated }
        var value: UInt64 = 0
        for offset in 1...width {
            value = value << 8 | UInt64(bytes[index + offset])
        }
        index += 1 + width
        return value
    }

    // MARK: - Skipping

    /// Walks past a value this reader has no use for, without losing its
    /// place and without letting it say two things on the way.
    mutating func skipValue(depth: Int) throws {
        guard depth <= SignedTransactionReader.nestingDepthLimit else {
            throw SignedTransactionReadError.nestedTooDeep
        }
        guard index < bytes.count else { throw SignedTransactionReadError.truncated }
        let header = bytes[index]

        // Maps and arrays are walked rather than jumped over, because the
        // duplicate-key rule holds at any depth and a length cannot be
        // computed without reading what is inside anyway.
        if header >= 0x80 && header <= 0x8F || header == 0xDE || header == 0xDF {
            let count = try readMapCount()
            var keys = KeysSeen()
            for _ in 0..<count {
                try keys.take(try readString())
                try skipValue(depth: depth + 1)
            }
            return
        }
        if header >= 0x90 && header <= 0x9F || header == 0xDC || header == 0xDD {
            let count = try readArrayCount()
            for _ in 0..<count {
                try skipValue(depth: depth + 1)
            }
            return
        }
        if header <= 0x7F || header >= 0xE0 {
            index += 1
            return
        }
        if header >= 0xA0 && header <= 0xBF {
            index += 1
            _ = try take(Int(header & 0x1F))
            return
        }

        index += 1
        switch header {
        case 0xC0, 0xC2, 0xC3:
            return
        case 0xC4, 0xD9:
            let length = try readLength(width: 1)
            _ = try take(length)
        case 0xC5, 0xDA:
            let length = try readLength(width: 2)
            _ = try take(length)
        case 0xC6, 0xDB:
            let length = try readLength(width: 4)
            _ = try take(length)
        case 0xC7:
            let length = try readLength(width: 1)
            _ = try take(1 + length)
        case 0xC8:
            let length = try readLength(width: 2)
            _ = try take(1 + length)
        case 0xC9:
            let length = try readLength(width: 4)
            _ = try take(1 + length)
        case 0xCA, 0xCE, 0xD2:
            _ = try take(4)
        case 0xCB, 0xCF, 0xD3:
            _ = try take(8)
        case 0xCC, 0xD0:
            _ = try take(1)
        case 0xCD, 0xD1:
            _ = try take(2)
        case 0xD4: _ = try take(2)
        case 0xD5: _ = try take(3)
        case 0xD6: _ = try take(5)
        case 0xD7: _ = try take(9)
        case 0xD8: _ = try take(17)
        default:
            throw SignedTransactionReadError.unsupportedValue(header: header)
        }
    }

    // MARK: - Bytes

    /// Takes a run of bytes, or refuses a length the input did not carry.
    ///
    /// Nothing is sized from a number the input chose until this has agreed
    /// that the bytes are there, which is the whole of the rule against
    /// allocating in proportion to a declared length.
    mutating func take(_ length: Int) throws -> ArraySlice<UInt8> {
        guard length >= 0 else { throw SignedTransactionReadError.declaredLengthExceedsInput }
        guard length <= remaining else { throw SignedTransactionReadError.declaredLengthExceedsInput }
        let slice = bytes[index..<(index + length)]
        index += length
        return slice
    }

    private mutating func readLength(width: Int) throws -> Int {
        guard remaining >= width else { throw SignedTransactionReadError.truncated }
        var value = 0
        for offset in 0..<width {
            value = value << 8 | Int(bytes[index + offset])
        }
        index += width
        return value
    }

    private func readBigEndian32(at offset: Int) throws -> Int {
        guard offset + 4 <= bytes.count else { throw SignedTransactionReadError.truncated }
        // Four bytes into an `Int`, which is sixty four bits everywhere this
        // builds, so nothing here can overflow into a negative length.
        return Int(bytes[offset]) << 24
            | Int(bytes[offset + 1]) << 16
            | Int(bytes[offset + 2]) << 8
            | Int(bytes[offset + 3])
    }
}

// MARK: - KeysSeen

/// The keys one map has produced so far, and the rule they are held to.
///
/// One rule: no key twice, at any depth. That is the whole of what stops a
/// map saying two things, and it is deliberately not joined by a rule about
/// the order they arrive in, which refuses shapes real wallets send and
/// forbids nothing a reader could be confused by.
private struct KeysSeen {

    private var seen: Set<String> = []

    mutating func take(_ key: String) throws {
        guard seen.insert(key).inserted else {
            throw SignedTransactionReadError.duplicateKey(key)
        }
    }
}
