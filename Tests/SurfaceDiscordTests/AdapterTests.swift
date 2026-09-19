import DiscordBM
@preconcurrency import Foundation
import Surface
import Testing

@testable import SurfaceDiscord

/// The mapping between this package's values and Discord's payloads.
///
/// No socket is opened here. A payload is built and encoded, and the encoded
/// bytes are what is asserted on, which is the only way to catch the one
/// failure this layer exists for.
@Suite("Discord adapter")
struct AdapterTests {

    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - The frozen card

    @Test("An edit always carries an attachment list, empty rather than absent")
    func editAlwaysCarriesAttachments() throws {
        // Editing a message REPLACES its attachment list with whatever is
        // sent. Leave the key out and Discord keeps every file already on the
        // message and appends the new one: after a few edits there are
        // several files of one name, `attachment://name` resolves to the
        // oldest, and the card appears to have frozen while the handler is
        // working perfectly.
        let payload = CardRendering.edit(VisibleMessage(card: SurfaceCard(title: "T")))
        let json = try encoded(payload)
        #expect(json.contains("\"attachments\":[]"))
    }

    @Test("An edit with a file names it at its index")
    func editNamesItsFile() throws {
        let message = VisibleMessage(
            card: SurfaceCard(title: "T", attachmentName: "picture.png"),
            attachments: [AttachmentSpec(index: 0, filename: "picture.png")]
        )
        let json = try encoded(CardRendering.edit(message))
        #expect(json.contains("\"filename\":\"picture.png\""))
        #expect(json.contains("\"id\":\"0\""))
    }

    @Test("A first reply carries the same list, so the first send and every edit agree")
    func replyAlsoCarriesAttachments() throws {
        let json = try encoded(CardRendering.response(VisibleMessage(content: "hello")))
        #expect(json.contains("\"attachments\":[]"))
    }

    // MARK: - Mentions

    @Test("Nothing this bot sends can ping anybody, whatever the text says")
    func mentionsAreInert() throws {
        // Empty is not absent: an empty parse list tells Discord to resolve
        // no @everyone, no @here and no role or user mention, whatever the
        // text contains. The text itself is never rewritten, because
        // rewriting somebody's words mangles an announcement that quotes
        // "@everyone" in ordinary prose.
        let json = try encoded(CardRendering.response(VisibleMessage(content: "@everyone hello")))
        #expect(json.contains("\"parse\":[]"))
        #expect(json.contains("@everyone hello"))
    }

    // MARK: - Cards

    @Test("A card becomes an embed with its fields, colour and footer")
    func cardBecomesAnEmbed() throws {
        let card = SurfaceCard(
            title: "Title",
            description: "Body",
            fields: [SurfaceField(name: "Name", value: "Value", inline: true)],
            color: 0x3366FF,
            footer: "Footer",
            thumbnailURL: "https://pictures.example.test/logo.png"
        )
        let embed = CardRendering.embed(card)
        #expect(embed.title == "Title")
        #expect(embed.description == "Body")
        #expect(embed.fields?.count == 1)
        #expect(embed.fields?[0].inline == true)
        #expect(embed.footer?.text == "Footer")
        #expect(embed.thumbnail?.url.asString == "https://pictures.example.test/logo.png")
        #expect(embed.color != nil)
    }

    @Test("An empty title or body becomes absent rather than an empty string")
    func emptyPartsAreOmitted() {
        let embed = CardRendering.embed(SurfaceCard(title: "", description: ""))
        #expect(embed.title == nil)
        #expect(embed.description == nil)
    }

    @Test("Buttons are laid out five to a row, and a sixth row is dropped rather than refused")
    func buttonsAreLaidOutInRows() {
        let card = SurfaceCard(
            title: "T",
            buttons: (1...30).map { ButtonSpec(id: "n:\($0)", label: "\($0)") }
        )
        let rows = CardRendering.components(card)
        // Discord allows five to a row and five rows, and refuses the whole
        // message for a sixth in a row rather than wrapping it.
        #expect(rows.count == 5)
    }

    @Test("A link button carries its url and no custom id; a work button the reverse")
    func buttonKinds() throws {
        let card = SurfaceCard(
            title: "T",
            buttons: [
                .link(label: "Open", url: "https://example.test/go"),
                ButtonSpec(id: "verify:add", label: "Add", style: .primary)
            ]
        )
        let json = try encoded(CardRendering.components(card))
        // JSON escapes the slashes, so the check is on the host and the
        // path rather than on the whole URL as written.
        #expect(json.contains("example.test"))
        #expect(json.contains("\"style\":5"))
        #expect(json.contains("verify:add"))
    }

    // MARK: - Command payloads

    @Test("A command maps to the payload Discord accepts, with its options in order")
    func commandMapping() throws {
        let definition = CommandDefinition(
            name: "unlink",
            description: "Remove an account",
            options: [
                CommandOption(type: .string, name: "needed", description: "First", required: true),
                CommandOption(type: .string, name: "optional", description: "Later", required: false)
            ]
        )
        let payload = CommandPayloadMapping.payload(for: definition)
        #expect(payload.name == "unlink")
        #expect(payload.options?.count == 2)
        #expect(payload.options?[0].required == true)
        #expect(payload.options?[1].required == false)
        // One server, so nothing registered should answer in a direct
        // message: there is no member, no role list and no server to read.
        #expect(payload.dm_permission == false)
    }

    @Test("A command with no options sends none rather than an empty list")
    func noOptionsMeansNoKey() {
        let payload = CommandPayloadMapping.payload(
            for: CommandDefinition(name: "ping", description: "Awake?")
        )
        #expect(payload.options == nil)
    }

