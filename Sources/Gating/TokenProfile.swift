import Foundation

/// Somewhere a member can go to look at, buy or pool the token.
///
/// A label and a URL, both the operator's. The original had a closed enum of
/// six link kinds, each of which knew how to build one exchange's URL from an
/// asset id, which meant a project on a seventh exchange needed a recompile and
/// a project on none of them still shipped links to all six.
public struct TokenLink: Sendable, Equatable, Hashable, Codable {

    // MARK: - Properties

    /// What the link says, for example `Exchange` or `Explorer`.
    public let label: String

    /// Where it goes.
    public let url: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - label: What the link says.
    ///   - url: Where it goes.
    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }

    // MARK: - Public Methods

    /// The link as Discord markdown.
    public var markdown: String {
        "[\(label)](\(url))"
    }
}

/// The one token a server's holder ladder is measured in.
///
/// Everything here is the operator's, and the important field is
/// ``decimals``. The original assumed six, as a named constant in one file and
/// as a bare literal in eight others, which is right for exactly one asset. A
/// zero-decimal asset read through that assumption is a millionth of itself,
/// so every rung of the ladder becomes unreachable and every member is
/// demoted at once. It is required configuration here, there is no default,
/// and every whole-token threshold in the module is converted through this
/// value and no other.
public struct TokenProfile: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The on-chain asset id.
    public let assetId: UInt64

    /// The ticker, as it appears beside an amount.
    public let symbol: String

    /// The longer name, for a card's title.
    public let displayName: String

    /// Decimal places. Two means one whole token is 100 smallest units.
    public let decimals: UInt8

    /// Smallest units in one whole token: ten to the power of ``decimals``.
    public let baseUnitsPerWholeUnit: UInt64

    /// A thumbnail for a card, or nil when the operator set none.
    public let logoURL: String?

    /// The stripe down the side of a card, as `0xRRGGBB`, or nil for none.
    public let cardColor: UInt32?

    /// Where a member can go to look at or trade the token.
    public let links: [TokenLink]

    // MARK: - Initializers

    /// - Parameters:
    ///   - assetId: The on-chain asset id.
    ///   - symbol: The ticker.
    ///   - displayName: The longer name; the symbol when omitted.
    ///   - decimals: Decimal places, at most 19. Ten to the twentieth
    ///     overflows `UInt64`, so more is refused here rather than trapping
    ///     somewhere downstream.
    ///   - logoURL: A card thumbnail.
    ///   - cardColor: A card colour.
    ///   - links: Where a member can go.
    public init(
        assetId: UInt64,
        symbol: String,
        displayName: String? = nil,
        decimals: UInt8,
        logoURL: String? = nil,
        cardColor: UInt32? = nil,
        links: [TokenLink] = []
    ) throws {
        guard decimals <= 19 else {
            throw GatingConfigurationError.unsupportedDecimals(
                key: TokenProfile.decimalsKey,
                value: UInt64(decimals)
            )
        }
        var scale: UInt64 = 1
        for _ in 0..<decimals {
            scale *= 10
        }
        self.assetId = assetId
        self.symbol = symbol
        self.displayName = displayName ?? symbol
        self.decimals = decimals
        self.baseUnitsPerWholeUnit = scale
        self.logoURL = logoURL
        self.cardColor = cardColor
        self.links = links
    }

    // MARK: - Public Methods

    /// Whole tokens as smallest units, saturating at the ceiling.
    ///
    /// Saturating rather than throwing, because the callers are thresholds. An
    /// operator who types too many zeros gets a rung nobody reaches, which is
    /// visible in the server and fixable in a minute. A wrapped `UInt64` would
    /// give them a rung everybody reaches, which is neither.
    public func baseUnits(whole: UInt64) -> UInt64 {
        let (product, overflowed) = whole.multipliedReportingOverflow(by: baseUnitsPerWholeUnit)
        return overflowed ? UInt64.max : product
    }

    /// Smallest units written out at this token's precision, no digit lost.
    public func format(_ baseUnits: UInt64) -> String {
        GatingFormatting.amount(baseUnits, decimals: Int(decimals))
    }

    /// Smallest units written out with the ticker after them.
    public func formatWithSymbol(_ baseUnits: UInt64) -> String {
        "\(format(baseUnits)) \(symbol)"
    }

    /// Every link as one line of Discord markdown.
    public var linksMarkdown: String {
        links.map(\.markdown).joined(separator: " | ")
    }
}

