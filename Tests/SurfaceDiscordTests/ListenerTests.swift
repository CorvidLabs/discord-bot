@preconcurrency import Foundation
import Surface
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import SurfaceDiscord

/// The accept loop, and what a peer can do to it.
///
/// These are the only tests in the package that open a socket. They bind
/// port zero and ask the kernel which port that was, so they take nothing
/// from whatever else is running on the machine, which is what made the
/// listener untestable before.
@Suite("The socket listener")
struct ListenerTests {

    // MARK: - What a failed accept costs

    @Test("A failed accept is retried, and the wait doubles up to a ceiling")
    func backoffDoublesToACeiling() {
        // A bare `continue` spins a core on a dead socket and stopping on the
        // first failure leaves the port bound with nothing behind it. Neither
        // is what a transient EINTR or EMFILE deserves.
        var policy = AcceptFailurePolicy()
        #expect(policy.recordFailure() == .retry(after: 0.1))
        #expect(policy.recordFailure() == .retry(after: 0.2))
        #expect(policy.recordFailure() == .retry(after: 0.4))

        for _ in 0..<20 {
            _ = policy.recordFailure()
        }
        #expect(policy.recordFailure() == .retry(after: AcceptFailurePolicy.maximumBackoff))
    }

    @Test("One accepted connection forgives every failure before it")
    func successForgives() {
        var policy = AcceptFailurePolicy()
        for _ in 0..<10 {
            _ = policy.recordFailure()
        }
        #expect(policy.consecutiveFailures == 10)
        policy.recordSuccess()
        #expect(policy.consecutiveFailures == 0)
        #expect(policy.recordFailure() == .retry(after: AcceptFailurePolicy.initialBackoff))
    }

    @Test("A long run of failures gives up rather than retrying for ever")
    func aDeadListenerGivesUp() {
        var policy = AcceptFailurePolicy()
        var action = AcceptFailureAction.retry(after: 0)
        for _ in 0..<AcceptFailurePolicy.maximumConsecutiveFailures {
            action = policy.recordFailure()
        }
        // The process exits on this, because a bound port nothing serves
        // answers a deploy gate while every callback is lost.
        #expect(action == .giveUp(afterFailures: AcceptFailurePolicy.maximumConsecutiveFailures))
    }

    // MARK: - A real socket

    @Test("One request in, one answer out")
    func answersARequest() async throws {
        let listener = SocketHTTPListener(address: "127.0.0.1", port: 0) { request, _ in
            HTTPListenerReply(status: 200, body: "{\"route\":\"\(request.route)\"}")
        }
        try await listener.start()
        let port = await listener.boundPort
        #expect(port > 0)

        let answer = Self.exchange("GET /health HTTP/1.1\r\nHost: x\r\n\r\n", port: port, timeoutSeconds: 5)
        await listener.stop()

        let text = try #require(answer)
        #expect(text.contains("200 OK"))
        #expect(text.contains("\"route\":\"/health\""))
    }

    @Test("Peers that connect and say nothing cannot stop everybody else being served")
    func silentPeersCannotStallTheProcess() async throws {
        // `recv` blocks. Served on the cooperative pool, one silent peer per
        // core stops every task in the process: the gateway, every command,
        // the health snapshot. It needs no key, no data and not even a
        // request line.
        let listener = SocketHTTPListener(address: "127.0.0.1", port: 0) { _, _ in
            HTTPListenerReply(status: 200, body: "{\"ok\":true}")
        }
        try await listener.start()
        let port = await listener.boundPort

        // Nothing below here suspends until the silent peers are closed
        // again, so this test fails rather than deadlocking when the serving
        // goes back onto the pool.
        var silent: [Int32] = []
        for _ in 0..<(ProcessInfo.processInfo.activeProcessorCount + 4) {
            if let handle = Self.openConnection(to: port) {
                silent.append(handle)
            }
        }
        #expect(silent.count > ProcessInfo.processInfo.activeProcessorCount)

        let answer = Self.exchange("GET /health HTTP/1.1\r\n\r\n", port: port, timeoutSeconds: 5)
        for handle in silent {
            close(handle)
        }
        await listener.stop()

        #expect(answer?.contains("200 OK") == true)
    }

    // MARK: - A client of our own

    /// Opens a connection and leaves it open, saying nothing.
    private static func openConnection(to port: Int) -> Int32? {
        #if canImport(Glibc)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else { return nil }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) == 1 else {
            close(handle)
            return nil
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result >= 0 else {
            close(handle)
            return nil
        }
        return handle
    }

    /// Sends one request and waits a bounded time for the answer.
    private static func exchange(_ text: String, port: Int, timeoutSeconds: Int) -> String? {
        guard let handle = openConnection(to: port) else { return nil }
        defer { close(handle) }

        var timeout = timeval(tv_sec: .init(timeoutSeconds), tv_usec: 0)
        setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let bytes = Array(text.utf8)
        let sent = bytes.withUnsafeBufferPointer { pointer -> Int in
            guard let base = pointer.baseAddress else { return -1 }
            return send(handle, base, pointer.count, 0)
        }
        guard sent > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        let read = recv(handle, &buffer, buffer.count, 0)
        guard read > 0 else { return nil }
        return String(decoding: buffer[0..<read], as: UTF8.self)
    }
}
