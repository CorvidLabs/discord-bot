import Foundation
import Store
import StoreSQLite
import StoreTestKit
import Testing

@Suite("Store conformance, SQLite on a file")
struct SQLiteFileConformanceTests {

    @Test("A store behaves", arguments: StoreConformance.Behaviour.allCases)
    func behaves(_ behaviour: StoreConformance.Behaviour) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await StoreConformance.sqliteFile(in: directory).run(behaviour)
            // A file-backed store can prove every behaviour in the suite,
            // including the ones the store in memory has to skip. A skip here
            // would mean a probe went missing rather than that the backend
            // cannot do it.
            #expect(outcome == .ran, "\(behaviour.rawValue): \(outcome.skipReason ?? "")")
        }
    }
}

@Suite("Store conformance, SQLite in memory")
struct SQLiteInMemoryConformanceTests {

    @Test("A store behaves", arguments: StoreConformance.Behaviour.allCases)
    func behaves(_ behaviour: StoreConformance.Behaviour) async throws {
        _ = try await StoreConformance.sqliteInMemory().run(behaviour)
    }
}