extension TokenProfile {

    // MARK: - Loading

    /// The variable naming the asset.
    public static let assetIdKey = "TOKEN_ASSET_ID"

    /// The variable naming the ticker.
    public static let symbolKey = "TOKEN_SYMBOL"

    /// The variable naming the longer name.
    public static let displayNameKey = "TOKEN_NAME"

    /// The variable naming the precision. Required; see ``decimals``.
    public static let decimalsKey = "TOKEN_DECIMALS"

    /// The variable naming the card thumbnail.
    public static let logoKey = "TOKEN_LOGO_URL"

    /// The variable naming the card colour.
    public static let colorKey = "TOKEN_CARD_COLOR"

    /// Reads the token from a dictionary. The shape tests use.
    public static func load(from environment: [String: String]) throws -> TokenProfile {
        try load { environment[$0] }
    }

    /// Reads the token, or says which variable is wrong.
    ///
    /// Takes a lookup rather than a dictionary so a caller can pass its own
    /// environment straight through without copying it first.
    public static func load(_ lookup: (String) -> String?) throws -> TokenProfile {
        let assetId = try NumberedEnvironment.requiredWholeNumber(
            assetIdKey,
            purpose: "It is the on-chain id of the asset your holder ladder is measured in.",
            lookup
        )
        let symbol = try NumberedEnvironment.required(
            symbolKey,
            purpose: "It is the ticker shown beside an amount.",
            lookup
        )
        let rawDecimals = try NumberedEnvironment.requiredWholeNumber(
            decimalsKey,
            purpose: "It is how many decimal places your asset has, and every threshold in "
                + "the ladder is converted through it.",
            lookup
        )
        guard rawDecimals <= 19 else {
            throw GatingConfigurationError.unsupportedDecimals(key: decimalsKey, value: rawDecimals)
        }

        var logoURL: String?
        if let raw = NumberedEnvironment.nonEmpty(logoKey, lookup) {
            guard NumberedEnvironment.isLinkableURL(raw) else {
                throw GatingConfigurationError.unusableURL(key: logoKey, value: raw)
            }
            logoURL = raw
        }

        return try TokenProfile(
            assetId: assetId,
            symbol: symbol,
            displayName: NumberedEnvironment.nonEmpty(displayNameKey, lookup),
            decimals: UInt8(rawDecimals),
            logoURL: logoURL,
            cardColor: try NumberedEnvironment.color(colorKey, lookup),
            links: try loadLinks(lookup)
        )
    }

    /// Reads `TOKEN_LINK_n_LABEL` and `TOKEN_LINK_n_URL` upward from 1.
    ///
    /// The first gap ends the list, like every other numbered list here. A
    /// label without a URL is a refusal rather than a link to nowhere.
    private static func loadLinks(_ lookup: (String) -> String?) throws -> [TokenLink] {
        var links: [TokenLink] = []
        for index in 1...NumberedEnvironment.maxEntries {
            let labelKey = "TOKEN_LINK_\(index)_LABEL"
            let urlKey = "TOKEN_LINK_\(index)_URL"
            guard let label = NumberedEnvironment.nonEmpty(labelKey, lookup) else { break }
            let url = try NumberedEnvironment.required(
                urlKey,
                purpose: "\(labelKey) is set, so this link needs somewhere to go.",
                lookup
            )
            guard NumberedEnvironment.isLinkableURL(url) else {
                throw GatingConfigurationError.unusableURL(key: urlKey, value: url)
            }
            links.append(TokenLink(label: label, url: url))
        }
        if links.count == NumberedEnvironment.maxEntries {
            try NumberedEnvironment.refuseOverflow(
                "TOKEN_LINK_\(NumberedEnvironment.maxEntries + 1)_LABEL",
                lookup
            )
        }
        return links
    }
}
