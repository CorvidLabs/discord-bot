import Foundation
import Store
import StoreSQLite
import Testing
@testable import Runtime

/// Stopping, and putting back what was taken.
///
/// The listener gives the port back and the store's close releases the lease
/// that keeps a second instance out. A process that stopped without doing
/// both leaves the next start looking like a duplicate (RT-028, SEE-8).
@Suite("Stopping cleanly")
internal struct LifecycleTests {

    // MARK: - Tests

    @Test("Stopping gives the port back, so the next start can bind it")
    internal func stoppingGivesThePortBack() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let port = instance.listener.port
        await instance.shutDown()

        // The same port, taken again. A listener that had not been closed
        // would refuse this.
        let again = HealthListener(state: HealthState(componentNames: []))
        let rebound = try await again.bind(address: "127.0.0.1", port: port)
        #expect(rebound.port == port)
        await again.stop()
    }

    @Test("Stopping closes the store, which releases the lease a second instance waits on")
    internal func stoppingReleasesTheLease() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.db").path

        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(output: output, store: FileStoreOpener())
        ).run(settings: Fixture.settings(storePath: path))
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        await instance.shutDown()

        // A second open of the same file, which the lease would have refused
        // a moment ago.
        let second = try await SQLiteStore.open(at: path)
        await second.close()
    }

    @Test("Stopping twice is not an error, because a second signal is the ordinary case")
    internal func stoppingTwiceIsFine() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        await instance.shutDown()
        await instance.shutDown()
        // Whoever was waiting is released exactly once and does not hang.
        await instance.waitUntilStopped()
    }

    @Test("Waiting returns once the instance has stopped")
    internal func waitingReturnsOnStop() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings())
        guard case .running(let instance) = outcome else {
            Issue.record("the boot refused: \(String(describing: outcome.failure))")
            return
        }
        let waiter = Task { await instance.waitUntilStopped() }
        await instance.shutDown()
        await waiter.value
    }
}

/// A store on a real file, under whatever path the settings gave.
internal struct FileStoreOpener: StoreOpening {

    internal func open(path: String) async throws -> OpenedStore {
        do {
            let store = try await SQLiteStore.open(at: path)
            let report = await store.migrationReport
            return OpenedStore(
                store: store,
                migrationsApplied: report.applied,
                createdFile: report.createdFile
            )
        } catch SQLiteStoreError.alreadyHeldByAnotherProcess(let held) {
            throw StoreGateError.heldByAnotherProcess(path: held)
        } catch {
            throw StoreGateError.unusable(path: path, reason: "\(error)")
        }
    }
}
