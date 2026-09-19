import Foundation

/// Something that can move value, and the account it moves it from.
///
/// A protocol declared here rather than `Reserve`'s ``ReservePayer`` taken
/// directly, because this target depends on `Gating`, `Chain` and `Store` and
/// on nothing else (RT-001), and reaching through `Store` for a module this
/// target does not declare would be the graph claim quietly broken. An adapter
/// that holds a real payer conforms to this and is a target of its own, which
/// is an edge in the manifest and a line in the disclosure document.
///
/// **Nothing in this package conforms to it.** That is the point: a build that
/// can spend is a build with a target that did, which somebody adds on purpose
/// and somebody else reads.
public protocol SpendingPayer: Sendable {

    /// What this payer is, for the banner. Not a secret and not derived from
    /// one: the name of the mechanism, such as the module that signs.
    var payerName: String { get }

    /// The public account it signs for.
    ///
    /// Public by construction, and the one fact derived from a key that the
    /// report prints, because an operator has to be able to check they funded
    /// the right account (CATALOG-6.a).
    var publicAccount: String { get }
}

/// Whether this build can move anything, as a fact about the composition.
///
/// **Never a reading of the settings.** There is no code path from
/// ``Settings`` to this value: no variable is consulted, and the test for it
/// sets every catalogue variable to a truthy and then to a falsy value and
/// asserts the capability is exactly what the caller passed (BUILD-3,
/// BUILD-3.a).
///
/// The consequence is that there is no `TEST_MODE`, no `DRY_RUN` and no
/// `SAFE_MODE` here, and there never can be one that means anything. The bot
/// this was ported from carries a note in its own documentation saying its
/// test mode is not a money switch; a project that has to carry such a note
/// has already failed to say so in software, and the note is load-bearing
/// only until somebody new does not read it.
public enum SpendCapability: Sendable {

    /// No payer is compiled into this build, so nothing can be moved.
    case cannotSpend

    /// A payer is compiled in, and this is it.
    case canSpend(any SpendingPayer)

    // MARK: - Public Methods

    /// The first line of every start (BUILD-3.b, SPEND-6.c, HOST-7.a).
    ///
    /// Written by the report rather than by a logger, so no level, filter or
    /// destination can remove it.
    public var banner: String {
        switch self {
        case .cannotSpend:
            return "This build cannot move anything: no payer is compiled in, and no setting "
                + "can add one."
        case .canSpend(let payer):
            return "This build can sign. Payer: \(payer.payerName). It signs for "
                + "\(payer.publicAccount)."
        }
    }

    /// Whether anything in this build could move value.
    public var canSign: Bool {
        switch self {
        case .cannotSpend: return false
        case .canSpend: return true
        }
    }
}
