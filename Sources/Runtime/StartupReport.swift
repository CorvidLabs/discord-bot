import Chain
import Foundation
import Gating

/// One heading of the startup report and the lines under it.
public struct ReportSection: Sendable, Equatable {

    // MARK: - Properties

    /// The heading.
    public let title: String

    /// The lines under it, already in the order they are printed.
    public let lines: [String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - title: The heading.
    ///   - lines: The lines under it.
    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }
}

/// What the build made of the settings, written at every start.
///
/// Written at **every** start, including one that then refuses, and no
/// setting can suppress it: a start that refuses is still a start, and it is
/// the one a contributor sees most often while they are getting their
/// settings right (ADOPT-9, BUILD-3.b).
///
/// What it never prints: the value of a secret, in any form, including a
/// length or a hash; the path or query of any URL; and a fact derived from a
/// secret unless the catalogue entry names that fact and the fact is public by
/// construction, which today is the account a signing key signs for.
public struct StartupReport: Sendable, Equatable {

    // MARK: - Properties

    /// The sections, in the order they are printed.
    public private(set) var sections: [ReportSection]

    // MARK: - Initializers

    /// - Parameter sections: The sections, in order.
    public init(sections: [ReportSection] = []) {
        self.sections = sections
    }

    // MARK: - Public Methods

    /// Adds a section to the end.
    ///
    /// - Parameter section: The section.
    public mutating func append(_ section: ReportSection) {
        sections.append(section)
    }

    /// Adds a section unless it has no lines.
    ///
    /// - Parameter section: The section.
    public mutating func appendIfAny(_ section: ReportSection) {
        guard !section.lines.isEmpty else { return }
        sections.append(section)
    }

    /// Every line, ready for standard output.
    ///
    /// Plain lines with a stable two-space indent under each heading, so an
    /// operator can grep it. Not JSON: retrofitting a machine-readable report
    /// means changing every line at once, and nobody has asked for one yet.
    public var lines: [String] {
        lines(from: 0)
    }

    /// The lines of every section from `index` onward.
    ///
    /// What lets a start write each section as it is produced and still
    /// produce exactly the text one write would have: the blank line that
    /// separates two sections belongs to the second of them, so a report
    /// written in six goes reads the same as one written in one (RT-019).
    ///
    /// - Parameter index: The first section to render. Past the end is no
    ///   lines rather than a refusal, because a finish with nothing left to
    ///   say is the ordinary case.
    public func lines(from index: Int) -> [String] {
        var out: [String] = []
        var position = max(index, 0)
        while position < sections.count {
            if position > 0 {
                out.append("")
            }
            out.append(sections[position].title)
            out.append(contentsOf: sections[position].lines.map { "  \($0)" })
            position += 1
        }
        return out
    }

    /// The whole report as one string.
    public var rendered: String {
        lines.joined(separator: "\n")
    }
}

/// What this build says its version is.
///
/// A constant edited when a release is cut, which is honest and cheap. It is
/// what the **source claimed**, not what was built: stamping the real revision
/// needs a build plugin, which is a new moving part in the manifest, so SEE-12
/// is half answered here and the report says so in words rather than implying
/// more than it knows.
public enum RuntimeVersion: Sendable {

    /// The version this source declares.
    public static let current = "0.1.0"
}

/// Turns what is known into the sections the report prints.
///
/// Every section is a function from values, so each one can be rendered and
/// asserted without a boot.
public enum StartupReportWriter: Sendable {

    // MARK: - Public Methods

    /// The banner and the version, which are printed before the settings are
    /// even read.
    ///
    /// - Parameter capability: Whether this build can move anything.
    public static func opening(capability: SpendCapability) -> ReportSection {
        ReportSection(
            title: "discord-bot",
            lines: [
                capability.banner,
                "Version \(RuntimeVersion.current), as the source declared it. This is what was "
                    + "written down, not a stamp of what was built."
            ]
        )
    }

