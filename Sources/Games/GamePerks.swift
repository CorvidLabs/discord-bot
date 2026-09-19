import Foundation

/// One change a collection makes to the loot table.
///
/// An operation rather than a number, because the three things a host wants to say
/// are genuinely different: "make this rarer", "make this commoner", and "this is
/// impossible until somebody holds one of mine". Only ``LootWeightOperation/set``
/// can raise a kind off a base weight of zero, and only it ignores what an earlier
/// perk already did, so two holders of the same kind of collection do not stack
/// into an absurd weight.
public struct LootWeightAdjustment: Sendable, Equatable {

    // MARK: - Properties

    /// The kind whose weight moves.
    public let kind: ShinyKind

    /// How it moves.
    public let operation: LootWeightOperation

    // MARK: - Initializers

    /// - Parameters:
    ///   - kind: The kind whose weight moves.
    ///   - operation: How it moves.
    public init(kind: ShinyKind, operation: LootWeightOperation) {
        self.kind = kind
        self.operation = operation
    }
}

/// How a ``LootWeightAdjustment`` changes a weight.
public enum LootWeightOperation: Sendable, Equatable {
    /// Scale the weight so far. `0.6` makes a kind rarer.
    case multiply(Double)

    /// Add to the weight so far.
    case add(Double)

    /// Replace the weight so far, whatever it was.
    ///
    /// The only operation that can unlock a kind sitting at a base weight of zero,
    /// and the only one two holders of the same collection cannot stack.
    case set(Double)

    /// The number the operation carries, for validation.
    public var value: Double {
        switch self {
        case .multiply(let value): return value
        case .add(let value): return value
        case .set(let value): return value
        }
    }
}

/// A perk that rerolls a disappointing find.
///
/// The coin is spent whenever the find is one of ``kinds``, whether or not it
/// lands. That is not an accident of the original and it must not be tidied away:
/// skipping the draw when the outcome would not be used consumes the seeded stream
/// differently, and every table dealt after it diverges.
public struct PerkReroll: Sendable, Equatable {

    // MARK: - Properties

    /// Chance in `0...1` that the find is rerolled once.
    public let probability: Double

    /// Finds poor enough to be worth rerolling. Anything else spends no draw at
    /// all.
    public let kinds: Set<ShinyKind>

    // MARK: - Initializers

    /// - Parameters:
    ///   - probability: Chance in `0...1`.
    ///   - kinds: Finds that trigger the coin.
    public init(probability: Double, kinds: Set<ShinyKind>) {
        self.probability = probability
        self.kinds = kinds
    }
}

/// A perk that sometimes turns up a second find.
///
/// The coin is spent on every forage, landing or not, for the same reason
/// ``PerkReroll``'s is. The extra find goes in the pouch and pays no chips: it is
/// loot, not income.
public struct PerkExtraFind: Sendable, Equatable {

    // MARK: - Properties

    /// Chance in `0...1` of a second find.
    public let probability: Double

    // MARK: - Initializers

    /// - Parameter probability: Chance in `0...1`.
    public init(probability: Double) {
        self.probability = probability
    }
}

/// What holding one of a host's collections is worth at the tables.
///
/// The original hardcoded four booleans for two specific collections and scattered
/// their effects through three files. Everything one collection does now lives in
/// one value the host writes down, so a host can have none of these, or six
/// (`ADOPT-1.b`).
///
/// A perk is never required. Every field has a do-nothing default, and a server
/// that configures no perks at all plays the game exactly as somebody with no
/// collections plays it today (`ADOPT-3`).
public struct CollectionPerk: Sendable, Equatable, Identifiable {

    // MARK: - Properties

    /// The collection id this applies to, matched against ``GameHoldings``.
    ///
    /// Normalised: lowercase, and letters, digits and underscores only.
    /// ``GamePerks/init(_:)`` refuses any other shape, because the holdings this
    /// is compared against are normalised before they get here and an exact match
    /// against a differently spelled id is a perk that never fires.
    public let id: String

    /// What a member reads when this perk fires.
    ///
    /// The host's word for their own collection. Nothing in this package supplies
    /// one, because any default here would be somebody else's noun in somebody
    /// else's server (`ADOPT-1.c`).
    public let name: String

    /// Chips added to the daily claim for holding one.
    public let dailyBonusChips: Int

    /// Multiplies the wait between forages. `0.5` halves it; `1` leaves it alone.
    ///
    /// Factors stack, but the floor in ``Chips/minimumForageCooldown`` is absolute,
    /// so no combination of collections turns foraging into a button to hold down.
    public let forageCooldownFactor: Double

    /// Changes to the loot table, applied in this order.
    ///
    /// An array rather than a dictionary, so "halve the twigs then add two glass"
    /// means one thing rather than whichever thing a hash order produced.
    public let weightAdjustments: [LootWeightAdjustment]

