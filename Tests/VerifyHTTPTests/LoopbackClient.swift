import Dispatch
import Foundation
@testable import VerifyHTTP

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One HTTP request over loopback, by hand.
///
/// `URLSession` would do, and would also mean a test of a socket depending on
/// Foundation's proxy settings, its cache and its cookie store, which differ
/// between the two platforms this suite runs on. The point of these tests is
/// the socket, so the client is the smallest thing that can speak to it.
///
/// It reaches 127.0.0.1 and nothing else.
enum LoopbackClient {

    // MARK: - Errors

    enum Failure: Error, Equatable {
        case couldNotConnect(errorNumber: Int32)
        case noAnswer
    }

    // MARK: - Methods

    /// Sends one request, in as many pieces as it is given, and reads the
    /// whole answer.
    ///
    /// - Parameters:
    ///   - pieces: The request, split where the caller wants it split. More
    ///     than one piece is how a browser that puts its headers in one
    ///     segment and its body in the next is reproduced.
    ///   - bound: Where to send it.
    static func send(_ pieces: [String], to bound: VerifyHTTPBound) throws -> String {
        let handle = try connected(to: bound)
        defer { close(handle) }

        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                // Long enough that the listener has certainly read the first
                // piece and answered it if it was going to.
                usleep(80_000)
            }
            guard write(piece, to: handle) else { throw Failure.noAnswer }
        }

        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var answer = ""
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let received = recv(handle, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            answer += String(decoding: buffer[0..<received], as: UTF8.self)
        }
        guard !answer.isEmpty else { throw Failure.noAnswer }
        return answer
    }

    /// Sends the head of a request and then one more piece every so often,
    /// stopping as soon as an answer comes back.
    ///
    /// This is the peer the per-read timeout cannot bound: every byte it
    /// sends restarts a timeout that is armed per read, so what the answer
    /// costs is measured here rather than assumed.
    ///
    /// - Parameters:
    ///   - pieces: The head, and then whatever is dripped after it.
    ///   - bound: Where to send it.
    ///   - pausing: Seconds between two pieces.
    /// - Returns: What came back, and how long after the first byte.
    static func drip(
        _ pieces: [String],
        to bound: VerifyHTTPBound,
        pausing seconds: Double
    ) throws -> (answer: String, seconds: Double) {
        let handle = try connected(to: bound)
        defer { close(handle) }
        let started = DispatchTime.now()

        for (index, piece) in pieces.enumerated() {
            if index > 0 { usleep(useconds_t(seconds * 1_000_000)) }
            // Looked at before the next piece goes out, not after. Sending
            // to a listener that has already answered and closed earns a
            // reset, and a reset throws away the answer that is sitting in
            // this socket's own buffer, which is the thing being measured.
            if let answer = whateverIsWaiting(on: handle), !answer.isEmpty {
                return (answer, elapsed(since: started))
            }
            guard write(piece, to: handle) else { break }
        }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var answer = ""
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let received = recv(handle, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            answer += String(decoding: buffer[0..<received], as: UTF8.self)
        }
        return (answer, elapsed(since: started))
    }

    /// A connection opened and then left alone, the way a peer that says
    /// nothing leaves one. The caller closes it.
    ///
    /// - Parameter bound: Where to connect.
    static func hold(to bound: VerifyHTTPBound) throws -> Int32 {
        try connected(to: bound)
    }

    /// Closes a connection that was held.
    ///
    /// - Parameter handle: What ``hold(to:)`` answered.
    static func release(_ handle: Int32) {
        close(handle)
    }

    /// How long a fresh connection takes to be closed with nothing written
    /// to it at all.
    ///
    /// A connection refused at accept is closed at once; one the listener
    /// took and is waiting on is held for its whole budget. The difference
    /// is the bound on how many may be read at once, and it is a duration.
    ///
    /// - Parameters:
    ///   - bound: Where to connect.
    ///   - giveUpAfter: Seconds after which the answer is "it was not".
    static func secondsUntilClosed(
        to bound: VerifyHTTPBound,
        giveUpAfter seconds: Double
    ) throws -> Double {
        let handle = try connected(to: bound)
        defer { close(handle) }
        let started = DispatchTime.now()
        var timeout = timeval(
            tv_sec: .init(seconds),
            tv_usec: .init((seconds - seconds.rounded(.down)) * 1_000_000)
        )
        setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while recv(handle, &buffer, buffer.count, 0) > 0 { continue }
        return elapsed(since: started)
    }

    // MARK: - Private Methods

    /// A socket connected to a bound listener.
    private static func connected(to bound: VerifyHTTPBound) throws -> Int32 {
        #if canImport(Glibc) || canImport(Musl)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else { throw Failure.couldNotConnect(errorNumber: errno) }
        // A write to a listener that has already answered and closed is the
        // thing several of these tests are measuring, so it is an error
        // here rather than a signal that takes the test process with it.
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = bound.port.bigEndian
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        guard inet_pton(AF_INET, bound.address, &address.sin_addr) == 1 else {
            close(handle)
            throw Failure.couldNotConnect(errorNumber: errno)
        }
        let established = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard established == 0 else {
            let failure = errno
            close(handle)
            throw Failure.couldNotConnect(errorNumber: failure)
        }
        return handle
    }

    /// Writes one piece, answering whether all of it went.
    private static func write(_ piece: String, to handle: Int32) -> Bool {
        let bytes = Array(piece.utf8)
        var written = 0
        while written < bytes.count {
            let sent = bytes.withUnsafeBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Foundation.send(handle, base + written, bytes.count - written, writeFlags)
            }
            guard sent > 0 else { return false }
            written += sent
        }
        return true
    }

    /// Whatever has already arrived, without waiting for any of it.
    ///
    /// One read, not a loop: a second read on a socket the listener has not
    /// closed yet would block, and what these tests ask is only whether an
    /// answer has started.
    private static func whateverIsWaiting(on handle: Int32) -> String? {
        var waiting = [pollfd(fd: handle, events: Int16(POLLIN), revents: 0)]
        guard poll(&waiting, 1, 0) > 0, waiting[0].revents & Int16(POLLIN) != 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let received = recv(handle, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }
        return String(decoding: buffer[0..<received], as: UTF8.self)
    }

    /// Seconds since an instant on the monotonic clock.
    private static func elapsed(since started: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000_000
    }

    /// Flags for a write, so a peer that has gone is an error rather than a
    /// signal.
    private static var writeFlags: Int32 {
        #if canImport(Glibc) || canImport(Musl)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }

    /// A whole request as one piece.
    ///
    /// - Parameters:
    ///   - line: The request line.
    ///   - body: The body, or nil for none.
    ///   - bound: Where to send it.
    static func request(_ line: String, body: String? = nil, to bound: VerifyHTTPBound) throws -> String {
        try send([whole(line, body: body)], to: bound)
    }

    /// A request as text, headers and all.
    ///
    /// - Parameters:
    ///   - line: The request line.
    ///   - body: The body, or nil for none.
    static func whole(_ line: String, body: String? = nil) -> String {
        var text = line + "\r\nHost: localhost\r\nConnection: close\r\n"
        if let body {
            text += "Content-Type: application/json\r\n"
            text += "Content-Length: \(body.utf8.count)\r\n\r\n"
            text += body
        } else {
            text += "\r\n"
        }
        return text
    }

    /// The headers of a request with a body, and then the body, as two
    /// pieces.
    ///
    /// - Parameters:
    ///   - line: The request line.
    ///   - body: The body.
    static func split(_ line: String, body: String) -> [String] {
        let head = line + "\r\nHost: localhost\r\nConnection: close\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n\r\n"
        return [head, body]
    }
}

/// Runs blocking socket work on a thread of its own.
///
/// **A synchronous `recv` called straight from an `async` test holds one of
/// the cooperative pool's threads**, and that pool has about one thread per
/// core. On a two-core runner two waiting tests hold all of it, and the
/// listener's own answer — which reaches an actor and so needs that pool —
/// can never be scheduled. The connection is accepted, the request is read,
/// and nobody is left to write the reply: every peer then times out on a
/// listener that is working perfectly.
///
/// It is the test that is at fault rather than the listener. Blocking a
/// cooperative thread is the one thing a caller may not do, and a test is a
/// caller. This puts the block on a thread nothing else wants.
///
/// - Parameter work: The blocking call.
/// - Returns: What it returned.
/// - Throws: Whatever it threw.
internal func offCooperativePool<Value: Sendable>(
    _ work: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(with: Result { try work() })
        }
    }
}
