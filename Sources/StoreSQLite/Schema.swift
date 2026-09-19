@preconcurrency import Foundation

/// Every step of the schema, in order.
///
/// Small on purpose. This is the smallest store after which somebody can run
/// the bot, prove an account and be given a role, plus the two seams the engine
/// declared before any of this existed. What is deliberately absent is listed
/// in the module's spec rather than half built here.
internal enum Schema {

    // MARK: - Properties

    /// Every migration this build ships.
    internal static let migrations: [SchemaMigration] = [
        SchemaMigration(
            version: 1,
            name: "members and the accounts they proved",
            up: [
                // The directory. One row per member, and the only place the key
                // this instance drew and the chat account id appear together:
                // delete the row and every other mention of the key refers to
                // nobody.
                """
                CREATE TABLE members (
                    member_key TEXT PRIMARY KEY NOT NULL
                        CHECK (typeof(member_key) = 'text' AND length(member_key) = 32),
                    external_id TEXT NOT NULL UNIQUE,
                    first_seen_at INTEGER NOT NULL
                        CHECK (typeof(first_seen_at) = 'integer')
                )
                """,
                // Two balance halves, not one. Verification reads the account
                // that just signed, so a ladder decided from that alone demotes
                // somebody for linking an empty second wallet.
                //
                // The cascade is the forgetting. A table added in two years is
                // forgotten by the migration that creates it rather than by
                // somebody remembering to add a line somewhere else, and a test
                // reads the schema back and asserts every table carrying a
                // member key declares it.
                """
                CREATE TABLE accounts (
                    address TEXT PRIMARY KEY NOT NULL,
                    member_key TEXT NOT NULL
                        CHECK (typeof(member_key) = 'text' AND length(member_key) = 32)
                        REFERENCES members (member_key) ON DELETE CASCADE,
                    proven_at INTEGER NOT NULL
                        CHECK (typeof(proven_at) = 'integer'),
                    direct_base_units BLOB NOT NULL
                        CHECK (typeof(direct_base_units) = 'blob'
                            AND length(direct_base_units) = 8),
                    liquidity_base_units BLOB NOT NULL
                        CHECK (typeof(liquidity_base_units) = 'blob'
                            AND length(liquidity_base_units) = 8),
                    balances_read_at INTEGER
                        CHECK (balances_read_at IS NULL
                            OR typeof(balances_read_at) = 'integer')
                )
                """,
                "CREATE INDEX accounts_by_member ON accounts (member_key)",
                // One row, ever. The check is what stops a second baseline
                // quietly becoming the one a sweep reads.
                """
                CREATE TABLE role_baseline (
                    id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                    verified_member_count INTEGER NOT NULL
                        CHECK (typeof(verified_member_count) = 'integer'
                            AND verified_member_count >= 0),
                    recorded_at INTEGER NOT NULL
                        CHECK (typeof(recorded_at) = 'integer')
                )
                """
            ],
            down: [
                "DROP TABLE role_baseline",
                "DROP INDEX accounts_by_member",
                "DROP TABLE accounts",
                "DROP TABLE members"
            ]
        ),
        SchemaMigration(
            version: 2,
            name: "the payout ledger and the day's request count",
            up: [
                """
                CREATE TABLE reserve_state (
                    id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                    schedule_id TEXT,
                    activated_at INTEGER
                        CHECK (activated_at IS NULL OR typeof(activated_at) = 'integer')
                )
                """,
                // One row per stream rather than one blob for the lot, so an
                // operator reading the file in something that is not this
                // project can see what each stream has spent.
                """
                CREATE TABLE reserve_streams (
                    stream_id TEXT PRIMARY KEY NOT NULL,
                    completed_epochs BLOB NOT NULL
                        CHECK (typeof(completed_epochs) = 'blob'
                            AND length(completed_epochs) = 8),
                    spent_base_units BLOB NOT NULL
                        CHECK (typeof(spent_base_units) = 'blob'
                            AND length(spent_base_units) = 8),
                    last_period_key TEXT
                )
                """,
                """
                CREATE TABLE reserve_epochs (
                    stream_id TEXT NOT NULL,
                    epoch BLOB NOT NULL
                        CHECK (typeof(epoch) = 'blob' AND length(epoch) = 8),
                    paid_base_units BLOB NOT NULL
                        CHECK (typeof(paid_base_units) = 'blob'
                            AND length(paid_base_units) = 8),
                    started_at INTEGER
                        CHECK (started_at IS NULL OR typeof(started_at) = 'integer'),
                    completed_at INTEGER
                        CHECK (completed_at IS NULL OR typeof(completed_at) = 'integer'),
                    PRIMARY KEY (stream_id, epoch)
                )
                """,
                // The claims are their own rows rather than three lists inside
                // the epoch row, and the reason is arithmetic. A runner saves
                // the whole record once per recipient, so lists in the row mean
                // rewriting a growing value several thousand times and flushing
                // every version of it to the disk: hundreds of megabytes for one
                // epoch, and quadratic in the number paid. A payout that is
                // correct and takes two minutes gets killed by an operator's
                // timeout half way through, which is the half-finished payout
                // the whole design exists to prevent, arriving by the back door.
                //
                // The key is the position, not the value. A record carries
                // lists, and a list may hold the same value twice; keyed by the
                // value, such a list came back shorter and reordered rather
                // than being refused, which is a public save and load pair
                // disagreeing in silence.
                //
                // No cascade to `members` on purpose, and the column is not
                // called `member_key`. A slot already paid has to stay recorded
                // after the member is forgotten, or a resumed run pays it again.
                // What makes that safe is that the value is a key this instance
                // drew rather than anything that came from a person.
                """
                CREATE TABLE reserve_epoch_claims (
                    stream_id TEXT NOT NULL,
                    epoch BLOB NOT NULL
                        CHECK (typeof(epoch) = 'blob' AND length(epoch) = 8),
                    kind INTEGER NOT NULL CHECK (kind IN (0, 1, 2)),
                    value TEXT NOT NULL,
                    ordinal INTEGER NOT NULL
                        CHECK (typeof(ordinal) = 'integer' AND ordinal >= 0),
                    PRIMARY KEY (stream_id, epoch, kind, ordinal),
                    FOREIGN KEY (stream_id, epoch)
                        REFERENCES reserve_epochs (stream_id, epoch) ON DELETE CASCADE
                )
                """,
                """
                CREATE TABLE request_budget (
                    id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                    used_requests BLOB NOT NULL
                        CHECK (typeof(used_requests) = 'blob'
                            AND length(used_requests) = 8),
                    day_start INTEGER NOT NULL
                        CHECK (typeof(day_start) = 'integer')
                )
                """
            ],
            down: [
                "DROP TABLE request_budget",
                "DROP TABLE reserve_epoch_claims",
                "DROP TABLE reserve_epochs",
                "DROP TABLE reserve_streams",
                "DROP TABLE reserve_state"
            ]
        )
    ]

    /// What kind of thing a claim row records.
    ///
    /// Numbered rather than named so the column is small and the values cannot
    /// drift with a rename. The order is a compatibility surface: adding a kind
    /// means adding a number, never renumbering.
    internal enum ClaimKind: Int64, Sendable, CaseIterable {

        /// An account that has been paid this epoch.
        case account = 0

        /// A person who has been paid this epoch.
        case recipient = 1

        /// A holding that has been paid for this epoch.
        case holding = 2
    }
}
