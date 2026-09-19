import DiscordBM
import Foundation
import Surface

/// Performs what the router decided.
///
/// The router answers in ``Surface/RouterAction`` values and never calls a
/// client, so the acknowledgement contract is checked by comparing an array
/// in a test. This is the only place those values become HTTP, and it holds
/// no rules of its own: if it is deciding something, that decision is in the
/// wrong place.
public struct ReplySending: InteractionReplying {

    // MARK: - Properties

    /// The chat client.
    private let client: any DiscordClient

    /// What a failure is reported through.
    private let log: @Sendable (String) -> Void

    // MARK: - Initializers

    /// - Parameters:
    ///   - client: The chat client.
    ///   - log: What a failure is reported through.
    public init(client: any DiscordClient, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.client = client
        self.log = log
    }

    // MARK: - Public Methods

    /// Carries out every action, in order.
    ///
    /// Order matters: a defer has to reach Discord before the follow-up that
    /// fills it in, and inside three seconds.
    ///
    /// - Parameters:
    ///   - actions: What the router decided.
    ///   - request: The interaction they answer.
    public func perform(_ actions: [RouterAction], for request: InteractionRequest) async {
        for action in actions {
            await perform(action, for: request)
        }
    }

    // MARK: - Private Methods

    /// Carries out one action.
    ///
    /// A failure is logged and does not stop the rest. Half an answer is
    /// better than none, and throwing here would abandon a follow-up the
    /// member is already watching a spinner for.
    private func perform(_ action: RouterAction, for request: InteractionRequest) async {
        do {
            switch action {
            case .acknowledgeLater(let isEphemeral):
                try await client.createInteractionResponse(
                    id: InteractionSnowflake(request.interactionId),
                    token: request.token,
                    payload: .deferredChannelMessageWithSource(isEphemeral: isEphemeral)
                ).guardSuccess()

            case .reply(let message):
                try await client.createInteractionResponse(
                    id: InteractionSnowflake(request.interactionId),
                    token: request.token,
                    payload: .channelMessageWithSource(CardRendering.response(message))
                ).guardSuccess()

            case .followUp(let message):
                try await client.updateOriginalInteractionResponse(
                    token: request.token,
                    payload: CardRendering.edit(message)
                ).guardSuccess()

            case .updateMessage(let message):
                try await client.createInteractionResponse(
                    id: InteractionSnowflake(request.interactionId),
                    token: request.token,
                    payload: CardRendering.update(message)
                ).guardSuccess()

            case .suggest(let choices):
                try await client.createInteractionResponse(
                    id: InteractionSnowflake(request.interactionId),
                    token: request.token,
                    payload: CardRendering.suggestions(choices)
                ).guardSuccess()

            case .track:
                // Remembering a job is the mailbox's, not the client's.
                break
            }
        } catch {
            log("Could not answer interaction \(request.interactionId): \(error)")
        }
    }
}