    /// Every catalogue entry, grouped, marked set or unset.
    ///
    /// Marked, never printed. The listing says what is there and the section
    /// after it says what was made of it, which is what keeps a value out of
    /// this half entirely.
    ///
    /// - Parameter settings: The one snapshot.
    public static func catalogue(settings: Settings) -> ReportSection {
        var lines: [String] = []
        for group in SettingsGroup.allCases {
            let entries = SettingsCatalogue.entries.filter { $0.group == group }
            guard !entries.isEmpty else { continue }
            lines.append("\(group.rawValue):")
            for entry in entries {
                lines.append("  \(entry.pattern.padding(toLength: 34, withPad: " ", startingAt: 0))"
                    + " \(mark(entry, in: settings))")
            }
        }
        return ReportSection(title: "Settings", lines: lines)
    }

    /// What the build made of the settings, rather than only that they
    /// loaded.
    ///
    /// This is the section a typo shows up in. A rung a gap dropped is a
    /// shorter ladder here, minutes before a sweep acts on it (ADOPT-9.a), and
    /// the variable each numbered list stopped at is named so an operator can
    /// see where it stopped rather than infer it.
    ///
    /// - Parameter configuration: What loaded.
    public static func understanding(configuration: LoadedConfiguration) -> ReportSection {
        let token = configuration.gating.token
        var lines: [String] = [
            "Token: asset \(token.assetId), \(token.symbol), \(token.displayName), "
                + "\(token.decimals) decimal places",
            "Node: \(SecretRedaction.host(of: configuration.chain.nodeURL.absoluteString))"
        ]

        lines.append(contentsOf: ladderLines(configuration.gating))
        lines.append(contentsOf: collectionLines(configuration.gating))
        lines.append(contentsOf: poolLines(configuration.gating))
        lines.append(contentsOf: accessLines(configuration.gating))
        lines.append(contentsOf: linkLines(token))
        return ReportSection(title: "What this made of them", lines: lines)
    }

    /// The heading the Parts section is written under.
    ///
    /// Named rather than typed twice, because a start writes that section at
    /// the gate that learns what the node said and the finish has to know it
    /// is already there.
    public static let partsTitle = "Parts"

    /// Which parts are on, which are off, and why each off one is off.
    ///
    /// A community with a token and no collections is a whole setup rather
    /// than a broken one, and the way anybody knows that is by reading this
    /// (ADOPT-10, ADOPT-10.a, BUILD-1.a).
    ///
    /// - Parameters:
    ///   - configuration: What loaded.
    ///   - capability: Whether this build can move anything.
    ///   - chainOutcome: What the node said, or nil before it was asked.
    public static func parts(
        configuration: LoadedConfiguration,
        capability: SpendCapability,
        chainOutcome: ChainGateOutcome?
    ) -> ReportSection {
        var lines: [String] = []
        lines.append("on   store, at \(configuration.runtime.storePath)")
        lines.append("on   health endpoint")

        switch chainOutcome {
        case .confirmed:
            lines.append("on   node, and it confirmed the asset and its precision")
        case .notProbed(let reason):
            lines.append("on   node, not probed at start. \(reason)")
        case .unreached(let reason):
            lines.append("on   node, not reached yet. \(reason)")
        case .contradiction, .none:
            lines.append("on   node")
        }

        // No branch for an empty ladder: `TIER_1_NAME` is required and the
        // configuration gate refuses without it, so a start that reaches this
        // line has at least one rung. Printing "off, because no TIER_1_NAME is
        // set" would describe a start that cannot happen.
        lines.append(
            "on   holder ladder, \(counted(configuration.gating.ladder.rungs.count, "rung"))"
        )
        lines.append(
            configuration.gating.collections.isEmpty
                ? "off  collections, because no COLLECTION_1_ID is set"
                : "on   collections, \(configuration.gating.collections.collections.count)"
        )
        lines.append(
            configuration.gating.pools.isEmpty
                ? "off  pools, because no POOL_1_ID is set"
                : "on   pools, \(configuration.gating.pools.pools.count)"
        )
        lines.append(
            capability.canSign
                ? "on   spending"
                : "off  spending, because no payer is compiled into this build. No setting can "
                    + "switch it on, and none stops it either: nothing here can move anything."
        )
        lines.append("off  chat surface, because this build has none: no gateway, no commands")
        lines.append("off  wallet verification, because this build has none")
        return ReportSection(title: partsTitle, lines: lines)
    }

