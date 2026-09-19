@preconcurrency import Foundation

/// The names a store reports rows under.
///
/// Shared by every backend so a forgetting reports the same tables whichever
/// one is running, and so the conformance suite can assert the counts rather
/// than accept whatever spelling a backend happens to use.
public enum StoreTable: Sendable {

    /// The directory: one row per member, holding the minted key.
    public static let members = "members"

    /// The accounts members proved.
    public static let accounts = "accounts"

    /// The sweep guard's baseline.
    public static let roleBaseline = "role_baseline"

    /// The reserve's own state, one row per stream plus the scalars.
    public static let reserveState = "reserve_state"

    /// One row per epoch of per stream.
    public static let reserveEpochs = "reserve_epochs"

    /// The day's request count.
    public static let requestBudget = "request_budget"
}
