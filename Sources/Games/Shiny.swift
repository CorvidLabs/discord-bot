import Foundation

/// The eight things a forage can come back with, cheapest first.
///
/// Declaration order is the JavaScript original's and the weight table is read
/// positionally by ``GameShuffle/pickIndex(_:using:)``, so reordering these cases
/// would change what every stored seed finds.
public enum ShinyKind: String, Sendable, Codable, CaseIterable, Equatable {
    /// The commonest find, and the first rung of the nest ladder.
    case twig
    /// Common, worth a little more than a twig.
    case feather
    /// Common.
    case pebble
    /// The cheapest find that pays chips.
    case beetle
    /// Uncommon.
    case glass
    /// Rare.
    case silver
    /// The rarest of the ordinary finds.
    case gold
    /// Unreachable at its base weight. See ``Shiny/baseWeight(_:)``.
    case rune
}

/// What one kind of junk is worth: its face, its nest points, and its chip
/// sprinkle.
///
/// Nest points and chips are deliberately different numbers. Points build a pouch
/// score that never leaves the pouch; chips are the playing score, and common junk
/// pays none of them so foraging cannot be farmed for a pile.
public struct ShinyMeta: Sendable, Equatable {

    // MARK: - Properties

    /// Name on a card.
    public let label: String

    /// Plural of ``label``, for a sentence that needs one.
    ///
    /// Stored rather than derived. The original appended an `s` to every label and
    /// told members they needed "3 glasss", which is the kind of thing that only
    /// gets noticed after it has been read a thousand times.
    public let labelPlural: String

    /// Nest points per item, before the nest-level multiplier.
    public let value: Int

    /// Chips a forage pays when this is the find. Zero for common junk.
    public let chips: Int

    // MARK: - Initializers

    /// - Parameters:
    ///   - label: Name on a card.
    ///   - labelPlural: Plural. Defaults to `label` plus `s`.
    ///   - value: Nest points per item.
    ///   - chips: Chips a forage pays for this find.
    public init(label: String, labelPlural: String? = nil, value: Int, chips: Int) {
        self.label = label
        self.labelPlural = labelPlural ?? "\(label)s"
        self.value = value
        self.chips = chips
    }
}

/// One player's pouch: what they have found, how high the nest is, and when they
/// may forage again.
///
/// The inventory is keyed by ``ShinyKind/rawValue`` rather than by the enum so the
/// whole state encodes to a plain JSON object, and a kind added later reads back as
/// absent instead of failing the decode.
public struct ShinyState: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Counts keyed by ``ShinyKind/rawValue``. A missing key is zero.
    public var inventory: [String: Int]

    /// Nest height, 1 through ``Shiny/maxNestLevel``. Multiplies the pouch score.
    ///
    /// "Nest" is the ladder and only the ladder. The chips a player spends and wins
    /// are chips, and they are never called this.
    public var nestLevel: Int

    /// When the last forage landed. Nil means they have never foraged.
    public var lastForageAt: Date?

    /// What the last forage turned up. Nil until the first find.
    public var lastFind: ShinyKind?

    /// The line a card shows under the find: perks, or why a forage was refused.
    public var lastBonus: String?

    /// Seconds between forages.
    ///
    /// Carried on the state rather than recomputed, so a perk can shorten it per
    /// player and a stored pouch still knows its own wait.
    public var cooldown: TimeInterval

    // MARK: - Initializers

    /// - Parameters:
    ///   - inventory: Counts keyed by ``ShinyKind/rawValue``.
    ///   - nestLevel: Nest height.
    ///   - lastForageAt: When the last forage landed.
    ///   - lastFind: What it turned up.
    ///   - lastBonus: The line under the find.
    ///   - cooldown: Seconds between forages.
    public init(
        inventory: [String: Int],
        nestLevel: Int,
        lastForageAt: Date? = nil,
        lastFind: ShinyKind? = nil,
        lastBonus: String? = nil,
        cooldown: TimeInterval
    ) {
        self.inventory = inventory
        self.nestLevel = nestLevel
        self.lastForageAt = lastForageAt
        self.lastFind = lastFind
        self.lastBonus = lastBonus
        self.cooldown = cooldown
    }

    // MARK: - Public Methods

    /// How many of `kind` are in the pouch. A kind never found reads as zero.
    public func count(_ kind: ShinyKind) -> Int {
        inventory[kind.rawValue] ?? 0
    }
}

/// Shiny: forage junk, build a nest out of it.
///
/// Every entry point is a pure reducer. ``forage(_:context:)`` takes the context
/// `inout` because finding something advances a seeded stream.
///
/// The chip accounting is worth stating twice: a forage pays the chips of the kind
/// it settled on and nothing else. A perk's extra find goes in the pouch without
/// paying, and raising the nest never moves chips at all.
public enum Shiny: Sendable {

