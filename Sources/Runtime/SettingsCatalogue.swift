import Chain
import Foundation
import Gating

/// Whether a variable has to be set for the build to start.
public enum SettingsRequirement: String, Sendable, Equatable {

    /// No default exists and boot refuses without it.
    case required

    /// Absent means the documented behaviour, never somebody else's value.
    case optional
}

/// Whether a variable's value may be printed.
public enum SettingsSecrecy: String, Sendable, Equatable {

    /// The value may appear in the startup report.
    case plain

    /// The value may never appear anywhere: not its length, not a prefix, not
    /// a hash. A hash of a low entropy secret is a crackable secret and a
    /// length is enough to confirm a guess (CATALOG-6.a).
    case secret

    /// The value is a URL, so only its scheme, host and port may be printed.
    ///
    /// Some node providers put the credential in the path, and the report is
    /// meant to be safe to paste into an issue.
    case url
}

/// Which part of the build reads a variable, for grouping the report.
public enum SettingsGroup: String, Sendable, Equatable, CaseIterable {

    /// The token the ladder is measured in.
    case token = "Your token"

    /// The rungs of the holder ladder.
    case ladder = "The ladder"

    /// The collections gated on.
    case collections = "Collections"

    /// The liquidity pools counted.
    case pools = "Pools"

    /// Roles and administrators.
    case access = "Roles and administrators"

    /// The node and the brakes on reading it.
    case chain = "The node"

    /// What this program itself needs.
    case runtime = "This process"

    /// The chat service, when this build has one.
    ///
    /// Nothing in this module fills this group. The entries belong to
    /// whatever conforms to ``ChatGateway`` and arrive through
    /// ``ChatGateway/settingsEntries``, because a module that links no chat
    /// library cannot name a chat variable (`BUILD-4`).
    case chat = "The chat service"
}

/// One variable this build reads, described exactly once.
///
/// The name is taken from the constant that owns it rather than retyped,
/// because a retyped name is how a rename becomes a variable an operator sets
/// and nothing reads.
public struct SettingsEntry: Sendable, Equatable {

    // MARK: - Properties

    /// The variable, or the family pattern with `#` where a number goes.
    public let pattern: String

    /// What it is for, in one sentence an operator can act on.
    public let purpose: String

    /// Whether boot refuses without it.
    public let requirement: SettingsRequirement

    /// Whether its value may be printed.
    public let secrecy: SettingsSecrecy

    /// Which part of the build reads it.
    public let group: SettingsGroup

    // MARK: - Initializers

    /// - Parameters:
    ///   - pattern: The variable, or a family pattern with `#` for a number.
    ///   - purpose: What it is for.
    ///   - requirement: Whether boot refuses without it.
    ///   - secrecy: Whether its value may be printed.
    ///   - group: Which part of the build reads it.
    public init(
        _ pattern: String,
        purpose: String,
        requirement: SettingsRequirement = .optional,
        secrecy: SettingsSecrecy = .plain,
        group: SettingsGroup
    ) {
        self.pattern = pattern
        self.purpose = purpose
        self.requirement = requirement
        self.secrecy = secrecy
        self.group = group
    }

    // MARK: - Public Methods

    /// Whether this entry describes more than one variable.
    public var isFamily: Bool {
        pattern.contains("#")
    }

    /// Whether `name` is one of the variables this entry describes.
    ///
    /// A family matches when the fixed parts line up and every `#` stands
    /// against at least one digit. Numbered families are described as
    /// families rather than as thirty-two entries each, because thirty-two
    /// entries per family would bury the report and the number is an
    /// implementation ceiling rather than a product statement.
    public func matches(_ name: String) -> Bool {
        var remaining = Substring(name)
        let parts = pattern.split(separator: "#", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            if index > 0 {
                let digits = remaining.prefix(while: \.isNumber)
                guard !digits.isEmpty else { return false }
                remaining = remaining.dropFirst(digits.count)
            }
            guard remaining.hasPrefix(part) else { return false }
            remaining = remaining.dropFirst(part.count)
        }
        return remaining.isEmpty
    }
}

/// Every variable this build reads, described once.
///
/// One list, and the report, the audit and the secret rule are all rendered
/// from it. Rendering from the catalogue is what makes the secret rule
/// structural rather than remembered: the renderer has no access to a value
/// except through an entry, and an entry marked secret has no path that
/// yields one (TRUST-1, ADOPT-9).
public enum SettingsCatalogue: Sendable {

    // MARK: - Properties

