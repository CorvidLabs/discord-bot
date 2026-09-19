@preconcurrency import Foundation
import Store
import Testing

@testable import Surface

/// The order the boot happens in, and what happens when a step will not work.
@Suite("Boot sequence")
struct BootSequenceTests {

    // MARK: - Doubles

    actor CountingGateway: GatewayConnection {
        private(set) var identifyCount = 0
        func identify() async throws { identifyCount += 1 }
        var count: Int { identifyCount }
    }

    actor CountingBinder: PortBinder {
        private(set) var bound: [Int] = []
        private let failing: Set<Int>

        init(failing: Set<Int> = []) { self.failing = failing }

        func bind(port: Int, address: String) async throws {
            if failing.contains(port) { throw FixtureError.refused }
            bound.append(port)
        }

        var ports: [Int] { bound }
    }

    actor CountingRegistrar: CommandRegistrar {
        private(set) var registered: [String] = []
        func register(_ catalog: ValidatedCatalog, guildId: String) async throws {
            registered = catalog.names
        }
        var names: [String] { registered }
    }

    struct OpeningStore: StoreOpener {
        let store: any BotStore
        let fails: Bool
        init(store: any BotStore = InMemoryStore(), fails: Bool = false) {
            self.store = store
            self.fails = fails
        }
        func open() async throws -> any BotStore {
            if fails { throw FixtureError.refused }
            return store
        }
    }

    private func configuration(
        portalURL: String? = "https://verify.example.test",
        secret: String? = "shared"
    ) -> SurfaceConfiguration {
        SurfaceConfiguration(
            botToken: "token",
            guildId: "1",
            healthPort: 8_080,
            callbackPort: 8_081,
            portalURL: portalURL,
            sharedSecret: secret
        )
    }

    // MARK: - The order

    @Test("Lease, then bind, then identify, and health still says starting at the end (RUN-7)")
    func theOrder() async throws {
        let gateway = CountingGateway()
        let binder = CountingBinder()
        let registrar = CountingRegistrar()
        let health = HealthState()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: health,
            storeOpener: OpeningStore(),
            binder: binder,
            registrar: registrar,
            gateway: gateway,
            verification: FakeVerificationClient()
        )

        let (_, steps) = try await boot.run()

        #expect(steps.first == .openedStore)
        #expect(steps.contains(.bound(port: 8_080)))
        #expect(steps.contains(.bound(port: 8_081)))
        #expect(steps.last == .ready)

        let boundIndex = try #require(steps.firstIndex(of: .bound(port: 8_081)))
        let identifyIndex = try #require(steps.firstIndex(of: .identified))
        let registerIndex = try #require(steps.firstIndex(of: .registeredCommands(commandCount: 4)))
        // Registration is HTTP and is not identify, so it sits between them.
        #expect(boundIndex < registerIndex)
        #expect(registerIndex < identifyIndex)

