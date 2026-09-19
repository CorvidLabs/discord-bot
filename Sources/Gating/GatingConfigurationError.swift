import Foundation

/// What is wrong with the configuration somebody wrote.
///
/// Every case names the variable to fix, because the person reading it is
/// setting the bot up for the first time and has no idea what the code calls
/// things (ADOPT-2). None of these has a fallback: absent configuration is a
/// refusal that names a variable, never a quiet substitution of somebody
/// else's asset, ladder or collection (ADOPT-1.c).
public enum GatingConfigurationError: Error, Equatable, LocalizedError, Sendable {

    /// A variable that has no default and was not set.
    case missing(key: String, purpose: String)

    /// A variable that has to be a whole number and is not.
    case notANumber(key: String, value: String)

    /// A threshold of zero. Everybody reaches it, so it is not a threshold.
    case zeroMinimum(key: String)

    /// A supply ceiling of zero. Nothing on chain could ever be under it.
    case zeroSupply(key: String)

    /// A numbered list that carries on past the last number this module reads.
    case tooManyEntries(key: String, limit: Int)

    /// A name with nothing in it an id can be made from.
    case unusableName(key: String, value: String)

    /// A URL the bot would hand to Discord and Discord would reject.
    case unusableURL(key: String, value: String)

    /// A colour that is not six hexadecimal digits.
    case unusableColor(key: String, value: String)

    /// More decimals than ten to that power fits in 64 bits.
    case unsupportedDecimals(key: String, value: UInt64)

    /// Two entries resolve to the same id, so one would overwrite the other.
    case duplicateId(id: String, first: String, second: String)

    /// Two entries share a display name, which is what gets stored and counted.
    case duplicateName(name: String, first: String, second: String)

    /// Two rungs sit at one threshold, so one can never be reached.
    case duplicateMinimum(minimum: UInt64, first: String, second: String)

    /// Two entries claim the same on-chain asset.
    case duplicateAsset(assetId: UInt64, first: String, second: String)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case let .missing(key, purpose):
            return "\(key) is not set. \(purpose) There is no default: a default here would be "
                + "somebody else's answer to a question only you can answer."
        case let .notANumber(key, value):
            return "\(key) is \"\(value)\", which is not a whole number."
        case let .zeroMinimum(key):
            return "\(key) is 0. A rung anybody reaches is not a rung; leave it out instead."
        case let .zeroSupply(key):
            return "\(key) is 0, so nothing could ever be a piece of this collection. Leave it "
                + "out for pieces minted one at a time, or set the largest edition size."
        case let .tooManyEntries(key, limit):
            return "\(key) is set, but only the first \(limit) entries of a numbered list are "
                + "read. Rather than quietly drop the rest, this is a refusal: renumber the list "
                + "so it ends at \(limit)."
        case let .unusableName(key, value):
            return "\(key) is \"\(value)\", which has no letters or digits to make an id from."
        case let .unusableURL(key, value):
            return "\(key) is \"\(value)\", which is not an http or https URL with a host. "
                + "Discord will not render anything else."
        case let .unusableColor(key, value):
            return "\(key) is \"\(value)\", which is not a colour. Write six hexadecimal digits, "
                + "optionally prefixed with # or 0x."
        case let .unsupportedDecimals(key, value):
            return "\(key) is \(value). Ten to that power does not fit in 64 bits, so no amount "
                + "could be converted. The maximum is 19."
        case let .duplicateId(id, first, second):
            return "\(first) and \(second) both come out as the id \"\(id)\". Give one of them "
                + "its own explicit id."
        case let .duplicateName(name, first, second):
            return "\(first) and \(second) are both \"\(name)\". A name is what gets stored and "
                + "counted, so two entries sharing one would be merged."
        case let .duplicateMinimum(minimum, first, second):
            return "\(first) and \(second) both sit at \(GatingFormatting.grouped(minimum)). "
                + "Two rungs at one threshold means one can never be reached."
        case let .duplicateAsset(assetId, first, second):
            return "\(first) and \(second) both name asset \(assetId). One holding cannot belong "
                + "to two of them."
        }
    }
}
