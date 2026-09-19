import Foundation

/// A file travelling with a message.
public struct AttachmentSpec: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// Where this file sits in the message's file list.
    public let index: Int

    /// Its name, which is what `attachment://` markup refers to.
    public let filename: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - index: Where this file sits in the message's file list.
    ///   - filename: Its name.
    public init(index: Int, filename: String) {
        self.index = index
        self.filename = filename
    }
}

/// What happens to a payload that does not fit.
public enum TruncationPolicy: String, Sendable, Equatable, Codable {

    /// Shorten it and say so. The default, for a list or a summary where the
    /// shortened form is obviously shortened.
    case clamp

    /// Refuse to send it, and tell the person why.
    ///
    /// For anything whose truncated form still reads as a complete answer: an
    /// announcement, a receipt, a URL. Half a link is not a shorter link.
    case refuse
}

/// A message somebody will actually see.
public struct VisibleMessage: Sendable, Equatable {

    // MARK: - Properties

    /// Plain text above the card, or nil.
    public let content: String?

    /// The card, or nil for text alone.
    public let card: SurfaceCard?

    /// Whether only the person who ran the command sees it.
    public let isEphemeral: Bool

    /// The files on this message **after** it is sent or edited.
    ///
    /// Never optional, and empty rather than absent when there is no file.
    /// Editing a message **replaces** its attachment list with whatever this
    /// says, and omitting the key entirely means Discord keeps every picture
    /// already on the message and appends the new one. A card edited a few
    /// times then has several files of the same name, `attachment://name`
    /// resolves to the oldest, and the card appears to have frozen while the
    /// handler is in fact working perfectly.
    public let attachments: [AttachmentSpec]

    /// What to do when this does not fit.
    public let truncation: TruncationPolicy

    // MARK: - Initializers

    /// - Parameters:
    ///   - content: Plain text above the card.
    ///   - card: The card.
    ///   - isEphemeral: Whether only the invoker sees it.
    ///   - attachments: The files this message should end up with. Empty, not
    ///     absent, when there are none.
    ///   - truncation: What to do when it does not fit.
    public init(
        content: String? = nil,
        card: SurfaceCard? = nil,
        isEphemeral: Bool = false,
        attachments: [AttachmentSpec] = [],
        truncation: TruncationPolicy = .clamp
    ) {
        self.content = content
        self.card = card
        self.isEphemeral = isEphemeral
        self.attachments = attachments
        self.truncation = truncation
    }

    /// An ephemeral line of text.
    /// - Parameter text: What it says.
    public static func ephemeral(_ text: String) -> VisibleMessage {
        VisibleMessage(content: text, isEphemeral: true)
    }
}

/// One option offered while somebody is still typing.
public struct AutocompleteChoice: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// What the person reads.
    public let name: String

    /// What the command receives.
    public let value: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: What the person reads.
    ///   - value: What the command receives.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A job whose report may outlive the interaction that started it.
public struct JobId: Sendable, Hashable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// The identifier itself.
    public let value: String

    // MARK: - Initializers

    /// - Parameter value: The identifier.
    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }
}

/// What a handler answers with.
///
/// A value, so the acknowledgement rules are the router's to enforce and not
/// something twenty-six handlers each have to remember. In the original every
/// handler called the chat client itself, which is why one of them forgot to
/// defer and left members with a thinking indicator for fifteen minutes.
public enum SurfaceReply: Sendable, Equatable {

    /// Answer now. Only legal for a command whose policy is
    /// ``AcknowledgePolicy/immediate``.
    case immediate(VisibleMessage)

    /// The body of a reply the router already deferred.
    case followUp(VisibleMessage)

    /// Replace the message a component sat on.
    case updateMessage(VisibleMessage)

    /// Offer these while the person is still typing.
    case autocomplete([AutocompleteChoice])

    /// Started something long. The message is what the person sees now; the
    /// report arrives through ``JobMailbox``.
    case longRunning(job: JobId, started: VisibleMessage)

    /// No. Always ephemeral, always says why.
    case refuse(String)
}

/// How long a command is allowed to take before it has said anything.
///
/// Discord gives a handler **three seconds** to acknowledge an interaction and
/// **fifteen minutes** after that to finish. Miss the first and the member
/// sees "This interaction failed" and the work is invisible; miss the second
/// and the report has nowhere to go.
public enum AcknowledgePolicy: String, Sendable, Equatable, CaseIterable, Codable {

    /// Answers inside three seconds from values already in hand.
    case immediate

    /// Defers first, then follows up inside fifteen minutes.
    case deferEphemeral

    /// Defers publicly, then follows up inside fifteen minutes.
    case deferPublic

    /// May outlive the interaction token. Reports through ``JobMailbox``.
    case longRunning

    // MARK: - Public Methods

    /// Whether the router emits a defer before calling the handler.
    public var defersFirst: Bool {
        switch self {
        case .immediate:
            return false
        case .deferEphemeral, .deferPublic, .longRunning:
            return true
        }
    }

    /// Whether the deferred acknowledgement is ephemeral.
    public var isEphemeral: Bool {
        switch self {
        case .deferEphemeral, .longRunning:
            return true
        case .immediate, .deferPublic:
            return false
        }
    }
}