        #expect(await gateway.count == 1)
        #expect(await registrar.names == ["ping", "help", "verify", "unlink"])
        // Identifying is asking for a websocket, not having one: the call
        // returns while the connection is still being made. A `200` here
        // would pass a deploy gate for a bot no interaction can reach
        // (`SEE-1.a`), so only the gateway's own ready event raises it.
        #expect(await health.snapshot().status == "starting")
        #expect(await health.snapshot().discord == .starting)
        #expect(await health.snapshot().store == .up)
    }

    @Test("Health only says ok once the gateway itself says ready (SEE-1.a)")
    func healthWaitsForTheGateway() async throws {
        let health = HealthState()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: health,
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: CountingRegistrar(),
            gateway: CountingGateway(),
            verification: FakeVerificationClient()
        )
        _ = try await boot.run()

        #expect(await health.snapshot().statusCode == 503)
        // What the adapter does when the ready event arrives, and the only
        // thing in the package that does it.
        await health.setDiscord(.up)
        #expect(await health.snapshot().status == "ok")
        #expect(await health.snapshot().statusCode == 200)
    }

    @Test("A port already in use stops the boot before identify, so the live copy keeps its session (RUN-7.a)")
    func bindFailureNeverIdentifies() async throws {
        // A second copy that identified first would take the live copy's
        // session away, because Discord invalidates the session a duplicate
        // identify collides with, and would then die here anyway. Under a
        // supervisor that restarts it, that is a reconnect storm with no
        // bottom.
        let gateway = CountingGateway()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: HealthState(),
            storeOpener: OpeningStore(),
            binder: CountingBinder(failing: [8_081]),
            registrar: CountingRegistrar(),
            gateway: gateway,
            verification: FakeVerificationClient()
        )

        await #expect(throws: BootError.self) {
            _ = try await boot.run()
        }
        #expect(await gateway.count == 0)
    }

    @Test("A store another process holds stops the boot before any port is claimed")
    func storeFailureNeverBinds() async throws {
        let binder = CountingBinder()
        let gateway = CountingGateway()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: HealthState(),
            storeOpener: OpeningStore(fails: true),
            binder: binder,
            registrar: CountingRegistrar(),
            gateway: gateway,
            verification: FakeVerificationClient()
        )

        await #expect(throws: BootError.self) {
            _ = try await boot.run()
        }
        #expect(await binder.ports.isEmpty)
        #expect(await gateway.count == 0)
    }

    // MARK: - The two halves of verification

    @Test("Two different shared secrets stop the boot, rather than every /verify failing (VERIFY-5.b)")
    func secretMismatchRefuses() async throws {
        let portal = FakeVerificationClient()
        await portal.setProbe(.disagreed)
        let gateway = CountingGateway()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: HealthState(),
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: CountingRegistrar(),
            gateway: gateway,
            verification: portal
        )

        await #expect(throws: BootError.sharedSecretMismatch) {
            _ = try await boot.run()
        }
        #expect(await gateway.count == 0)
    }

    @Test("A portal that offers nothing to probe is not read as agreement")
    func notOfferedIsRecordedRatherThanAssumed() async throws {
        let portal = FakeVerificationClient()
        await portal.setProbe(.notOffered)
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: HealthState(),
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: CountingRegistrar(),
            gateway: CountingGateway(),
            verification: portal
        )
        let (_, steps) = try await boot.run()
        #expect(steps.contains(.probedSharedSecret(.notOffered)))
    }

    @Test("An unreachable portal stops the boot, so nobody is handed a link into nothing")
    func unreachablePortalRefuses() async throws {
        let portal = FakeVerificationClient()
        await portal.setHealthError(VerificationError.unreachable("refused"))
        let gateway = CountingGateway()
        let boot = BootSequence(
            configuration: configuration(),
            catalog: try Fixture.catalog(),
            health: HealthState(),
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: CountingRegistrar(),
            gateway: gateway,
            verification: portal
        )
        await #expect(throws: VerificationError.self) {
            _ = try await boot.run()
        }
        #expect(await gateway.count == 0)
    }

    @Test("With verification off, the boot runs and health says so rather than saying down")
    func verificationOffIsNotAFault() async throws {
        let health = HealthState()
        let boot = BootSequence(
            configuration: configuration(portalURL: nil, secret: nil),
            catalog: try CommandCatalog.build(features: SurfaceFeatures(enabled: [])),
            health: health,
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: CountingRegistrar(),
            gateway: CountingGateway(),
            verification: nil
        )
        _ = try await boot.run()
        #expect(await health.snapshot().verification == .off)
        await health.setDiscord(.up)
        #expect(await health.snapshot().status == "ok")
    }

    // MARK: - Registration is never sent something Discord would refuse

    @Test("An invalid catalogue stops the boot before the registration call")
    func invalidCatalogNeverReachesDiscord() async throws {
        let registrar = CountingRegistrar()
        let gateway = CountingGateway()
        let illegal = CommandCatalog(commands: [
            CommandDefinition(
                name: "bad",
                description: "Wrong order",
                options: [
                    CommandOption(type: .string, name: "optional", description: "Later", required: false),
                    CommandOption(type: .string, name: "needed", description: "First", required: true)
                ]
            )
        ])
        let boot = BootSequence(
            configuration: configuration(),
            catalog: illegal,
            health: HealthState(),
            storeOpener: OpeningStore(),
            binder: CountingBinder(),
            registrar: registrar,
            gateway: gateway,
            verification: FakeVerificationClient()
        )
        await #expect(throws: CommandCatalogInvalid.self) {
            _ = try await boot.run()
        }
        #expect(await registrar.names.isEmpty)
        #expect(await gateway.count == 0)
    }
}