    /// Prefixes this build owns. A variable inside one that nothing read is
    /// reported as a probable typo rather than ignored (ADOPT-9.a).
    public static let ownedPrefixes: [String] = [
        "TOKEN_",
        "TIER_",
        "COLLECTION_",
        "POOL_",
        "LP_",
        "ADMIN_WALLET_",
        "VERIFIED_",
        "CHAIN_",
        "STORE_",
        "HEALTH_"
    ]

    /// Prefixes reserved for a part this build does not have.
    ///
    /// Stated as a list here rather than left to whoever implements the check,
    /// because there is no chat module yet whose constants could be
    /// enumerated: without this one reader reserves the whole prefix, another
    /// reserves one variable and a third adds the portal keys, and one
    /// environment file produces three different boots.
    ///
    /// A variable inside one of these **refuses the boot**. An operator who
    /// sets a chat token believes their members are about to see a bot; they
    /// are not, and a process that starts, answers healthy and never appears
    /// in the server is exactly the outage the SEE family opens with.
    ///
    /// **A prefix stays on this list once the part exists.** The rule is not
    /// "this prefix is forbidden", it is "nothing here would read it", and
    /// the thing that settles that is whether a variable is described. A part
    /// that is linked hands over its own entries through
    /// ``ChatGateway/settingsEntries``, those entries describe its variables,
    /// and a described variable is never reserved. Take the part away and the
    /// entries go with it and the refusal is back, unchanged, with nothing
    /// having been edited. That is why the chat prefix is still here even
    /// though a chat surface now exists: the refusal is for the build that
    /// has not got one.
    public static let reservedPrefixes: [String] = ["DISCORD_", "VERIFY_"]

    /// What a reserved prefix is reserved for, for the refusal's sentence.
    ///
    /// Written to follow "this build has no", so no article on the front of
    /// any of them.
    public static func reservedPart(_ prefix: String) -> String {
        switch prefix {
        case "DISCORD_": return "chat surface"
        case "VERIFY_": return "wallet verification"
        default: return "part that would read it"
        }
    }

    /// Every variable, in the order the report prints them.
    public static let entries: [SettingsEntry] = tokenEntries
        + ladderEntries
        + collectionEntries
        + poolEntries
        + accessEntries
        + chainEntries
        + runtimeEntries

    // MARK: - Public Methods

    /// The entry describing `name`, or nil when nothing does.
    public static func entry(for name: String) -> SettingsEntry? {
        entry(for: name, in: entries)
    }

    /// The entry describing `name` in this list, or nil when nothing does.
    ///
    /// Takes the list rather than reading ``entries``, because a linked part
    /// contributes entries of its own and every check has to see the same
    /// list the report does.
    ///
    /// - Parameters:
    ///   - name: The variable as the operator wrote it.
    ///   - entries: Every entry in play, this build's own and any a linked
    ///     part supplied.
    public static func entry(for name: String, in entries: [SettingsEntry]) -> SettingsEntry? {
        entries.first { $0.matches(name) }
    }

    /// Every variable name in the catalogue's ``SettingsGroup/chain`` group.
    ///
    /// Needed because the chain loader takes a dictionary rather than a
    /// lookup, so its reads cannot record themselves. Taken from the
    /// catalogue, which takes the names from the constants that own them, so
    /// no variable name is written down twice.
    public static var chainNames: [String] {
        entries.filter { $0.group == .chain && !$0.isFamily }.map(\.pattern)
    }

    /// Which of the reserved prefixes `name` carries, if any.
    public static func reservedPrefix(of name: String) -> String? {
        reservedPrefixes.first { name.hasPrefix($0) }
    }

    /// Which of the reserved prefixes `name` carries and no linked part
    /// claims, if any.
    ///
    /// - Parameters:
    ///   - name: The variable as the operator wrote it.
    ///   - entries: Every entry in play.
    public static func reservedPrefix(of name: String, given entries: [SettingsEntry]) -> String? {
        let owned = ownedPrefixes(given: entries)
        guard !owned.contains(where: { name.hasPrefix($0) }) else { return nil }
        return reservedPrefix(of: name)
    }