    @Test("A subcommand is never marked required, because Discord does not mean anything by it")
    func containersAreNotRequired() {
        let payload = CommandPayloadMapping.payload(for: CommandDefinition(
            name: "group",
            description: "Has subcommands",
            options: [CommandOption(type: .subcommand, name: "one", description: "One")]
        ))
        #expect(payload.options?[0].required == nil)
    }

    @Test("The shipped catalogue maps without a socket being opened")
    func catalogMaps() throws {
        let catalog = try CommandCatalog.build(
            features: SurfaceFeatures(enabled: Set(SurfaceFeature.allCases))
        )
        let payloads = CommandPayloadMapping.payloads(for: catalog)
        #expect(payloads.map(\.name) == ["ping", "help", "verify", "unlink"])
    }

    // MARK: - Decoding what arrives

    private func interaction(_ json: String) throws -> Interaction {
        try JSONDecoder().decode(Interaction.self, from: Data(json.utf8))
    }

    @Test("A slash command becomes a request of plain strings, with no snowflake on it")
    func decodesACommand() throws {
        let raw = """
        {
          "id": "100000000000000010",
          "application_id": "100000000000000011",
          "type": 2,
          "token": "interaction-token",
          "version": 1,
          "entitlements": [],
          "guild_id": "100000000000000002",
          "member": {
            "roles": ["100000000000000020"],
            "permissions": "8",
            "joined_at": "2024-01-01T00:00:00+00:00",
            "deaf": false,
            "mute": false,
            "flags": 0,
            "user": { "id": "100000000000000001", "username": "someone", "discriminator": "0" }
          },
          "data": {
            "id": "100000000000000012",
            "name": "unlink",
            "type": 1,
            "options": [
              { "name": "account", "type": 3, "value": "ACCOUNT-ONE" }
            ]
          }
        }
        """
        let request = try #require(InteractionDecoding.request(from: try interaction(raw)))
        #expect(request.kind == .command)
        #expect(request.commandName == "unlink")
        #expect(request.userExternalId == "100000000000000001")
        #expect(request.guildId == "100000000000000002")
        #expect(request.memberRoleIds == ["100000000000000020"])
        // Administrator is bit three, which is the number eight.
        #expect(request.permissionBits == 8)
        #expect(request.string("account") == "ACCOUNT-ONE")
        #expect(request.token == "interaction-token")
    }

    @Test("A subcommand's options are flattened, and the path it came down is kept")
    func decodesASubcommand() throws {
        let raw = """
        {
          "id": "100000000000000010",
          "application_id": "100000000000000011",
          "type": 2,
          "token": "t",
          "version": 1,
          "entitlements": [],
          "guild_id": "100000000000000002",
          "member": {
            "roles": [],
            "joined_at": "2024-01-01T00:00:00+00:00",
            "deaf": false,
            "mute": false,
            "flags": 0,
            "user": { "id": "100000000000000001", "username": "someone", "discriminator": "0" }
          },
          "data": {
            "id": "100000000000000012",
            "name": "wallet",
            "type": 1,
            "options": [
              {
                "name": "status",
                "type": 1,
                "options": [ { "name": "verbose", "type": 5, "value": true } ]
              }
            ]
          }
        }
        """
        let request = try #require(InteractionDecoding.request(from: try interaction(raw)))
        #expect(request.subcommandPath == ["status"])
        #expect(request.flag("verbose"))
        // A handler reads the option by name whether or not there was a
        // subcommand above it.
        #expect(request.commandName == "wallet")
    }

    @Test("A button becomes a component request carrying its id")
    func decodesAComponent() throws {
        let raw = """
        {
          "id": "100000000000000010",
          "application_id": "100000000000000011",
          "type": 3,
          "token": "t",
          "version": 1,
          "entitlements": [],
          "guild_id": "100000000000000002",
          "member": {
            "roles": [],
            "joined_at": "2024-01-01T00:00:00+00:00",
            "deaf": false,
            "mute": false,
            "flags": 0,
            "user": { "id": "100000000000000001", "username": "someone", "discriminator": "0" }
          },
          "data": { "custom_id": "verify:add", "component_type": 2 }
        }
        """
        let request = try #require(InteractionDecoding.request(from: try interaction(raw)))
        #expect(request.kind == .component)
        #expect(request.customId == "verify:add")
    }

    @Test("An autocomplete is decoded as one, and says which option is being typed in")
    func decodesAnAutocomplete() throws {
        let raw = """
        {
          "id": "100000000000000010",
          "application_id": "100000000000000011",
          "type": 4,
          "token": "t",
          "version": 1,
          "entitlements": [],
          "guild_id": "100000000000000002",
          "member": {
            "roles": [],
            "joined_at": "2024-01-01T00:00:00+00:00",
            "deaf": false,
            "mute": false,
            "flags": 0,
            "user": { "id": "100000000000000001", "username": "someone", "discriminator": "0" }
          },
          "data": {
            "id": "100000000000000012",
            "name": "unlink",
            "type": 1,
            "options": [ { "name": "account", "type": 3, "value": "ACC", "focused": true } ]
          }
        }
        """
        let request = try #require(InteractionDecoding.request(from: try interaction(raw)))
        #expect(request.kind == .autocomplete)
        #expect(request.focusedOption == "account")
    }

    @Test("Suggestions past Discord's cap are trimmed rather than lost")
    func suggestionsAreTrimmed() {
        // Discord refuses more than twenty-five and shows none of them.
        let choices = (1...40).map { AutocompleteChoice(name: "n\($0)", value: "\($0)") }
        let payload = CardRendering.suggestions(choices)
        let encoder = JSONEncoder()
        let json = String(decoding: (try? encoder.encode(payload)) ?? Data(), as: UTF8.self)
        #expect(json.contains("\"n25\""))
        #expect(json.contains("\"n26\"") == false)
    }
}
