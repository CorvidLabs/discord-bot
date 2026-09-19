import Chain
import Foundation
import Runtime
import Store
import StoreSQLite

/// The durable store, on the SQLite the operating system already ships.
///
/// This is where the refusals of a real store become the two the boot has to
/// tell apart. A store held by another process is not the same fact as a
/// volume that cannot promise a write: the first means another copy is still
/// serving and this one should stop, and the second means nothing is serving
/// anybody (RUN-7.a).
internal struct DurableStoreOpener: StoreOpening {

    // MARK: - Internal Methods

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
            throw StoreGateError.unusable(
                path: path,
                reason: (error as? any LocalizedError)?.errorDescription ?? "\(error)"
            )
        }
    }
}

/// The node, over HTTP, and the one probe whose headers are the point.
internal struct NodeChainSource: ChainSourceProviding {

    // MARK: - Internal Methods

    internal func dataSource(for configuration: ChainConfiguration) throws -> any AccountDataSource {
        NodeAccountDataSource(configuration: configuration)
    }

    internal func proofProbe(for configuration: ChainConfiguration) -> (any HTTPHeaderProbe)? {
        // No configured header names means nothing to prove, so no probe is
        // built and no second host is ever contacted. That is the ordinary
        // case for a provider that stamps nothing.
        guard !configuration.proofHeaderNames.isEmpty else { return nil }
        // The node's own status path. The alternative was a fifth variable
        // most operators would never touch, and this is the path the node
        // software offers; a provider that does not is a provider whose proof
        // headers simply never arrive, which the probe already reports as no
        // proof rather than as false proof.
        let base = configuration.nodeURL.absoluteString.hasSuffix("/")
            ? String(configuration.nodeURL.absoluteString.dropLast())
            : configuration.nodeURL.absoluteString
        guard let url = URL(string: base + "/v2/status") else { return nil }
        var headers: [String: String] = [:]
        if let token = configuration.apiToken {
            headers["X-Algo-API-Token"] = token
        }
        return URLSessionHeaderProbe(url: url, headers: headers)
    }
}
