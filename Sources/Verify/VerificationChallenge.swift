import Foundation

/// The five lines a member reads in their wallet, and the bytes they sign.
///
/// ```
/// <the operator's label>
/// Server: <this instance's own identity>
/// Member: <the subject this session was minted for>
/// Code: <six characters, the same six the member was just shown>
/// <a hundred and twenty eight bit nonce>
/// ```
///
/// Every line earns its place. The label is the operator's, so a member sees
/// their own community's words and not somebody else's (ADOPT-1.c). The server
/// line is what makes a proof worthless in another community: a signature
/// minted here verifies against nothing elsewhere, whatever else matches
/// (VERIFY-4, HOST-6). The member line is what stops one member's signature
/// being adopted for another, and it is opaque: the subject is whatever the
/// caller supplied, which above this boundary is an identifier that was minted
/// rather than derived from a person. The code is the anti-phishing device,
/// six characters a member can compare against what their chat client just
/// showed them without reading a nonce on a phone. The nonce is the part they
/// cannot choose.
///
/// **Five lines is an invariant, not a description of the usual case.** The
/// subject is located by its line index when a submitted note is checked, so a
/// label with a line break in it would render six lines and move the nonce
/// into the slot the subject check reads. Every value rendered into a line is
/// therefore refused if it carries a break of any kind, and the label is
/// bounded (REQ-verify-002 in `specs/verify`). The other half of that rule
/// belongs to a host, which checks the operator's label when it starts and
/// names the variable to fix, so an operator learns of it before a member
/// does.
///
/// The value renders its own text and reads it back, so the bytes signed and
/// the bytes compared come out of one function and cannot drift apart.
public struct VerificationChallenge: Sendable {

    // MARK: - Properties

    /// Lines in a challenge. Fixed, because the subject is found by index.
    public static let lineCount: Int = 5

    /// Which line carries the subject, counting from zero.
    public static let subjectLineIndex: Int = 2

    /// The largest an operator's label may be, in UTF-8 bytes.
    ///
    /// Bounded so an operator cannot put a page of text in front of a member's
    /// wallet and push everything worth reading off the screen.
    public static let maximumLabelByteCount: Int = 100

    /// Characters in the code a member compares against their chat client.
    public static let codeCharacterCount: Int = 6

    /// Characters in the nonce: a hundred and twenty eight bits as hexadecimal.
    public static let nonceCharacterCount: Int = 32

    /// What the second line says before the instance identity.
    public static let instanceLinePrefix: String = "Server: "

    /// What the third line says before the subject.
    public static let subjectLinePrefix: String = "Member: "

    /// What the fourth line says before the code.
    public static let codeLinePrefix: String = "Code: "

    /// The operator's own words, the first thing a member reads in the wallet.
    public let label: String

    /// What this instance calls itself, so a proof means nothing anywhere else.
    public let instanceIdentity: String

    /// Who the proof will be adopted for, as an opaque string.
    public let subject: String

    /// The six characters shown to the member and carried in the signed bytes.
    public let code: String

    /// A hundred and twenty eight bits the member cannot choose.
    public let nonce: String

    /// The five lines, as the member's wallet will show them.
    public var text: String {
        [
            label,
            Self.instanceLinePrefix + instanceIdentity,
            Self.subjectLinePrefix + subject,
            Self.codeLinePrefix + code,
            nonce
        ].joined(separator: "\n")
    }

    /// The bytes a wallet signs and the bytes a submitted note is compared
    /// against.
    public var bytes: Data {
        Data(text.utf8)
    }

    // MARK: - Initializers

    /// A challenge rebuilt from parts, refusing anything that would not render
    /// as five lines.
    ///
    /// - Parameters:
    ///   - label: The operator's own words.
    ///   - instanceIdentity: What this instance calls itself.
    ///   - subject: The opaque subject the session was minted for.
    ///   - code: The six characters the member was shown.
    ///   - nonce: The nonce.
    /// - Throws: ``VerifyError/challengeValueCarriesLineBreak(field:)`` when
    ///   any value carries a break, or
    ///   ``VerifyError/challengeLabelTooLong(byteCount:limit:)``.
    public init(
        label: String,
        instanceIdentity: String,
        subject: String,
        code: String,
        nonce: String
    ) throws {
        try Self.requireOneLine(label, field: "challenge label")
        try Self.requireOneLine(instanceIdentity, field: "instance identity")
        try Self.requireOneLine(subject, field: "subject")
        try Self.requireOneLine(code, field: "code")
        try Self.requireOneLine(nonce, field: "nonce")
        let labelBytes = label.utf8.count
        guard labelBytes <= Self.maximumLabelByteCount else {
            throw VerifyError.challengeLabelTooLong(
                byteCount: labelBytes,
                limit: Self.maximumLabelByteCount
            )
        }
        self.label = label
        self.instanceIdentity = instanceIdentity
        self.subject = subject
        self.code = code
        self.nonce = nonce
    }