    /// Rerolls a poor find. Nil for a collection that does not.
    public let reroll: PerkReroll?

    /// A kind tucked into the pouch on every single forage, free, no draw spent.
    public let freeFind: ShinyKind?

    /// Sometimes turns up a second find. Nil for a collection that does not.
    public let extraFind: PerkExtraFind?

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: Collection id, matched against a player's holdings.
    ///   - name: What a member reads when the perk fires. Defaults to the id.
    ///   - dailyBonusChips: Chips added to the daily claim.
    ///   - forageCooldownFactor: Multiplies the forage wait.
    ///   - weightAdjustments: Loot table changes, in order.
    ///   - reroll: Reroll rule, if any.
    ///   - freeFind: A kind granted on every forage, if any.
    ///   - extraFind: Second-find rule, if any.
    public init(
        id: String,
        name: String? = nil,
        dailyBonusChips: Int = 0,
        forageCooldownFactor: Double = 1,
        weightAdjustments: [LootWeightAdjustment] = [],
        reroll: PerkReroll? = nil,
        freeFind: ShinyKind? = nil,
        extraFind: PerkExtraFind? = nil
    ) {
        self.id = id
        self.name = name ?? id
        self.dailyBonusChips = dailyBonusChips
        self.forageCooldownFactor = forageCooldownFactor
        self.weightAdjustments = weightAdjustments
        self.reroll = reroll
        self.freeFind = freeFind
        self.extraFind = extraFind
    }
}

/// The host's whole perk configuration, in the order it was written down.
///
/// **The order is the contract.** Perks are applied in configuration order and
/// never in holdings order, because a player's holdings are a set and a set has no
/// order a replay could depend on. Two players holding the same collections spend
/// their draws in the same sequence, and the same seed produces the same forage
/// forever.
///
/// The trap this type exists to avoid is subtler than it looks. Making perks
/// configurable at all is what threatens replay: a draw that happens only when some
/// perk is present makes the stream a function of the configuration. Keeping the
/// sequence fixed means a host with no perks gets exactly the stream a player with
/// no collections has always got, and adding a perk only ever adds draws for the
/// players who hold that collection.
public struct GamePerks: Sendable, Equatable {

    // MARK: - Properties

    /// Every configured perk, in configuration order.
    public let ordered: [CollectionPerk]

    // MARK: - Initializers