    /// Every prefix this build reads, given what a linked part supplied.
    ///
    /// A reserved prefix moves over as soon as one entry under it arrives,
    /// and it moves **whole**. That is the difference between reserving a
    /// prefix and describing a variable, and it is what a typo needs: with a
    /// chat surface linked, `DISCORD_BOT_TOKE` is one edit from something
    /// this build reads, so it belongs with `TIER_1_MIM` as a probable typo
    /// that is reported (`ADOPT-9.a`), not with a variable for a part that
    /// does not exist, which is refused (`RUN-9.a`). Take the part away and
    /// the entries go with it and the prefix is reserved again.
    ///
    /// - Parameter entries: Every entry in play.
    public static func ownedPrefixes(given entries: [SettingsEntry]) -> [String] {
        ownedPrefixes + reservedPrefixes.filter { prefix in
            entries.contains { $0.pattern.hasPrefix(prefix) }
        }
    }

    /// Whether `name` carries a prefix this build reads, given what a linked
    /// part supplied.
    ///
    /// - Parameters:
    ///   - name: The variable as the operator wrote it.
    ///   - entries: Every entry in play.
    public static func isOwned(_ name: String, given entries: [SettingsEntry]) -> Bool {
        ownedPrefixes(given: entries).contains { name.hasPrefix($0) }
    }

    /// Whether `name` carries a prefix this build owns.
    public static func isOwned(_ name: String) -> Bool {
        ownedPrefixes.contains { name.hasPrefix($0) }
    }

    // MARK: - Private Methods

    private static let tokenEntries: [SettingsEntry] = [
        SettingsEntry(
            TokenProfile.assetIdKey,
            purpose: "The on-chain id of the asset your holder ladder is measured in.",
            requirement: .required,
            group: .token
        ),
        SettingsEntry(
            TokenProfile.symbolKey,
            purpose: "The ticker shown beside an amount.",
            requirement: .required,
            group: .token
        ),
        SettingsEntry(
            TokenProfile.decimalsKey,
            purpose: "How many decimal places your asset has. Every threshold is converted "
                + "through it.",
            requirement: .required,
            group: .token
        ),
        SettingsEntry(
            TokenProfile.displayNameKey,
            purpose: "The longer name, for a card's title. The ticker when unset.",
            group: .token
        ),
        SettingsEntry(
            TokenProfile.logoKey,
            purpose: "A thumbnail for a card. Stored and never fetched by this process.",
            secrecy: .url,
            group: .token
        ),
        SettingsEntry(
            TokenProfile.colorKey,
            purpose: "The stripe down the side of a card, as six hexadecimal digits.",
            group: .token
        ),
        SettingsEntry(
            "TOKEN_LINK_#_LABEL",
            purpose: "What a link shown to a member says, numbered from 1.",
            group: .token
        ),
        SettingsEntry(
            "TOKEN_LINK_#_URL",
            purpose: "Where that link goes. Stored and never fetched.",
            secrecy: .url,
            group: .token
        )
    ]

    private static let ladderEntries: [SettingsEntry] = [
        SettingsEntry(
            "TIER_#_NAME",
            purpose: "One rung's name, numbered from 1. TIER_1_NAME is required, because a "
                + "server with no ladder would grant roles at somebody else's numbers. The "
                + "first gap ends the ladder.",
            requirement: .required,
            group: .ladder
        ),
        SettingsEntry(
            "TIER_#_MIN",
            purpose: "The smallest holding on that rung, in whole tokens. Required for every "
                + "rung that exists, so TIER_1_MIN is required too.",
            requirement: .required,
            group: .ladder
        ),
        SettingsEntry(
            "TIER_#_EMOJI",
            purpose: "Shown beside that rung's name.",
            group: .ladder
        ),
        SettingsEntry(
            "TIER_#_ID",
            purpose: "That rung's stable key, when the name is not a good one.",
            group: .ladder
        ),
        SettingsEntry(
            "TIER_#_ROLE_ID",
            purpose: "The role that rung grants.",
            group: .ladder
        ),
        SettingsEntry(
            TierConfiguration.unrankedNameKey,
            purpose: "What a member below the first rung is called.",
            group: .ladder
        ),
        SettingsEntry(
            TierConfiguration.unrankedEmojiKey,
            purpose: "The emoji beside that word.",
            group: .ladder
        )
    ]

    private static let collectionEntries: [SettingsEntry] = [
        SettingsEntry(
            "COLLECTION_#_ID",
            purpose: "One collection's id, numbered from 1. The first gap ends the list.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_CREATOR",
            purpose: "The account that minted that collection. Required once the collection "
                + "exists: it is how a piece of yours is told apart from every other asset.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_NAME",
            purpose: "What that collection is called on a card.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_NAME_PREFIX",
            purpose: "A prefix every piece's name carries, when it has one.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_UNIT_NAME",
            purpose: "The unit name every piece carries, when it has one.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_MAX_SUPPLY",
            purpose: "The largest supply an asset may have and still be a piece. One unless set.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_ROLE_ID",
            purpose: "The role holding any piece of that collection grants.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_COUNT_#_MIN",
            purpose: "How many pieces reach a stacked rung of that collection.",
            group: .collections
        ),
        SettingsEntry(
            "COLLECTION_#_COUNT_#_ROLE_ID",
            purpose: "The role that stacked rung grants. Required once the rung exists.",
            group: .collections
        )
    ]