    // MARK: - Public Methods

    /// A fresh challenge, with a code and a nonce drawn from the system's own
    /// random number generator.
    ///
    /// Nothing about the code or the nonce is derived from the subject, the
    /// address, the clock or any argument. A nonce seeded from a timestamp
    /// gives two members who run the command together the same challenge, and
    /// gives anybody who knows when it was minted a head start at guessing it.
    ///
    /// - Parameters:
    ///   - label: The operator's own words.
    ///   - instanceIdentity: What this instance calls itself.
    ///   - subject: The opaque subject this session is being minted for.
    /// - Returns: The challenge.
    /// - Throws: ``VerifyError`` when a value would not render as one line, or
    ///   when the label is over the bound.
    public static func mint(
        label: String,
        instanceIdentity: String,
        subject: String
    ) throws -> VerificationChallenge {
        var generator = SystemRandomNumberGenerator()
        let code = String((0..<codeCharacterCount).map { _ in
            codeAlphabet[Int.random(in: 0..<codeAlphabet.count, using: &generator)]
        })
        let high = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        let low = UInt64.random(in: UInt64.min...UInt64.max, using: &generator)
        return try VerificationChallenge(
            label: label,
            instanceIdentity: instanceIdentity,
            subject: subject,
            code: code,
            nonce: hexadecimal(high) + hexadecimal(low)
        )
    }

    /// The subject a **submitted** note claims to have been minted for.
    ///
    /// This reads one line out of the bytes that arrived, at the index the
    /// challenge shape fixes, and nothing else. It deliberately does not
    /// rebuild the expected challenge from the submitted note: that would make
    /// the note comparison a tautology, because the expected value would be
    /// built out of the value being checked.
    ///
    /// It answers nil when the note is not five lines, is not UTF-8, or does
    /// not carry the subject prefix on the line it should. A caller reading
    /// nil has learned that the note is not this session's challenge, and the
    /// note comparison that follows is the reason to give the member, because
    /// "this prompt names a different member" would be a guess about bytes
    /// that are not a challenge at all.
    ///
    /// - Parameter note: The note bytes as they arrived.
    /// - Returns: The subject the note names, or nil.
    public static func subject(inNote note: Data) -> String? {
        let lines = note.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard lines.count == lineCount else { return nil }
        guard let line = String(data: Data(lines[subjectLineIndex]), encoding: .utf8) else { return nil }
        guard line.hasPrefix(subjectLinePrefix) else { return nil }
        return String(line.dropFirst(subjectLinePrefix.count))
    }

    // MARK: - Private Methods

    /// The alphabet the code is drawn from.
    ///
    /// No `I`, `O`, `0` or `1`: a member is reading this off a phone and
    /// comparing it against a second screen, and the pairs that look alike are
    /// the ones that make them give up rather than the ones that make them
    /// careful.
    private static let codeAlphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// The scalars that would break a challenge into more lines than it has.
    ///
    /// Checked as Unicode scalars rather than as characters because a carriage
    /// return followed by a line feed is one Swift `Character`, so a search for
    /// a line feed inside it finds nothing and the check that looked right
    /// passes over the one sequence most likely to arrive.
    private static let lineBreakScalars: Set<Unicode.Scalar> = [
        "\u{000A}", "\u{000D}", "\u{2028}", "\u{2029}"
    ]

    /// Refuses a value that would not render as exactly one line.
    private static func requireOneLine(_ value: String, field: String) throws {
        guard !value.unicodeScalars.contains(where: { lineBreakScalars.contains($0) }) else {
            throw VerifyError.challengeValueCarriesLineBreak(field: field)
        }
    }

    /// Sixty four bits as sixteen lowercase hexadecimal characters, padded.
    private static func hexadecimal(_ value: UInt64) -> String {
        let digits = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

// MARK: - Equatable

extension VerificationChallenge: Equatable {

    /// Two challenges are the same challenge when their bytes are the same
    /// bytes.
    ///
    /// Written out rather than synthesised so that the comparison is the one a
    /// note is held to: whole, as bytes, with nothing trimmed, folded or
    /// compared by prefix. Each of those accepts something the member did not
    /// sign.
    public static func == (lhs: VerificationChallenge, rhs: VerificationChallenge) -> Bool {
        lhs.bytes == rhs.bytes
    }
}