    /// Today's request count, and whether this start inherited one.
    ///
    /// The bot this was ported from restored the count and said so in a line,
    /// and the line is the point: several restarts in one UTC day each
    /// starting from zero spend past the ceiling while the provider's own day
    /// keeps running, and without this nothing in this build would say which
    /// of the two happened (RUN-8, RUN-8.b).
    ///
    /// - Parameters:
    ///   - restored: Whether a count written earlier today was applied.
    ///   - snapshot: What the governor holds now.
    public static func budget(restored: Bool, snapshot: RequestBudgetSnapshot) -> ReportSection {
        var lines: [String] = []
        lines.append(
            restored
                ? "Restored today's request count: \(snapshot.usedRequests). A restart costs you "
                    + "nothing you have already spent."
                : "No request count on record for today, so this start begins at zero. That is "
                    + "what a first start of the day looks like and also what an empty store "
                    + "looks like."
        )
        lines.append(
            snapshot.hasBudget
                ? "Budget: \(snapshot.limit) requests this UTC day, reads and signing together. "
                    + "\(snapshot.remainingRequests) left."
                : "Budget: none set, so nothing here stops this asking your provider as often as "
                    + "the per-second limiter allows."
        )
        return ReportSection(title: "Today's requests", lines: lines)
    }

    /// The address and port actually bound.
    ///
    /// - Parameter listener: What the bind produced.
    public static func listener(_ listener: ListenerBound) -> ReportSection {
        ReportSection(
            title: "Listening",
            lines: [
                "http://\(listener.address):\(listener.port)/health",
                "A bound socket is not health. This answers 503 and `starting` until every part "
                    + "it is waiting for has been reached."
            ]
        )
    }

    /// The store: what was applied, and whether this start made the file.
    ///
    /// - Parameters:
    ///   - opened: What opening it did.
    ///   - path: Where it is.
    public static func store(_ opened: OpenedStore, path: String) -> ReportSection {
        var lines = ["Path: \(path)"]
        lines.append(
            opened.migrationsApplied.isEmpty
                ? "Migrations applied by this start: none"
                : "Migrations applied by this start: \(opened.migrationsApplied.joined(separator: ", "))"
        )
        if opened.createdFile {
            lines.append(
                "This start CREATED the store. If you expected one to be here, stop and check "
                    + "\(RuntimeEnvironment.storePath) and whether the volume mounted: an "
                    + "invented store and a found one are otherwise the same output."
            )
        } else {
            lines.append("The store was already there.")
        }
        return ReportSection(title: "Store", lines: lines)
    }

    /// Variables nothing read, and the entry each is nearly.
    ///
    /// - Parameter audit: What the audit found.
    public static func audit(_ audit: SettingsAudit) -> ReportSection {
        var lines: [String] = []
        for unread in audit.unread {
            if let nearest = unread.nearest {
                lines.append("\(unread.name) is set and nothing read it. Did you mean \(nearest)?")
            } else {
                lines.append("\(unread.name) is set and nothing read it.")
            }
        }
        return ReportSection(title: "Set, and read by nothing", lines: lines)
    }

    // MARK: - Private Methods

    /// `count` with `noun`, pluralised.
    ///
    /// A report an operator reads at every start should not say "1 rungs".
    private static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    private static func mark(_ entry: SettingsEntry, in settings: Settings) -> String {
        if entry.isFamily {
            // Counted by name and not by value, because a family's members
            // are numbered and the audit is what reports a blank one.
            let count = settings.names.filter { entry.matches($0) }.count
            if count == 0 {
                return entry.requirement == .required ? "UNSET, and required" : "unset"
            }
            return "\(count) set"
        }
        let isSet = settings.value(entry.pattern)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if !isSet {
            return entry.requirement == .required ? "UNSET, and required" : "unset"
        }
        return entry.secrecy == .secret ? "set (a secret, never printed)" : "set"
    }