    /// Builds a perk set, refusing anything a host would rather hear about now.
    ///
    /// **A collection id must arrive normalised: lowercase, and nothing in it but
    /// letters, digits and underscores.** The ids here are matched exactly, and
    /// they come from the same operator configuration the rest of the product
    /// reads, which normalises a name it is given to exactly that shape before
    /// anything matches on it. A host that reads one variable and configures both
    /// sides from it would otherwise pass `Founders Pass` to a perk while every
    /// holding it will ever be compared against says `founders_pass`: the perk is
    /// non-empty, unpadded and unique, so every other check below passes, and it
    /// then never fires for anybody, forever, with nothing anywhere saying so.
    /// A refusal at the configuration is loud where that mismatch is silent.
    ///
    /// The rule is checked, never applied. Normalising the id here would mean this
    /// module carrying a second copy of a transform it cannot see, and the two
    /// would drift; checking the shape needs no shared code, because a normalised
    /// id is recognisable on its own.
    ///
    /// - Parameter perks: The perks, in the order they should apply.
    /// - Throws: ``GameConfigurationError`` naming the collection and the setting.
    public init(_ perks: [CollectionPerk]) throws {
        var seen: Set<String> = []
        for perk in perks {
            // Validated in the form it is stored and matched in. Checking a
            // trimmed copy and keeping the raw one let " founders " through as a
            // structurally valid perk that could never match a holding.
            let trimmed = perk.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw GameConfigurationError.emptyCollectionId
            }
            guard trimmed == perk.id else {
                throw GameConfigurationError.paddedCollectionId(collectionId: perk.id)
            }
            guard Self.isNormalized(perk.id) else {
                throw GameConfigurationError.unnormalizedCollectionId(collectionId: perk.id)
            }
            guard seen.insert(perk.id).inserted else {
                throw GameConfigurationError.duplicateCollectionId(perk.id)
            }
            guard perk.dailyBonusChips >= 0 else {
                throw GameConfigurationError.negativeDailyBonus(
                    collectionId: perk.id,
                    value: perk.dailyBonusChips
                )
            }
            guard perk.forageCooldownFactor.isFinite, perk.forageCooldownFactor >= 0 else {
                throw GameConfigurationError.invalidCooldownFactor(
                    collectionId: perk.id,
                    value: perk.forageCooldownFactor
                )
            }
            for adjustment in perk.weightAdjustments {
                let value = adjustment.operation.value
                guard value.isFinite, value >= 0 else {
                    throw GameConfigurationError.invalidWeight(
                        collectionId: perk.id,
                        kind: adjustment.kind.rawValue,
                        value: value
                    )
                }
            }
            if let reroll = perk.reroll {
                try Self.requireProbability(reroll.probability, id: perk.id, setting: "the reroll chance")
                guard !reroll.kinds.isEmpty else {
                    throw GameConfigurationError.emptyRerollTrigger(collectionId: perk.id)
                }
            }
            if let extra = perk.extraFind {
                try Self.requireProbability(extra.probability, id: perk.id, setting: "the extra-find chance")
            }
        }
        self.ordered = perks
    }

    /// The validated-by-construction path, for the empty set.
    private init(validated: [CollectionPerk]) {
        self.ordered = validated
    }

    // MARK: - Public Methods

    /// No perks at all. The ordinary configuration, not a degraded one (`ADOPT-3`).
    ///
    /// Named `empty` rather than `none` on purpose. A static member called `none`
    /// on a struct collides with `Optional.none` at a comparison site: `perks ==
    /// .none` compiles, resolves to the optional, and is always false. That shipped
    /// once, as four always-false comparisons nobody read the warnings for.
    public static let empty = GamePerks(validated: [])

    /// Whether any perk is configured at all.
    public var isEmpty: Bool { ordered.isEmpty }

    /// The perks these holdings earn, in configuration order.
    ///
    /// Configuration order, not holdings order: see the type's own note. This is
    /// the single place that decides the sequence, so there is one thing to read
    /// when a replay disagrees with itself.
    ///
    /// Only what was **read as held**. A collection nobody could read earns
    /// nothing here, because granting a perk on a failed read hands somebody
    /// something they may never have owned, and the free gift is the half of
    /// this that cannot be taken back. What it must not do is pass for an
    /// answer: ``unresolved(for:)`` is the other half, and a caller settling
    /// anything a member cannot re-take later reads both (`PLAY-4` retired says
    /// a perk is not a promise, which is why the games keep dealing rather than
    /// stopping for one).
    public func active(for holdings: GameHoldings) -> [CollectionPerk] {
        ordered.filter { holdings.reading(of: $0.id) == .held }
    }

    /// The configured perks whose collection could not be read for this player,
    /// in configuration order.
    ///
    /// Empty means the perks are settled: every collection anybody configured
    /// was either held or not, and ``active(for:)`` is the whole answer. A
    /// non-empty list means the answer is short by these, and a caller deciding
    /// something a member cannot come back for tomorrow should wait rather than
    /// settle it.
    ///
    /// Only *configured* perks are named. A collection nobody could read and
    /// nobody wrote a perk for cannot change anything, and refusing over it
    /// would punish a host for a failure that costs their members nothing
    /// (`ADOPT-3`).
    public func unresolved(for holdings: GameHoldings) -> [CollectionPerk] {
        ordered.filter { holdings.reading(of: $0.id) == .unknown }
    }

    /// The configured perk for a collection id, or nil.
    public func perk(_ collectionId: String) -> CollectionPerk? {
        ordered.first { $0.id == collectionId }
    }

    // MARK: - Private Methods

    /// Whether an id is already in the shape operator configuration normalises to.
    ///
    /// Lowercase, and letters, digits or underscores only. The alphabet is
    /// Unicode's rather than ASCII's on purpose: a normaliser lowercases the name
    /// it was given and keeps whatever in it is a letter or a digit, so a
    /// collection called "Café" normalises to `café`, and refusing that would
    /// refuse a correctly configured server to buy a rule that only looked
    /// stricter. The alphabet is drawn from what a normaliser keeps rather than
    /// from what looks tidy, because a rule stricter than that only ever refuses
    /// somebody who did nothing wrong.
    ///
    /// Each character is judged by its first scalar, which is what
    /// `Character.isLetter` and `Character.isNumber` already do. A combining mark
    /// landing straight after a separator re-segments into one character that
    /// begins with that underscore, and reading the first scalar is what stops it
    /// from being read as punctuation and refused.
    private static func isNormalized(_ id: String) -> Bool {
        guard id.lowercased() == id else { return false }
        let underscore: Unicode.Scalar = "_"
        return id.allSatisfy { character in
            character.isLetter || character.isNumber || character.unicodeScalars.first == underscore
        }
    }

    /// Refuses a probability outside `0...1`, naming what to fix.
    private static func requireProbability(_ value: Double, id: String, setting: String) throws {
        guard value.isFinite, value >= 0, value <= 1 else {
            throw GameConfigurationError.invalidProbability(
                collectionId: id,
                setting: setting,
                value: value
            )
        }
    }
}
