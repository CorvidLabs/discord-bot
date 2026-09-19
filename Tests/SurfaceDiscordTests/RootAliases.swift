import Runtime

/// Names for two composition-root types that the chat surface's own module
/// also has a version of.
///
/// `Runtime` and `Surface` each declare a `HealthState`, and the adapter's
/// tests need both modules, so an unqualified name is ambiguous there.
/// Qualifying it does not work either: `Runtime.HealthState` resolves the
/// first component to the `Runtime` struct inside that module rather than to
/// the module. This file imports one of the two and nothing else, so the
/// names here are unambiguous, and everywhere else says which it means.
internal typealias RootHealthListener = HealthListener

/// The composition root's health state, under a name that says whose it is.
internal typealias RootHealthState = HealthState
