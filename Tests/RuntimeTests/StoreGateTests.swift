import Foundation
import Store
import StoreSQLite
import Testing
@testable import Runtime

/// The store, and the lease that keeps a second instance out.
///
/// It opens before any socket is bound, because the lease asks the exact
/// question a port clash only approximates: whether another instance is using
/// **this data**. One machine hosting several communities has several
/// instances with a store and a port each, and a second instance pointed at
/// the same store on a different port would pass a port check and fail this
/// (RUN-7.a).
@Suite("The store gate")
internal struct StoreGateTests {

    // MARK: - The path

    @Test("A relative store path is refused, and the refusal says why (ADOPT-2)")
    internal func relativePathIsRefused() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings(storePath: "data/store.db"))

        let failure = try #require(outcome.failure)
        #expect(failure.variable == RuntimeEnvironment.storePath)
        #expect(failure.code == .configuration)
        // The reason is the one that actually bites: a supervisor restarting
        // from another directory hands the same command a different, empty
        // store, which reads as a reserve that has never paid anybody.
        #expect(failure.remedy?.contains("different and empty store") == true)
    }

    @Test("A missing store path is named rather than defaulted")
    internal func missingPathIsNamed() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(seams: Fixture.seams(output: output))
            .run(settings: Fixture.settings(extras: [RuntimeEnvironment.storePath: nil]))
        #expect(outcome.failure?.variable == RuntimeEnvironment.storePath)
    }

    // MARK: - Another copy

    @Test("A store another process holds stops this one, and says the other keeps serving")
    internal func heldStoreStopsThisOne() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(
                output: output,
                store: RefusingStoreOpener(.heldByAnotherProcess(path: "/tmp/held.db"))
            )
        ).run(settings: Fixture.settings())

        let failure = try #require(outcome.failure)
        #expect(failure.code == .unavailable)
        #expect(failure.summary.contains("still serving"))
        // Stopped before the socket, so the live copy never notices.
        #expect(!outcome.gatesPassed.contains(.bind))
    }

    @Test("A store that cannot be used is a different refusal from one that is held")
    internal func unusableStoreIsItsOwnRefusal() async throws {
        let output = RecordingOutput()
        let outcome = await BootSequence(
            seams: Fixture.seams(
                output: output,
                store: RefusingStoreOpener(
                    .unusable(path: "/tmp/store.db", reason: "the volume cannot promise a write")
                )
            )
        ).run(settings: Fixture.settings())

        let failure = try #require(outcome.failure)
        #expect(failure.code == .unavailable)
        #expect(failure.summary.contains("cannot promise a write"))
    }

    // MARK: - A real file

    @Test("A real store under the test's own directory opens, migrates and reports (SEE-8)")
    internal func realFileOpensAndSaysItMadeIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.db").path

        let store = try await SQLiteStore.open(at: path)
        let report = await store.migrationReport
        #expect(report.createdFile)
        #expect(!report.applied.isEmpty)

        let section = StartupReportWriter.store(
            OpenedStore(
                store: store,
                migrationsApplied: report.applied,
                createdFile: report.createdFile
            ),
            path: path
        )
        // An invented store and a found one are otherwise the same output,
        // and a volume that did not mount arrives looking exactly like a
        // genuine first boot.
        #expect(section.lines.contains { $0.contains("CREATED") })
        await store.close()
    }

    @Test("A second open of the same file is refused, which is the lease doing its job")
    internal func secondOpenIsRefused() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lease-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("store.db").path

        let first = try await SQLiteStore.open(at: path)
        defer { Task { await first.close() } }

        await #expect(throws: SQLiteStoreError.alreadyHeldByAnotherProcess(path: path)) {
            _ = try await SQLiteStore.open(at: path)
        }
    }
}