    private static func ladderLines(_ configuration: GatingConfiguration) -> [String] {
        var lines: [String] = []
        let ladder = configuration.ladder
        if ladder.rungs.isEmpty {
            lines.append("Ladder: no rungs")
        } else {
            lines.append("Ladder, \(counted(ladder.rungs.count, "rung")), lowest first:")
            for rung in ladder.rungs {
                let whole = rung.minimumBaseUnits / max(configuration.token.baseUnitsPerWholeUnit, 1)
                let role = configuration.roleId(for: rung).map { "role \($0)" } ?? "no role"
                lines.append(
                    "  \(rung.name): \(GatingFormatting.grouped(whole)) whole "
                        + "(\(GatingFormatting.grouped(rung.minimumBaseUnits)) smallest units), \(role)"
                )
            }
        }
        lines.append(
            "  the ladder stopped at TIER_\(ladder.rungs.count + 1)_NAME, which is not set"
        )
        lines.append("Below the first rung a member is called \"\(ladder.unrankedName)\"")
        return lines
    }

    private static func collectionLines(_ configuration: GatingConfiguration) -> [String] {
        var lines: [String] = []
        let catalogue = configuration.collections
        if catalogue.isEmpty {
            lines.append("Collections: none")
        } else {
            lines.append("Collections, \(catalogue.collections.count):")
            for collection in catalogue.collections {
                let role = collection.roleId.map { "role \($0)" } ?? "no role"
                lines.append(
                    "  \(collection.id): minted by \(collection.creatorAddress), "
                        + "\(collection.countRungs.count) count rungs, \(role)"
                )
            }
        }
        lines.append(
            "  the collection list stopped at COLLECTION_\(catalogue.collections.count + 1)_ID, "
                + "which is not set"
        )
        return lines
    }

    private static func poolLines(_ configuration: GatingConfiguration) -> [String] {
        var lines: [String] = []
        let catalogue = configuration.pools
        if catalogue.isEmpty {
            lines.append("Pools: none")
        } else {
            lines.append("Pools, \(catalogue.pools.count):")
            for pool in catalogue.pools {
                let role = pool.roleId.map { "role \($0)" } ?? "no role"
                lines.append(
                    "  \(pool.id): LP asset \(pool.lpAssetId), paired with \(pool.pairedAssetId), "
                        + "\(pool.decimals) decimal places, \(role)"
                )
            }
        }
        lines.append(
            "  the pool list stopped at POOL_\(catalogue.pools.count + 1)_ID, which is not set"
        )
        return lines
    }

    private static func accessLines(_ configuration: GatingConfiguration) -> [String] {
        var lines: [String] = []
        lines.append(
            configuration.verifiedRoleId.map { "Verified role: \($0)" }
                ?? "Verified role: none"
        )
        lines.append(
            configuration.pools.providerRoleId.map { "Liquidity provider badge: \($0)" }
                ?? "Liquidity provider badge: none"
        )
        let admins = configuration.admins.accounts
        if admins.isEmpty {
            lines.append("Administrators: nobody. The list starts empty and stays that way "
                + "until you put somebody on it.")
        } else {
            lines.append("Administrators, \(admins.count):")
            for account in admins {
                lines.append("  \(account)")
            }
        }
        lines.append(
            "  the administrator list stopped at ADMIN_WALLET_\(admins.count + 1), which is not set"
        )
        return lines
    }

    private static func linkLines(_ token: TokenProfile) -> [String] {
        var lines: [String] = []
        if token.links.isEmpty {
            lines.append("Token links: none")
        } else {
            lines.append("Token links, \(token.links.count):")
            for link in token.links {
                lines.append("  \(link.label): \(SecretRedaction.host(of: link.url))")
            }
        }
        lines.append(
            "  the link list stopped at TOKEN_LINK_\(token.links.count + 1)_LABEL, which is not set"
        )
        return lines
    }
}
