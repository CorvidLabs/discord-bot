import Foundation

/// How a button looks, in Discord's own five styles.
public enum ButtonStyle: String, Sendable, Equatable, CaseIterable, Codable {

    /// The one action a card is mostly about.
    case primary

    /// Everything else.
    case secondary

    /// A confirmation.
    case success

    /// Something that takes a thing away.
    case danger

    /// A link out. Carries a URL and no work.
    case link
}

/// A button on a card.
///
/// **It carries an id, never a closure.** In the original the work a button
/// did lived on the value that drew it, so a card could not be built in a test
/// without building the services behind it, and two buttons a version apart
/// could not be told from each other at all. Here the id is the whole
/// contract: the router matches its namespace, and a card is a value a test
/// can compare.
///
/// That also means a button from an older build is a string nothing claims
/// rather than a crash, which is why ``SurfaceRouter`` answers an unrouted id
/// instead of leaving Discord to print "This interaction failed".
public struct ButtonSpec: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// What the router matches, namespaced with a prefix and a colon.
    ///
    /// Empty for, and only for, a link button. Bounded by
    /// ``ReplyLimits/customId``, which is why a namespace is a few characters.
    public let id: String

    /// What it says.
    public let label: String

    /// How it looks.
    public let style: ButtonStyle

    /// Where a link button goes, and nil for every other style.
    public let url: String?

    /// Whether it is greyed out.
    public let disabled: Bool

    // MARK: - Initializers

    /// A button that does work.
    ///
    /// - Parameters:
    ///   - id: The namespaced id the router matches.
    ///   - label: What it says.
    ///   - style: How it looks. Never ``ButtonStyle/link``; use
    ///     ``link(label:url:)`` for that.
    ///   - disabled: Whether it is greyed out.
    public init(id: String, label: String, style: ButtonStyle = .secondary, disabled: Bool = false) {
        self.id = id
        self.label = label
        // A work button drawn in the link style has no url, and Discord
        // refuses the whole message for it. Correcting it here rather than
        // refusing keeps a caller's mistake from costing a member their reply.
        self.style = style == .link ? .secondary : style
        self.url = nil
        self.disabled = disabled
    }

    /// A button that opens a link and is never routed.
    ///
    /// - Parameters:
    ///   - label: What it says.
    ///   - url: Where it goes.
    public static func link(label: String, url: String) -> ButtonSpec {
        ButtonSpec(unchecked: "", label: label, style: .link, url: url, disabled: false)
    }

    /// The shape this file builds for itself.
    private init(unchecked id: String, label: String, style: ButtonStyle, url: String?, disabled: Bool) {
        self.id = id
        self.label = label
        self.style = style
        self.url = url
        self.disabled = disabled
    }

    // MARK: - Public Methods

    /// Whether the router should try to claim this button's id.
    public var isRoutable: Bool {
        style != .link && !id.isEmpty
    }
}

/// One named line on a card.
public struct SurfaceField: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// The field's name.
    public let name: String

    /// The field's body.
    public let value: String

    /// Whether it sits beside its neighbour rather than under it.
    public let inline: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - name: The field's name.
    ///   - value: The field's body.
    ///   - inline: Whether it sits beside its neighbour.
    public init(name: String, value: String, inline: Bool = false) {
        self.name = name
        self.value = value
        self.inline = inline
    }
}

/// A card, as a value.
///
/// No chat-client type appears on it, so a test asserts on the card rather
/// than on an encoded payload, and the mapping into whatever the chat client
/// wants lives in the adapter alone. That is the whole reason this type
/// exists: in the original a card *was* a library type, and checking what a
/// command would show meant building a gateway.
public struct SurfaceCard: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// The heading.
    public let title: String

    /// The body under the heading.
    public let description: String

    /// Named lines.
    public let fields: [SurfaceField]

    /// `0xRRGGBB`, or nil for no colour. The operator's, never a shipped one.
    public let color: UInt32?

    /// The small line at the bottom.
    public let footer: String?

    /// A small picture beside the title.
    ///
    /// Only `http` and `https` with a host survive the initializer. Anything
    /// else becomes nil, because an unusable thumbnail must cost the picture
    /// and not the whole message.
    public let thumbnailURL: String?

    /// A large picture under the body, under the same rule as the thumbnail.
    public let imageURL: String?

    /// The buttons under it.
    public let buttons: [ButtonSpec]

    /// The name of a file sent with this card, or nil.
    public let attachmentName: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - title: The heading.
    ///   - description: The body.
    ///   - fields: Named lines.
    ///   - color: `0xRRGGBB`, or nil.
    ///   - footer: The small line at the bottom.
    ///   - thumbnailURL: A small picture, or nil. Unusable becomes nil.
    ///   - imageURL: A large picture, or nil. Unusable becomes nil.
    ///   - buttons: The buttons under it.
    ///   - attachmentName: The name of a file sent with this card.
    public init(
        title: String,
        description: String = "",
        fields: [SurfaceField] = [],
        color: UInt32? = nil,
        footer: String? = nil,
        thumbnailURL: String? = nil,
        imageURL: String? = nil,
        buttons: [ButtonSpec] = [],
        attachmentName: String? = nil
    ) {
        self.title = title
        self.description = description
        self.fields = fields
        self.color = color
        self.footer = footer
        self.thumbnailURL = Self.linkable(thumbnailURL)
        self.imageURL = Self.linkable(imageURL)
        self.buttons = buttons
        self.attachmentName = attachmentName
    }

    // MARK: - Private Methods

    /// A URL a chat client will actually fetch, or nil.
    ///
    /// A `cid:` reference, a relative path or a `data:` blob makes Discord
    /// refuse the **whole** message, so a picture nobody can load has to cost
    /// the picture. An unset picture is no picture (`ADOPT-6.a`), and an
    /// unusable one is treated the same way on purpose.
    private static func linkable(_ candidate: String?) -> String? {
        guard
            let candidate,
            let url = URL(string: candidate),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else { return nil }
        return candidate
    }
}
