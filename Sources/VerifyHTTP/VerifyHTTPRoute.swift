@preconcurrency import Foundation

/// The six things this surface answers.
///
/// **Two of them are the obligation and four are what the obligation costs.**
/// The page and the submission are what a host owes. The script and the
/// stylesheet are separate routes because the page carries no inline script,
/// which is what lets the content security policy name no source but this
/// origin. The card and the connect exist because of where the session id
/// travels: it reaches the page in the fragment, which browsers never send to
/// a server, so the server cannot know which session a page load belongs to
/// and cannot render the member's name into the page. The page asks for it,
/// with the id in a request body.
public enum VerifyHTTPRoute: String, Sendable, Equatable, CaseIterable {

    /// The page a member's wallet signs against.
    case page

    /// The page's script.
    case script

    /// The page's stylesheet.
    case stylesheet

    /// Who this session belongs to, its code and its expiry.
    case card

    /// The address a wallet connected, recorded once.
    case connect

    /// The signed blob.
    case submit
}

/// What to do about one request, before anything reads a body.
public enum VerifyRouteMatch: Sendable, Equatable {

    /// It is one of this surface's routes.
    case matched(VerifyHTTPRoute)

    /// The path is one of this surface's routes and the method is not.
    case methodNotAllowed

    /// Nothing here serves that.
    case unknown
}

/// Where each route lives, and which method reaches it.
public enum VerifyRouting: Sendable {

    // MARK: - Properties

    /// The page.
    public static let pagePath: String = "/verify"

    /// The page's script.
    public static let scriptPath: String = "/verify/app.js"

    /// The page's stylesheet.
    public static let stylesheetPath: String = "/verify/app.css"

    /// Who this session belongs to.
    public static let cardPath: String = "/verify/card"

    /// The address a wallet connected.
    public static let connectPath: String = "/verify/connect"

    /// The signed blob.
    public static let submitPath: String = "/verify/submit"

    // MARK: - Public Methods

    /// The path a route is served at.
    ///
    /// - Parameter route: The route.
    public static func path(of route: VerifyHTTPRoute) -> String {
        switch route {
        case .page: return pagePath
        case .script: return scriptPath
        case .stylesheet: return stylesheetPath
        case .card: return cardPath
        case .connect: return connectPath
        case .submit: return submitPath
        }
    }

    /// The method a route is reached with.
    ///
    /// The three that carry a session id are `POST`, and that is the rule
    /// rather than a convention: a bearer credential in a `GET` is a bearer
    /// credential in the request line, and the request line is what every
    /// log on the way writes down.
    ///
    /// - Parameter route: The route.
    public static func method(of route: VerifyHTTPRoute) -> String {
        switch route {
        case .page, .script, .stylesheet: return "GET"
        case .card, .connect, .submit: return "POST"
        }
    }

    /// Whether a route carries a session id in its body.
    ///
    /// - Parameter route: The route.
    public static func carriesSessionIdentifier(_ route: VerifyHTTPRoute) -> Bool {
        switch route {
        case .page, .script, .stylesheet: return false
        case .card, .connect, .submit: return true
        }
    }

    /// What to do about one request.
    ///
    /// - Parameters:
    ///   - method: The method, as it arrived.
    ///   - path: The path, with any query string already taken off.
    public static func match(method: String, path: String) -> VerifyRouteMatch {
        guard let route = VerifyHTTPRoute.allCases.first(where: { self.path(of: $0) == path }) else {
            return .unknown
        }
        guard self.method(of: route) == method else { return .methodNotAllowed }
        return .matched(route)
    }
}
