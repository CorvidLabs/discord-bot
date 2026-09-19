import Foundation

/// A perk configuration that refuses to exist, and why.
///
/// Every case names the collection and the setting to fix. A host finds out they
/// have set this up wrongly when they start the process, not when a member's forage
/// behaves oddly three weeks later (`ADOPT-2`).
public enum GameConfigurationError: Error, LocalizedError, Sendable, Equatable {
    /// A perk was configured with a blank collection id, so nothing could ever
    /// match it.
    case emptyCollectionId

    /// A collection id with whitespace around it.
    ///
    /// Refused rather than trimmed. The id is matched against a player's holdings
    /// exactly as it is written, so a padded one is structurally valid, raises
    /// nothing, and can never match anything; trimming it here would instead be a
    /// guess at which of the two spellings the rest of the host's configuration
    /// uses.
    case paddedCollectionId(collectionId: String)

    /// A collection id that is not in the form operator configuration normalises
    /// ids to: lowercase, letters, digits and underscores only.
    ///
    /// Refused rather than normalised here. The ids a host writes down are read
    /// once and normalised before the rest of the product matches on them, so a
    /// host who configures both sides from the same variable would otherwise hand
    /// a perk `Founders Pass` while every holding says `founders_pass`. That perk
    /// is structurally perfect, raises nothing, and never fires. Normalising it
    /// here instead would be this module inventing a transform it cannot check
    /// against the one that actually ran.
    case unnormalizedCollectionId(collectionId: String)

    /// Two perks claim the same collection id.
    ///
    /// Refused rather than merged or last-wins, because either resolution is a
    /// guess at which of two half-written perks the host meant.
    case duplicateCollectionId(String)

    /// A daily bonus below zero, which would take chips away for holding something.
    case negativeDailyBonus(collectionId: String, value: Int)

    /// A cooldown factor that is negative or not a number.
    case invalidCooldownFactor(collectionId: String, value: Double)

    /// A loot weight that is negative or not a number.
    case invalidWeight(collectionId: String, kind: String, value: Double)

    /// A probability outside `0...1`, or not a number.
    case invalidProbability(collectionId: String, setting: String, value: Double)

    /// A reroll perk with nothing that triggers it, which spends no draw and does
    /// nothing, and is therefore always a typo.
    case emptyRerollTrigger(collectionId: String)

    /// What went wrong, and which setting to change.
    public var errorDescription: String? {
        switch self {
        case .emptyCollectionId:
            return "A collection perk has a blank id. Give it the collection id it applies to."
        case .paddedCollectionId(let id):
            return "Collection id '\(id)' has whitespace around it. "
                + "Ids are matched exactly, so a padded one matches nothing."
        case .unnormalizedCollectionId(let id):
            return "Collection id '\(id)' is not normalised. Write it in lowercase with nothing but "
                + "letters, digits and underscores, the way the configuration these ids come from "
                + "writes them, or it will match no holding."
        case .duplicateCollectionId(let id):
            return "Two collection perks use the id '\(id)'. Ids must be unique."
        case .negativeDailyBonus(let id, let value):
            return "Collection '\(id)' has a daily bonus of \(value). It must be zero or more."
        case .invalidCooldownFactor(let id, let value):
            return "Collection '\(id)' has a forage cooldown factor of \(value). "
                + "It must be a finite number of zero or more."
        case .invalidWeight(let id, let kind, let value):
            return "Collection '\(id)' sets the '\(kind)' loot weight to \(value). "
                + "It must be a finite number of zero or more."
        case .invalidProbability(let id, let setting, let value):
            return "Collection '\(id)' sets \(setting) to \(value). It must be between 0 and 1."
        case .emptyRerollTrigger(let id):
            return "Collection '\(id)' has a reroll with no kinds that trigger it. "
                + "List the kinds it should reroll, or remove the reroll."
        }
    }
}