    // MARK: - Properties

    /// Label, nest points, and chip sprinkle per kind.
    ///
    /// Chips only start at beetle: twigs, feathers and pebbles are the bulk of
    /// every pouch, and paying for them would make foraging a chip faucet.
    public static let meta: [ShinyKind: ShinyMeta] = [
        .twig: ShinyMeta(label: "Twig", value: 1, chips: 0),
        .feather: ShinyMeta(label: "Feather", value: 3, chips: 0),
        .pebble: ShinyMeta(label: "Pebble", value: 2, chips: 0),
        .beetle: ShinyMeta(label: "Beetle", value: 5, chips: 2),
        .glass: ShinyMeta(label: "Glass", labelPlural: "glass", value: 8, chips: 4),
        .silver: ShinyMeta(label: "Silver", labelPlural: "silver", value: 15, chips: 10),
        .gold: ShinyMeta(label: "Gold", labelPlural: "gold", value: 40, chips: 25),
        .rune: ShinyMeta(label: "Rune shard", value: 24, chips: 12)
    ]

    /// What each nest level above the first costs, in junk.
    ///
    /// The ladder is spent, not banked: raising the nest burns the ingredients out
    /// of the pouch, so a high nest is a choice to stop hoarding score.
    public static let nestCosts: [(level: Int, cost: [ShinyKind: Int])] = [
        (level: 2, cost: [.twig: 8]),
        (level: 3, cost: [.twig: 12, .feather: 6]),
        (level: 4, cost: [.twig: 16, .feather: 8, .pebble: 6]),
        (level: 5, cost: [.twig: 20, .feather: 10, .glass: 3, .silver: 1])
    ]

    /// The top of the ladder. A nest here refuses to rise and drops the upgrade
    /// action.
    public static let maxNestLevel: Int = 5

    /// Card title, identical in every state so an edited message stays the same
    /// card.
    private static let title: String = "Shiny"

    /// The one colour Shiny uses: nothing here wins or loses, so nothing changes
    /// tone.
    private static let cardColor: Int = 0x243028

    private static let forageButtonId: String = "ng_shiny_forage"
    private static let upgradeButtonId: String = "ng_shiny_upgrade"

    // MARK: - Public Methods

    /// An empty pouch at nest one, cooling down at `cooldown` seconds.
    ///
    /// Every kind is written in at zero rather than left out, so a fresh pouch
    /// encodes to the same shape as one that has been foraged and spent back down.
    public static func empty(cooldown: TimeInterval) -> ShinyState {
        var inventory: [String: Int] = [:]
        for kind in ShinyKind.allCases {
            inventory[kind.rawValue] = 0
        }
        return ShinyState(
            inventory: inventory,
            nestLevel: 1,
            lastForageAt: nil,
            lastFind: nil,
            lastBonus: nil,
            cooldown: cooldown
        )
    }

    /// The pouch's worth: every item at its nest points, multiplied by the nest
    /// level.
    ///
    /// The multiplier is why the ladder is worth climbing at all: the same junk is
    /// worth five times as much in a level five nest as in a fresh one.
    public static func nestScore(_ state: ShinyState) -> Int {
        var sum = 0
        for kind in ShinyKind.allCases {
            sum += state.count(kind) * info(kind).value
        }
        return sum * state.nestLevel
    }

