@preconcurrency import Foundation

/// Why a set of limits was refused.
public enum VerifyHTTPLimitsError: Error, Sendable, Equatable, CustomStringConvertible {

    /// A count was zero or less, which would refuse every request.
    case countNotPositive(field: String)

    /// A window was zero or less, so nothing would ever be counted.
    case windowNotPositive(field: String)

    // MARK: - Public Methods

    public var description: String {
        switch self {
        case .countNotPositive(let field):
            return "\(field) must be at least one"
        case .windowNotPositive(let field):
            return "\(field) must be longer than nothing"
        }
    }
}

/// What this surface will take, and from whom.
///
/// **The two per-source budgets are the whole community's, not one
/// member's.** Behind a reverse proxy every request arrives from the proxy's
/// address, so one source is every member at once, and this target
/// deliberately does not read a forwarded-for header to get around that: a
/// header a client sends is a header a client chooses, and honouring it turns
/// the per-source limit into a field an attacker fills in. So they are sized
/// for an instance rather than for a person: a number that reads like a
/// generous allowance for one member is, in the deployment this is written
/// for, the moment every member is refused at once, with nothing in the
/// answer to tell an operator it was somebody else who spent it.
///
/// The bound that holds a member is ``apiRequestsPerSession``, which counts
/// against a value only the member's own link produces. There is no
/// per-member bound on the page, the script and the stylesheet, and there
/// cannot be: the session id reaches the page in a fragment, which a browser
/// never sends, so the server cannot tell one page load from another.
public struct VerifyHTTPLimits: Sendable, Equatable {

    // MARK: - Properties

    /// Page, script and stylesheet requests one source may make in a window.
    ///
    /// A page load is three of them, every one of them is answered
    /// `no-store`, and a member who reloads is not doing anything wrong, so
    /// this is the loosest of the three. Behind a proxy it is the whole
    /// server's allowance for the window, so it is divided by three and then
    /// by however many members might be looking at once.
    public let assetRequestsPerSource: Int

    /// Card, connect and submit requests one source may make in a window.
    ///
    /// A verification is three of them, so behind a proxy this is the number
    /// of members who may be verifying in one window, times three, for the
    /// whole server. It is a flood stop rather than a member's allowance.
    public let apiRequestsPerSource: Int

    /// Card, connect and submit requests one session may make in a window.
    ///
    /// Larger than the three submissions a session is allowed, because the
    /// card and the connect are counted here too and a member who reloads the
    /// page spends one of each.
    public let apiRequestsPerSession: Int

    /// How long a window is.
    public let window: TimeInterval

    /// The most bytes a request body may be.
    public let maximumBodyBytes: Int

    /// What this surface takes unless an operator says otherwise.
    ///
    /// Six hundred assets and two hundred and forty calls a minute for the
    /// whole instance, and twelve calls a minute for one session. The first
    /// two are two hundred page loads and eighty verifications a minute,
    /// which no community this is for reaches and a flood passes in a
    /// second; sized that way because behind a proxy they are shared by
    /// everybody, and a per-member number put here stops the server. The
    /// third is the one that bounds a member: twelve is four page loads'
    /// worth of card, connect and submit, which is a member having a bad
    /// time rather than a member being stopped.
    public static let standard: VerifyHTTPLimits = VerifyHTTPLimits(
        uncheckedAssetRequestsPerSource: 600,
        apiRequestsPerSource: 240,
        apiRequestsPerSession: 12,
        window: 60,
        maximumBodyBytes: 8_192
    )

    // MARK: - Initializers

    /// - Parameters:
    ///   - assetRequestsPerSource: Page requests one source may make.
    ///   - apiRequestsPerSource: Calls one source may make.
    ///   - apiRequestsPerSession: Calls one session may make.
    ///   - window: How long a window is.
    ///   - maximumBodyBytes: The most bytes a request body may be.
    /// - Throws: ``VerifyHTTPLimitsError`` for a count or a window of
    ///   nothing, naming the one to fix, because an operator learning of it
    ///   from a member who cannot verify is the outcome this refusal exists
    ///   to avoid.
    public init(
        assetRequestsPerSource: Int,
        apiRequestsPerSource: Int,
        apiRequestsPerSession: Int,
        window: TimeInterval,
        maximumBodyBytes: Int
    ) throws {
        guard assetRequestsPerSource > 0 else {
            throw VerifyHTTPLimitsError.countNotPositive(field: "assetRequestsPerSource")
        }
        guard apiRequestsPerSource > 0 else {
            throw VerifyHTTPLimitsError.countNotPositive(field: "apiRequestsPerSource")
        }
        guard apiRequestsPerSession > 0 else {
            throw VerifyHTTPLimitsError.countNotPositive(field: "apiRequestsPerSession")
        }
        guard maximumBodyBytes > 0 else {
            throw VerifyHTTPLimitsError.countNotPositive(field: "maximumBodyBytes")
        }
        guard window > 0 else {
            throw VerifyHTTPLimitsError.windowNotPositive(field: "window")
        }
        self.assetRequestsPerSource = assetRequestsPerSource
        self.apiRequestsPerSource = apiRequestsPerSource
        self.apiRequestsPerSession = apiRequestsPerSession
        self.window = window
        self.maximumBodyBytes = maximumBodyBytes
    }

    /// The set this file chose itself, which has nothing to validate.
    private init(
        uncheckedAssetRequestsPerSource: Int,
        apiRequestsPerSource: Int,
        apiRequestsPerSession: Int,
        window: TimeInterval,
        maximumBodyBytes: Int
    ) {
        self.assetRequestsPerSource = uncheckedAssetRequestsPerSource
        self.apiRequestsPerSource = apiRequestsPerSource
        self.apiRequestsPerSession = apiRequestsPerSession
        self.window = window
        self.maximumBodyBytes = maximumBodyBytes
    }
}
