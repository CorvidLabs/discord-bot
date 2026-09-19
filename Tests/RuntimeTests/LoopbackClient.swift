import Foundation
@testable import Runtime

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One HTTP request over loopback, by hand.
///
/// `URLSession` would do, and would also mean a test of a socket depends on
/// Foundation's proxy settings, its cache and its cookie store. The point of
/// these tests is the socket, so the client is the smallest thing that can
/// speak to it.
///
/// It reaches 127.0.0.1 and nothing else, which is the whole of what
/// "everything runs offline" means here.
internal enum LoopbackClient {

    // MARK: - Errors

    internal enum Failure: Error, Equatable {
        case couldNotConnect(errorNumber: Int32)
        case noAnswer
    }

    // MARK: - Internal Methods

    /// Sends one request line and reads the whole answer.
    ///
    /// - Parameters:
    ///   - line: The request line, without the trailing carriage return.
    ///   - bound: Where to send it.
    internal static func send(_ line: String, to bound: ListenerBound) throws -> String {
        #if canImport(Glibc) || canImport(Musl)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else { throw Failure.couldNotConnect(errorNumber: errno) }
        defer { close(handle) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = bound.port.bigEndian
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        guard inet_pton(AF_INET, bound.address, &address.sin_addr) == 1 else {
            throw Failure.couldNotConnect(errorNumber: errno)
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw Failure.couldNotConnect(errorNumber: errno) }

        let request = line + "\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let bytes = Array(request.utf8)
        var written = 0
        while written < bytes.count {
            let sent = bytes.withUnsafeBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Foundation.send(handle, base + written, bytes.count - written, 0)
            }
            guard sent > 0 else { throw Failure.noAnswer }
            written += sent
        }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var answer = ""
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let received = recv(handle, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            answer += String(decoding: buffer[0..<received], as: UTF8.self)
        }
        guard !answer.isEmpty else { throw Failure.noAnswer }
        return answer
    }

    /// Connects and says nothing, leaving the connection open.
    ///
    /// The shape that finds out whether reading a request holds up everybody
    /// else's. The caller closes what it gets back.
    ///
    /// - Parameter bound: Where to connect.
    internal static func connectSilently(to bound: ListenerBound) throws -> Int32 {
        let handle = try connected(to: bound)
        return handle
    }

    /// Sends a request and then aborts the connection, so the answer is
    /// written to a peer that has gone.
    ///
    /// `SO_LINGER` with a zero timeout is what makes the close a reset rather
    /// than a polite goodbye, which is what any client that gives up does.
    ///
    /// - Parameters:
    ///   - line: The request line.
    ///   - bound: Where to send it.
    internal static func sendAndAbort(_ line: String, to bound: ListenerBound) throws {
        let handle = try connected(to: bound)
        let request = line + "\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let bytes = Array(request.utf8)
        _ = bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return Foundation.send(handle, base, bytes.count, 0)
        }
        var linger = linger(l_onoff: 1, l_linger: 0)
        setsockopt(handle, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<linger>.size))
        close(handle)
    }

    // MARK: - Private Methods

    private static func connected(to bound: ListenerBound) throws -> Int32 {
        #if canImport(Glibc) || canImport(Musl)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else { throw Failure.couldNotConnect(errorNumber: errno) }

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
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let failure = errno
            close(handle)
            throw Failure.couldNotConnect(errorNumber: failure)
        }
        return handle
    }
}