    /// Forage once: roll a find, apply the perks the player's collections earn,
    /// and pay the find's chips.
    ///
    /// **The draw order below is the game.** It is a fixed sequence of five stages,
    /// and it does not change with which perks a host has configured or which
    /// collections a player holds:
    ///
    /// 1. **The find.** One weighted draw, against the loot table the player's
    ///    perks produce.
    /// 2. **Rerolls,** walking the active perks in configuration order. A perk with
    ///    a reroll spends a coin when and only when the current find is one of its
    ///    trigger kinds, and spends it whether or not it lands. A perk with no
    ///    reroll spends nothing.
    /// 3. **The find goes in the pouch.** No draw.
    /// 4. **Free finds,** in the same order. No draw.
    /// 5. **Extra finds,** in the same order. A perk with an extra find spends a
    ///    coin on every forage, landing or not, and one more draw when it lands.
    ///
    /// Two things about that are easy to "tidy up" and must not be. Skipping a
    /// draw because its outcome turned out not to be used consumes the stream
    /// differently, so the same seed stops replaying and every table dealt
    /// afterwards diverges. And walking the perks in the player's holdings order
    /// rather than the host's configuration order would make the sequence depend
    /// on a `Set`'s iteration, which is not a thing a replay can rely on.
    ///
    /// A player who holds nothing, and a host who has configured no perks at all,
    /// spend exactly one draw here: stages 2, 4 and 5 have nothing to walk
    /// (`ADOPT-3`).
    ///
    /// A forage inside the cooldown is refused rather than queued: the pouch comes
    /// back untouched with only ``ShinyState/lastBonus`` replaced by the wait, and
    /// no chips and no draws move. Perks shorten the wait elsewhere; they never
    /// skip it.
    ///
    /// - Parameters:
    ///   - state: The pouch as it stands.
    ///   - context: Clock, player, perks and the seeded stream.
    /// - Returns: The pouch after the forage and the chips the find paid.
    public static func forage(
        _ state: ShinyState,
        context: inout GameContext
    ) -> ReduceResult<ShinyState> {
        let waiting = remainingCooldown(state, now: context.now)
        if waiting > 0 {
            var cooling = state
            // Whole seconds rounded up: telling somebody to wait "0s" when they
            // still have most of a second left reads as a broken button.
            cooling.lastBonus = "Ready again in \(Int(waiting.rounded(.up)))s."
            return ReduceResult(state: cooling, chipDelta: 0)
        }

        let perks = context.activePerks
        // Hoisted out of the roll: the table is a pure function of the active
        // perks, so computing it once is the same table every roll would have
        // built for itself.
        let table = weights(perks: perks)

        // Stage 1: the find.
        var kind = rollKind(weights: table, context: &context)
        var bonus: String?

        // Stage 2: rerolls.
        for perk in perks {
            guard let reroll = perk.reroll, reroll.kinds.contains(kind) else { continue }
            let coin = context.rng.next()
            if coin < reroll.probability {
                kind = rollKind(weights: table, context: &context)
                bonus = joined(bonus, "\(perk.name) reroll.")
            }
        }

        // Stage 3: the find goes in the pouch.
        var inventory = state.inventory
        add(kind, to: &inventory)

        // Stage 4: free finds.
        for perk in perks {
            guard let free = perk.freeFind else { continue }
            add(free, to: &inventory)
            bonus = joined(bonus, "\(perk.name) tucked in a \(info(free).label.lowercased()).")
        }

        // Stage 5: extra finds.
        for perk in perks {
            guard let extra = perk.extraFind else { continue }
            let coin = context.rng.next()
            if coin < extra.probability {
                let found = rollKind(weights: table, context: &context)
                add(found, to: &inventory)
                bonus = joined(bonus, "\(perk.name) found \(info(found).label).")
            }
        }

        var found = state
        found.inventory = inventory
        found.lastForageAt = context.now
        found.lastFind = kind
        found.lastBonus = bonus
        return ReduceResult(state: found, chipDelta: info(kind).chips)
    }

    /// Spend the next rung's ingredients to raise the nest.
    ///
    /// A maxed nest and a short pouch both come back as the state that went in with
    /// a note saying why, so a mistaken tap costs nothing. Ingredients are checked
    /// in kind order and the first one short is the one named, which keeps the note
    /// stable rather than letting a dictionary's ordering pick the message.
    ///
    /// - Parameter state: The pouch as it stands.
    /// - Returns: The raised pouch, or the same pouch and the reason it did not
    ///   rise. Never a chip movement: the ladder is bought with junk.
    public static func upgrade(_ state: ShinyState) -> ReduceResult<ShinyState> {
        guard let next = nestCosts.first(where: { $0.level == state.nestLevel + 1 }) else {
            return ReduceResult(state: state, chipDelta: 0, note: "The nest is as high as it goes.")
        }
        for kind in ShinyKind.allCases {
            guard let needed = next.cost[kind] else { continue }
            if state.count(kind) < needed {
                return ReduceResult(
                    state: state,
                    chipDelta: 0,
                    note: "Need \(needed) \(info(kind).labelPlural.lowercased())."
                )
            }
        }
        var inventory = state.inventory
        for kind in ShinyKind.allCases {
            guard let needed = next.cost[kind] else { continue }
            inventory[kind.rawValue, default: 0] -= needed
        }
        var raised = state
        raised.inventory = inventory
        raised.nestLevel = next.level
        raised.lastBonus = "Nest rose to \(next.level)."
        return ReduceResult(state: raised, chipDelta: 0)
    }

    /// Seconds until the next forage is legal. Zero once it is, and for somebody
    /// who has never foraged.
    public static func remainingCooldown(_ state: ShinyState, now: Date) -> TimeInterval {
        guard let last = state.lastForageAt else { return 0 }
        return max(0, state.cooldown - now.timeIntervalSince(last))
    }

    /// Actions the pouch will accept.
    ///
    /// Forage is always offered: the reducer, not the button, is what enforces the
    /// cooldown, because a click can always arrive from a card that has since moved
    /// on.
    public static func legalActions(_ state: ShinyState) -> [String] {
        state.nestLevel < maxNestLevel ? ["forage", "upgrade"] : ["forage"]
    }

