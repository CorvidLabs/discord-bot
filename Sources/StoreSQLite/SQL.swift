@preconcurrency import Foundation

/// A statement, which can only ever be a literal written in this source file.
///
/// The whole type exists for what it refuses. `StringLiteralType` is
/// `StaticString`, and nothing else can become an `SQL`, so
/// `"SELECT * FROM members WHERE external_id = '\(id)'"` is a **compile error**
/// rather than a review comment. There is no `init(_ text: String)` and there
/// is no interpolation, anywhere, at any privilege level.
///
/// Values reach a statement through `?` placeholders and ``SQLValue`` only.
/// That is not a convention this package tries to remember; it is the only
/// thing the type system will let anybody do.
public struct SQL: Sendable, Hashable, ExpressibleByStringLiteral {

    // MARK: - Properties

    /// The literal, as text for the C interface.
    public let text: String

    // MARK: - Initializers

    public typealias StringLiteralType = StaticString
    public typealias ExtendedGraphemeClusterLiteralType = StaticString
    public typealias UnicodeScalarLiteralType = StaticString

    /// - Parameter value: A literal written in the source. Nothing else
    ///   compiles.
    public init(stringLiteral value: StaticString) {
        self.text = value.description
    }
}