    private static let poolEntries: [SettingsEntry] = [
        SettingsEntry(
            "POOL_#_ID",
            purpose: "One pool's id, numbered from 1. The first gap ends the list.",
            group: .pools
        ),
        SettingsEntry(
            "POOL_#_LP_ASA",
            purpose: "The asset id of that pool's own LP token.",
            group: .pools
        ),
        SettingsEntry(
            "POOL_#_PAIRED_ASA",
            purpose: "The asset your token is paired with in that pool.",
            group: .pools
        ),
        SettingsEntry(
            "POOL_#_DECIMALS",
            purpose: "How many decimal places that pool's LP token has.",
            group: .pools
        ),
        SettingsEntry(
            "POOL_#_NAME",
            purpose: "What that pool is called on a card.",
            group: .pools
        ),
        SettingsEntry(
            "POOL_#_ROLE_ID",
            purpose: "The role a position in that pool grants.",
            group: .pools
        )
    ]

    private static let accessEntries: [SettingsEntry] = [
        SettingsEntry(
            GatingConfiguration.verifiedRoleKey,
            purpose: "The role for having proved an account at all.",
            group: .access
        ),
        SettingsEntry(
            LiquidityConfiguration.providerRoleKey,
            purpose: "The badge for having any liquidity position.",
            group: .access
        ),
        SettingsEntry(
            "ADMIN_WALLET_#",
            purpose: "An account allowed to administer, numbered from 1. The list starts empty "
                + "and nobody is on it who was not put there by you.",
            group: .access
        )
    ]

    private static let chainEntries: [SettingsEntry] = [
        SettingsEntry(
            ChainEnvironment.nodeURL,
            purpose: "The node to read from. Absolute http or https, with a host.",
            requirement: .required,
            secrecy: .url,
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.apiToken,
            purpose: "Your node provider's token, when the provider needs one.",
            secrecy: .secret,
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.proofHeaders,
            purpose: "Response header names copied onto a health answer as proof of which "
                + "provider served it. Comma separated.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.verifyAssetDecimals,
            purpose: "Whether to read the asset's precision from the chain at boot and refuse "
                + "to start when it disagrees. On unless set.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.requestsPerSecond,
            purpose: "Requests per second the limiter allows.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.dailyRequestBudget,
            purpose: "Requests permitted per UTC day, reads and signing together. Zero means no "
                + "budget. This counts requests and is not a limit on what may be sent.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.budgetPersistEvery,
            purpose: "How many requests pass between writes of the day's counter.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.batchSize,
            purpose: "How many accounts are read in parallel per batch.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.poolCacheSeconds,
            purpose: "Seconds a pool's reserves stay usable before they are read again.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.walletCacheSeconds,
            purpose: "Seconds a completed account reading stays usable.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.walletCooldownSeconds,
            purpose: "Seconds before the same account may be read again on demand.",
            group: .chain
        ),
        SettingsEntry(
            ChainEnvironment.healthProbeSeconds,
            purpose: "Seconds a provider proof probe's answer is reused.",
            group: .chain
        )
    ]

    private static let runtimeEntries: [SettingsEntry] = [
        SettingsEntry(
            RuntimeEnvironment.storePath,
            purpose: "Where this instance keeps what it remembers. Absolute, because a "
                + "supervisor restarting from another directory would otherwise hand the same "
                + "command a different and empty store.",
            requirement: .required,
            group: .runtime
        ),
        SettingsEntry(
            RuntimeEnvironment.healthPort,
            purpose: "The port the health endpoint listens on. No default: the normal hosted "
                + "shape is several communities on one machine, and a shared default turns the "
                + "second instance's first start into a clash that looks like a duplicate.",
            requirement: .required,
            group: .runtime
        ),
        SettingsEntry(
            RuntimeEnvironment.healthAddress,
            purpose: "The address the health endpoint binds. Loopback unless set, because the "
                + "answer can carry provider proof headers and a waiting list.",
            group: .runtime
        )
    ]
}