    /// The pouch as a card: pure data, mapped to a message by whatever drives it.
    ///
    /// The context is read-only here, because rendering never draws from the
    /// stream. It is taken for the clock, which decides whether the forage button
    /// is live.
    public static func card(_ state: ShinyState, context: GameContext) -> GameMessage {
        var find: String = "nothing yet"
        if let last = state.lastFind {
            find = info(last).label
        }
        let ready = remainingCooldown(state, now: context.now) == 0
        var pouch: [String] = []
        for kind in ShinyKind.allCases where state.count(kind) > 0 {
            pouch.append("\(info(kind).label) \(state.count(kind))")
        }
        var description = "Last find: **\(find)**. Nest level \(state.nestLevel). "
            + "Score \(nestScore(state))."
        if let bonus = state.lastBonus, !bonus.isEmpty {
            description += "\n\(bonus)"
        }
        return GameMessage(
            title: title,
            description: description,
            fields: [
                GameField(
                    name: "Pouch",
                    value: pouch.isEmpty ? "Empty." : pouch.joined(separator: " \u{00b7} ")
                )
            ],
            color: cardColor,
            buttons: [
                GameButton(
                    id: forageButtonId,
                    label: ready ? "Forage" : "Cooling down",
                    style: .primary,
                    disabled: !ready
                ),
                GameButton(id: upgradeButtonId, label: "Upgrade nest, spends junk", style: .secondary)
            ],
            footer: "What you find stays in the pouch. Nothing cashes out.",
            thumbnailUrl: context.player.holdings.pictureUrl
        )
    }

    /// Base odds per kind, in ``ShinyKind`` order.
    ///
    /// ``ShinyKind/rune`` is zero on purpose. It is unreachable until one of the
    /// host's collections sets a weight for it, which is what makes a locked find
    /// worth locking. Nothing in this package unlocks it, because nothing in this
    /// package knows what collections exist (`ADOPT-1.b`).
    public static func baseWeight(_ kind: ShinyKind) -> Double {
        switch kind {
        case .twig: return 40
        case .feather: return 22
        case .pebble: return 16
        case .beetle: return 10
        case .glass: return 7
        case .silver: return 3.5
        case .gold: return 1.5
        case .rune: return 0
        }
    }

    /// The odds a player actually forages on, after their perks adjust them.
    ///
    /// Adjustments are applied perk by perk in configuration order, and within a
    /// perk in the order the host wrote them, so a mix of multiplies, adds and sets
    /// means one thing rather than whatever a hash order produced. Returned in
    /// ``ShinyKind`` order, because the picker reads it positionally.
    ///
    /// - Parameter perks: The perks the player's holdings earn, already filtered
    ///   and in configuration order.
    /// - Returns: One weight per kind, in ``ShinyKind`` order.
    public static func weights(perks: [CollectionPerk]) -> [Double] {
        var table: [ShinyKind: Double] = [:]
        for kind in ShinyKind.allCases {
            table[kind] = baseWeight(kind)
        }
        for perk in perks {
            for adjustment in perk.weightAdjustments {
                let current = table[adjustment.kind] ?? 0
                switch adjustment.operation {
                case .multiply(let factor):
                    table[adjustment.kind] = current * factor
                case .add(let amount):
                    table[adjustment.kind] = current + amount
                case .set(let value):
                    table[adjustment.kind] = value
                }
            }
        }
        return ShinyKind.allCases.map { table[$0] ?? 0 }
    }

    // MARK: - Private Methods

    /// ``meta`` without the optional a dictionary lookup hands back.
    ///
    /// Every kind has an entry, so the fallback is unreachable. It is there so a
    /// kind added to the enum cannot trap a card that is only trying to draw
    /// itself.
    private static func info(_ kind: ShinyKind) -> ShinyMeta {
        meta[kind] ?? ShinyMeta(label: kind.rawValue, value: 0, chips: 0)
    }

    /// One weighted find, spending exactly one draw.
    private static func rollKind(weights: [Double], context: inout GameContext) -> ShinyKind {
        let index = GameShuffle.pickIndex(weights, using: &context.rng)
        let kinds = ShinyKind.allCases
        // The picker always answers inside the array it was handed; the fallback
        // only guards a future empty weight table.
        return kinds.indices.contains(index) ? kinds[index] : .twig
    }

    /// Put one of `kind` in the pouch.
    private static func add(_ kind: ShinyKind, to inventory: inout [String: Int]) {
        inventory[kind.rawValue, default: 0] += 1
    }

    /// Bonus lines read as one run of sentences, so a later perk appends to an
    /// earlier one.
    private static func joined(_ existing: String?, _ line: String) -> String {
        guard let existing = existing, !existing.isEmpty else { return line }
        return "\(existing) \(line)"
    }
}
