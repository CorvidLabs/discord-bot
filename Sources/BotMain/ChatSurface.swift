@preconcurrency import Foundation
import Runtime
import SurfaceDiscord

/// Where the chat surface is built, and the only place in this executable
/// that knows one exists.
///
/// It is handed the one snapshot of the machine's variables rather than
/// reading them, like everything else here (`RT-003`). Nothing in it names a
/// chat service's own vocabulary: the adapter reads its own variables and
/// describes them back through ``Runtime/ChatGateway/settingsEntries``, so
/// this file and the composition root stay free of words a target that links
/// no chat library is not allowed to know (`BUILD-4`).
internal enum ChatSurface {

    // MARK: - Internal Methods

    /// The chat surface this build was configured for, or nil for none.
    ///
    /// - Parameters:
    ///   - settings: The one snapshot of the machine's variables.
    ///   - log: What a message is reported through.
    /// - Throws: ``Runtime/BootFailure`` naming the variable to change.
    internal static func gateway(
        settings: Settings,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> (any ChatGateway)? {
        try await DiscordChatGateway.live(settings: settings.dictionary, log: log)
    }

    /// A surface that describes its variables and does nothing else.
    ///
    /// Handed to a dry run whose settings were refused, so the listing still
    /// prints every chat variable under its own heading and the audit still
    /// counts them read. Without it the dry run would fall back to a build
    /// with no chat surface and refuse those same variables a second time,
    /// for a reason that is not true of this binary.
    internal static func described() -> any ChatGateway {
        DescribedChatSurface(settingsEntries: ChatSurfaceSettings.settingsEntries)
    }

    /// What the surface reports through: standard output, one line at a time.
    ///
    /// Synchronous, because the adapter logs from inside an event handler and
    /// a handler that has to await an actor to say something is a handler
    /// that queues behind whatever else is talking.
    internal static let log: @Sendable (String) -> Void = { message in
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}

/// A chat surface a dry run can list without anything having been built.
///
/// Every verb but ``settingsEntries`` refuses. That is not a gap: the only
/// caller is `bot check`, which touches nothing, and a stand-in that quietly
/// connected to nobody would be worse than one that says it cannot.
internal struct DescribedChatSurface: ChatGateway {

    // MARK: - Properties

    /// Every variable the real surface reads.
    internal let settingsEntries: [SettingsEntry]

    // MARK: - Internal Methods

    internal func connect(
        afterBinding listener: ListenerBound,
        reporting session: @escaping @Sendable (ChatSessionState) async -> Void
    ) async throws {
        throw ChatSurfaceUnbuilt.refused
    }

    internal func roleIds(ofMember member: String) async throws -> Set<String> {
        throw ChatSurfaceUnbuilt.refused
    }

    internal func setRoles(ofMember member: String, to roleIds: Set<String>) async throws {
        throw ChatSurfaceUnbuilt.refused
    }

    internal func disconnect() async {}
}

/// What a surface that was never built refuses with.
internal enum ChatSurfaceUnbuilt: Error, Sendable {

    /// The settings that describe the surface were refused, so there is
    /// nothing to talk to.
    case refused
}
