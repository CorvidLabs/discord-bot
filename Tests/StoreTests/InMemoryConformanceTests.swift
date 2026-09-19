import Foundation
import Store
import StoreTestKit
import Testing

@Suite("Store conformance, in memory")
struct InMemoryConformanceTests {

    @Test("A store behaves", arguments: StoreConformance.Behaviour.allCases)
    func behaves(_ behaviour: StoreConformance.Behaviour) async throws {
        _ = try await StoreConformance.inMemory().run(behaviour)
    }

    /// The suite states what this backend cannot do, rather than leaving a
    /// reader to assume the green ticks cover it.
    @Test("The behaviours in memory cannot prove are exactly the durable ones")
    func skipsOnlyDurability() async throws {
        let outcomes = try await StoreConformance.inMemory().runAll()
        let skipped = outcomes
            .filter { $0.value.skipReason != nil }
            .keys
            .map(\.rawValue)
            .sorted()
        #expect(skipped == StoreConformance.Behaviour.needingDurability.map(\.rawValue).sorted())
        for behaviour in StoreConformance.Behaviour.needingDurability {
            #expect(outcomes[behaviour]?.skipReason?.isEmpty == false)
        }
    }
}
