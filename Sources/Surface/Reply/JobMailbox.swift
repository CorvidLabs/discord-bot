@preconcurrency import Foundation

/// Where a report goes when the interaction that asked for it has expired.
public enum JobFallback: Sendable, Equatable {

    /// A direct message to whoever ran the command.
    case directMessageToInvoker

    /// A message in a channel the operator named.
    case channel(id: String)

    /// Nowhere. The report is kept and read back from here, and that is all.
    ///
    /// Not a default anybody should choose, and deliberately not invented: an
    /// operator channel this package picked would be a channel somebody else
    /// chose (`ADOPT-6.a`).
    case none
}

/// Where one report is actually being sent.
public enum JobDelivery: Sendable, Equatable {

    /// The interaction is still live, so the report goes where it was asked
    /// for.
    case followUp(token: String, VisibleMessage)

    /// The token has expired; the invoker gets a direct message.
    case directMessage(externalId: String, VisibleMessage)

    /// The token has expired; the operator's channel gets it.
    case channel(id: String, VisibleMessage)

    /// The token has expired and there is nowhere configured. The record is
    /// kept; nobody is told.
    case undeliverable(JobId)
}

/// What is known about one long-running job.
public struct JobRecord: Sendable, Equatable {

    // MARK: - Properties

    /// The job.
    public let id: JobId

    /// Who asked for it.
    public let invokerExternalId: String

    /// The interaction token, good until ``deadline``.
    public let token: String

    /// When the token stops working.
    public let deadline: Date

    /// What happened, once it has. Nil while it is still running.
    public let report: VisibleMessage?

    // MARK: - Initializers

    /// - Parameters:
    ///   - id: The job.
    ///   - invokerExternalId: Who asked for it.
    ///   - token: The interaction token.
    ///   - deadline: When the token stops working.
    ///   - report: What happened, or nil while running.
    public init(
        id: JobId,
        invokerExternalId: String,
        token: String,
        deadline: Date,
        report: VisibleMessage? = nil
    ) {
        self.id = id
        self.invokerExternalId = invokerExternalId
        self.token = token
        self.deadline = deadline
        self.report = report
    }
}

/// Work that can outlive the interaction that started it.
///
/// Discord gives a handler fifteen minutes with an interaction token and then
/// the token is gone. A payout over a few hundred accounts, a full sweep, a
/// reserve epoch: each can take longer than that, and when it does the report
/// has nowhere to go and the person who pressed the button is left not knowing
/// whether their money moved.
///
/// `RAIN-13` is that a slow payout still says how it went. `RAIN-13.a` is that
/// it reaches the person another way when the reply cannot be updated any
/// more. `RAIN-13.b` is the one that decides the shape of this type: losing
/// the report must never mean losing the payout. So the outcome is **written
/// here first** and read back from here afterwards, and delivery is a separate
/// step that is allowed to fail.
///
/// Nothing in this change starts a real job. The seam and its clock ship now
/// so that the first command that needs it inherits a tested one rather than
/// inventing a worse one under time pressure.
public actor JobMailbox {

    // MARK: - Properties

    /// Where a report goes once the token has expired.
    private let fallback: JobFallback

    /// The clock. A parameter, so a test can walk past fifteen minutes
    /// without waiting fifteen minutes.
    private let now: @Sendable () -> Date

    /// Every job this process has started, by id.
    private var records: [JobId: JobRecord] = [:]

    // MARK: - Initializers

    /// - Parameters:
    ///   - fallback: Where a report goes once the token has expired.
    ///   - now: The clock.
    public init(fallback: JobFallback, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fallback = fallback
        self.now = now
    }

    // MARK: - Public Methods

    /// Records that a job has started, and until when it can answer normally.
    ///
    /// - Parameters:
    ///   - id: The job.
    ///   - invokerExternalId: Who asked for it.
    ///   - token: The interaction token.
    ///   - deadline: When that token stops working.
    public func start(id: JobId, invokerExternalId: String, token: String, deadline: Date) {
        records[id] = JobRecord(
            id: id,
            invokerExternalId: invokerExternalId,
            token: token,
            deadline: deadline
        )
    }

    /// Records what happened and says where to send it.
    ///
    /// The record is written before the answer is returned, so a delivery that
    /// then fails loses the message and not the fact.
    ///
    /// - Parameters:
    ///   - id: The job.
    ///   - report: What happened.
    /// - Returns: Where to send it, or ``JobDelivery/undeliverable(_:)``.
    public func finish(id: JobId, report: VisibleMessage) -> JobDelivery {
        guard let started = records[id] else {
            // A job nobody started. Answering `undeliverable` rather than
            // throwing keeps a caller from discarding a report it has in hand.
            return .undeliverable(id)
        }
        records[id] = JobRecord(
            id: started.id,
            invokerExternalId: started.invokerExternalId,
            token: started.token,
            deadline: started.deadline,
            report: report
        )

        guard now() >= started.deadline else {
            return .followUp(token: started.token, report)
        }
        switch fallback {
        case .directMessageToInvoker:
            return .directMessage(externalId: started.invokerExternalId, report)
        case .channel(let id):
            return .channel(id: id, report)
        case .none:
            return .undeliverable(started.id)
        }
    }

    /// What is on record for a job, including a report nobody could deliver.
    /// - Parameter id: The job.
    public func record(id: JobId) -> JobRecord? {
        records[id]
    }
}
