import Foundation

/// Who a request is being made for.
///
/// Every reservation names one, and the parameter has **no default**. A
/// default would mean a host that forgot got the unrationed path in silence,
/// which is the whole guard bypassed by an omission; making each call site say
/// which side of the rule it is on is what puts the decision in the diff where
/// a reviewer sees it.
///
/// A closed set of two cases rather than a free string, so that which side a
/// call sits on is visible in review. A third case for work an operator
/// ordered was considered and dropped: that is the instance doing what the
/// operator asked, the operator's own budget is the one being spent, and every
/// spending surface is already behind the admin allowlist, so a third case
/// would add a decision for a host to get wrong without adding a rule.
public enum RequestCaller: Sendable, Hashable {

    /// Work done on behalf of one member, rationed to a share of the day.
    ///
    /// **The key is this instance's own.** Nothing that came from a chat
    /// account may be passed here: a host hands over the key its own store
    /// minted for that member. This layer cannot enforce that and says so
    /// rather than pretending otherwise, but the consequences are worth
    /// knowing. The set of possible callers is then bounded by the membership,
    /// a caller id cannot be forged from outside to buy a fresh allowance, and
    /// nothing below the chat boundary holds an identifier belonging to a
    /// person (HOST-2).
    ///
    /// The value is opaque here: it is never logged, never persisted by this
    /// layer, and never repeated in an error or a notice.
    case member(key: String)

    /// The instance's own work, which carries no share.
    ///
    /// A role sweep, a scheduled payout, a boot check and anything an operator
    /// ordered. **Deliberately not rationed**, and the reason is not
    /// convenience: a sweep is not a person, it cannot type fast, it is
    /// already bounded by its batch size and the interval between runs, and
    /// holding it to one member's share would break the product's main job in
    /// order to protect it.
    ///
    /// The job name is for a reader of the call site. This layer does nothing
    /// with it.
    case system(job: String)

    // MARK: - Public Methods

    /// The key a share is counted against, or nil for work that carries none.
    public var shareKey: String? {
        switch self {
        case .member(let key): return key
        case .system: return nil
        }
    }

    /// Whether this caller is held to a share of the day.
    public var isRationed: Bool { shareKey != nil }
}
