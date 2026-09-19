@preconcurrency import Foundation

/// A behaviour a store did not have.
///
/// The suite throws these rather than calling into a testing framework, so it
/// builds on any toolchain and any platform with nothing but Foundation and the
/// package itself in the graph. A test target turns one into a failure at its
/// own call site, which is where a reader wants the line number anyway.
public struct StoreConformanceFailure: Error, Sendable, Equatable, CustomStringConvertible {

    // MARK: - Properties

    /// The backend under test, as the caller named it.
    public let backend: String

    /// The behaviour that failed.
    public let behaviour: StoreConformance.Behaviour

    /// What was expected, and what was found instead.
    public let detail: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - backend: The backend under test.
    ///   - behaviour: The behaviour that failed.
    ///   - detail: What was expected, and what was found.
    public init(backend: String, behaviour: StoreConformance.Behaviour, detail: String) {
        self.backend = backend
        self.behaviour = behaviour
        self.detail = detail
    }

    // MARK: - Public Methods

    public var description: String {
        "\(backend) failed \(behaviour.rawValue): \(detail)"
    }
}
