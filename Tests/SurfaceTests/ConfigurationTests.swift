import Foundation
import Testing

@testable import Surface

/// What has to be set, and what happens when it is set plausibly.
@Suite("Configuration and the boot report")
struct ConfigurationTests {

    private var complete: [String: String] {
        [
            "DISCORD_BOT_TOKEN": "a.token.value",
            "DISCORD_GUILD_ID": "100000000000000002",
            "HEALTH_PORT": "8080",
            "VERIFY_CALLBACK_PORT": "8081"
        ]
    }

    @Test("A missing token or server id refuses and names the variable (RUN-9.a)")
    func missingIsNamed() {
        for key in ["DISCORD_BOT_TOKEN", "DISCORD_GUILD_ID", "HEALTH_PORT", "VERIFY_CALLBACK_PORT"] {
            var environment = complete
            environment.removeValue(forKey: key)
            #expect(throws: SurfaceConfigurationError.self) {
                _ = try SurfaceConfiguration.load(from: environment)
            }
            do {
                _ = try SurfaceConfiguration.load(from: environment)
            } catch let error as SurfaceConfigurationError {
                #expect(error.errorDescription?.contains(key) == true)
            } catch {
                Issue.record("expected a configuration refusal")
            }
        }
    }

    @Test("A placeholder somebody forgot to replace stops the boot (ADOPT-7.a)")
    func placeholdersRefuse() {
        for value in ["changeme", "<your-token-here>", "CHANGEME", "your-token-here"] {
            var environment = complete
            environment["DISCORD_BOT_TOKEN"] = value
            #expect(throws: SurfaceConfigurationError.self) {
                _ = try SurfaceConfiguration.load(from: environment)
            }
        }
    }

    @Test("A blank value is the same as unset")
    func blankIsUnset() {
        var environment = complete
        environment["DISCORD_GUILD_ID"] = "   "
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try SurfaceConfiguration.load(from: environment)
        }
    }

    @Test("A server id that is not digits is refused before anything is bound")
    func guildIdIsChecked() {
        var environment = complete
        environment["DISCORD_GUILD_ID"] = "my-server"
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try SurfaceConfiguration.load(from: environment)
        }
    }

    @Test("One port twice is refused, because one process cannot bind a port twice")
    func portsMustDiffer() {
        var environment = complete
        environment["VERIFY_CALLBACK_PORT"] = environment["HEALTH_PORT"]
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try SurfaceConfiguration.load(from: environment)
        }
    }

    @Test("A portal with no secret beside it is refused, because there is one secret and not two")
    func portalNeedsItsSecret() {
        var environment = complete
        environment["VERIFY_PORTAL_URL"] = "https://verify.example.test"
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try SurfaceConfiguration.load(from: environment)
        }
    }

    @Test("Listening defaults to loopback, never to every interface")
    func listenAddressDefaultsToLoopback() throws {
        // A process that may one day hold a signing key should not appear on
        // every interface because nobody said otherwise.
        let loaded = try SurfaceConfiguration.load(from: complete)
        #expect(loaded.listenAddress == "127.0.0.1")
    }

    @Test("With no portal, verification is off and the catalogue says so")
    func noPortalMeansNoVerification() throws {
        let loaded = try SurfaceConfiguration.load(from: complete)
        #expect(loaded.hasVerification == false)
        #expect(loaded.features.has(.verification) == false)
        #expect(loaded.features.has(.spending) == false)
    }

    @Test("A trailing slash on the portal URL comes off, because the contract says there is none")
    func trailingSlashIsRemoved() throws {
        var environment = complete
        environment["VERIFY_PORTAL_URL"] = "https://verify.example.test/"
        environment["VERIFY_SHARED_SECRET"] = "shared"
        let loaded = try SurfaceConfiguration.load(from: environment)
        #expect(loaded.portalURL == "https://verify.example.test")
    }

    @Test("An empty extra operator role does not make every member an operator")
    func emptyAdminRoleGrantsNobody() {
        // An unset variable reaches this far as an empty string, and matching
        // on it would hand the server to whoever holds no roles at all.
        #expect(CommandAuth.isOperator(permissionBits: 0, memberRoleIds: [], adminRoleId: "") == false)
        #expect(CommandAuth.isOperator(permissionBits: nil, memberRoleIds: [""], adminRoleId: "") == false)
    }

    // MARK: - What it prints

    @Test("The boot report names the permissions in Discord's own words (ADOPT-11.b)")
    func reportNamesPermissions() throws {
        let lines = BootReport.lines(
            configuration: try SurfaceConfiguration.load(from: complete),
            catalog: try Fixture.catalog(),
            gating: try Fixture.gating()
        ).joined(separator: "\n")

        for name in DiscordPermission.requiredNames {
            #expect(lines.contains(name))
        }
        #expect(lines.contains("/ping /help /verify /unlink"))
        #expect(lines.contains("Ladder, 2 rung(s)"))
    }

    @Test("An invite URL grants exactly the permissions this process needs (ADOPT-11)")
    func inviteGrantsWhatIsNeeded() {
        let url = BootReport.inviteURL(applicationId: "100000000000000003")
        #expect(url.contains("client_id=100000000000000003"))
        #expect(url.contains("permissions=\(DiscordPermission.required)"))
        #expect(url.contains("scope=bot%20applications.commands"))
    }

    @Test("Without an application id the report names the variable instead of printing half a URL")
    func missingApplicationIdIsNamed() throws {
        let configuration = SurfaceConfiguration(
            botToken: "not-a-real-shape",
            guildId: "1",
            applicationId: nil,
            healthPort: 1,
            callbackPort: 2
        )
        let lines = BootReport.lines(
            configuration: configuration,
            catalog: try Fixture.catalog(),
            gating: try Fixture.gating()
        ).joined(separator: "\n")
        #expect(lines.contains(SurfaceConfiguration.applicationKey))
    }

    @Test("A managed role above the bot's own is named at startup, not after a member notices (ADOPT-11.a)")
    func rolesAboveTheBotAreNamed() {
        // Discord refuses to grant a role above the bot's own and fails
        // quietly doing it: the call succeeds for the rest and the member is
        // simply never promoted.
        let above = BootReport.rolesAboveBot(
            managedRoleIds: ["role-one", "role-two", "role-verified"],
            positions: ["role-one": 12, "role-two": 3, "role-verified": 20],
            botHighestPosition: 10,
            names: ["role-one": "One", "role-verified": "Verified"]
        )
        #expect(above == ["Verified", "One"])
    }

    @Test("Every role the configuration governs is the set that check is made against")
    func managedRolesComeFromTheConfiguration() throws {
        // Listed again by hand, this is the check that silently stops
        // covering the rung somebody added last month.
        let managed = BootReport.managedRoleIds(try Fixture.gating())
        #expect(managed == ["role-one", "role-two", "role-verified"])
    }

    @Test("The line an operator reads names the roles and says what to do")
    func rolesAboveTheBotReadAsAnInstruction() {
        #expect(BootReport.rolesAboveBotLine([]) == nil)
        let line = BootReport.rolesAboveBotLine(["Verified", "One"]) ?? ""
        #expect(line.contains("Verified"))
        #expect(line.contains("One"))
        #expect(line.contains("2 configured role(s)"))
    }

    @Test("Who runs this instance is required, because no shipped sentence can say it (VERIFY-6)")
    func disclosureIsRequired() {
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try DisclosureSettings.load { _ in nil }
        }
        #expect(throws: SurfaceConfigurationError.self) {
            _ = try DisclosureSettings.load { key in
                key == DisclosureSettings.operatorNameKey ? "Someone" : nil
            }
        }
        let loaded = try? DisclosureSettings.load { key in
            switch key {
            case DisclosureSettings.operatorNameKey: return "Someone"
            case DisclosureSettings.visibilityKey: return "Your rung only"
            default: return nil
            }
        }
        #expect(loaded?.operatorName == "Someone")
        #expect(loaded?.contact == nil)
    }

    @Test("A blank bot name becomes a word that names no project (ADOPT-1.f, ADOPT-6.a)")
    func blankBotNameNamesNobody() throws {
        let chrome = CardChrome(botName: "   ", token: try Fixture.token())
        #expect(chrome.botName == "this bot")
    }
}
