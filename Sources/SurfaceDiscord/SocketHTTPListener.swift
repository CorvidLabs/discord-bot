@preconcurrency import Foundation
import Surface

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What a listener answers with, and what it does afterwards.
public struct HTTPListenerReply: Sendable {

    // MARK: - Properties

    /// The status code.
    public let status: Int

    /// The body.
    public let body: String

    /// Work to start **after** the answer has gone out, or nil.
    ///
    /// The contract is that the callback is answered `200` and the work
    /// begins after, so a portal is never left waiting on a chain read and a
    /// role update.
    public let afterReply: (@Sendable () async -> Void)?

    // MARK: - Initializers

    /// - Parameters:
    ///   - status: The status code.
    ///   - body: The body.
    ///   - afterReply: Work to start after the answer has gone out.
    public init(status: Int, body: String, afterReply: (@Sendable () async -> Void)? = nil) {
        self.status = status
        self.body = body
        self.afterReply = afterReply
    }
}

/// Why a listener could not start.
public enum ListenerError: Error, Equatable, LocalizedError, Sendable {

    /// The socket could not be created.
    case socketUnavailable(errno: Int32)

    /// The address is not one this process can bind.
    case addressUnusable(address: String)

    /// The port is taken. Almost always a second copy of this bot.
    case portTaken(port: Int, errno: Int32)

    /// The socket bound and would not listen.
    case listenFailed(errno: Int32)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .socketUnavailable(let code):
            return "A socket could not be created (errno \(code))."
        case .addressUnusable(let address):
            return "\(address) is not an address this process can bind."
        case .portTaken(let port, let code):
            return "Port \(port) is already in use (errno \(code))."
        case .listenFailed(let code):
            return "The socket bound and would not listen (errno \(code))."
        }
    }
}

/// What the accept loop should do about one failed `accept`.
public enum AcceptFailureAction: Sendable, Equatable {

    /// Wait this long and try again.
    case retry(after: TimeInterval)

    /// Stop. The listener is not coming back on its own.
    case giveUp(afterFailures: Int)
}

/// How a failed `accept` is treated, counted and backed off.
///
/// **A failed `accept` is transient until it has failed many times in a row.**
/// `EINTR` from a signal, `ECONNABORTED` from a peer that reset between the
/// handshake and the accept, and `EMFILE` from a momentary descriptor squeeze
/// are all ordinary, and a loop that stops on the first one leaves the port
/// bound with nothing behind it: the health check goes on answering, the
/// deploy gate goes on passing, and not one callback is ever served again.
///
/// A bare `continue` is the opposite mistake, because a closed listening
/// socket fails instantly and for ever and would spin a core. So the wait
/// doubles from a tenth of a second up to five, and after a run of failures
/// the listener gives up and the process exits, which is the only way a
/// supervisor learns to start a working one.
public struct AcceptFailurePolicy: Sendable, Equatable {

    // MARK: - Properties

    /// The first wait after a failure.
    public static let initialBackoff: TimeInterval = 0.1

    /// The longest wait between two attempts.
    public static let maximumBackoff: TimeInterval = 5

    /// How many failures in a row mean the listener is dead.
    public static let maximumConsecutiveFailures = 50

    /// How many have failed in a row.
    public private(set) var consecutiveFailures = 0

    /// What the next wait would be.
    private var backoff = AcceptFailurePolicy.initialBackoff

    // MARK: - Initializers

    /// A policy that has seen nothing fail.
    public init() {}

    // MARK: - Public Methods

    /// Records one accepted connection, which forgives everything before it.
    public mutating func recordSuccess() {
        consecutiveFailures = 0
        backoff = Self.initialBackoff
    }

    /// Records one failure and says what to do about it.
    public mutating func recordFailure() -> AcceptFailureAction {
        consecutiveFailures += 1
        guard consecutiveFailures < Self.maximumConsecutiveFailures else {
            return .giveUp(afterFailures: consecutiveFailures)
        }
        let wait = backoff
        backoff = min(backoff * 2, Self.maximumBackoff)
        return .retry(after: wait)
    }
}

/// A very small HTTP listener, on the platform's own sockets.
///
/// **A single read of at most 8,192 bytes, and the socket is never read
/// again.** `Content-Length` is not consulted. That is the contract
/// `docs/VERIFICATION.md` sets out and it constrains what a portal may send:
/// the whole request in one read, no chunked transfer encoding, no
/// `Expect: 100-continue`, no connection reuse. It is a constraint rather
/// than an oversight, and writing it down is what lets somebody build the
/// other half from the document alone.
///
/// **Nothing that blocks runs on the cooperative pool.** `accept`, `recv` and
/// `send` all block, the pool has one thread per core, and a handful of peers
/// that connect and then say nothing would otherwise stop every task in the
/// process: the gateway, every interaction, the health snapshot. So the
/// accept loop is a thread of its own and each connection is served on a
/// thread of its own, and every accepted socket carries a receive and send
/// timeout so a silent peer costs one short-lived thread rather than a
/// permanent one.
///
/// Nothing here parses or authorises anything. The parsing is
/// ``Surface/HTTPRequestHead/parse(_:)`` and the rules are
/// ``Surface/CallbackRouting``, both in a target with no sockets in it, so
/// every one of them is a unit test.
public actor SocketHTTPListener {

    // MARK: - Properties

    /// How long a peer has to send its request, and to take its answer.
    public static let peerTimeoutSeconds = 10

    /// What it binds.
    public let address: String

    /// The port it binds.
    public let port: Int

    /// What answers a request.
    private let respond: @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    /// The listening socket, or -1.
    private var listening: Int32 = -1

    /// The port the kernel actually gave, which is ``port`` unless that was
    /// zero. Zero asks for any free port, which is how a test binds without
    /// racing whatever else on the machine wanted 8,080.
    public private(set) var boundPort = 0

    /// Whether the accept loop should keep going.
    private let running = RunFlag()

    // MARK: - Initializers

    /// - Parameters:
    ///   - address: What it binds.
    ///   - port: The port it binds. Zero asks the kernel for a free one.
    ///   - log: What a message is reported through.
    ///   - respond: What answers a request. The second argument is the
    ///     client's address, which is what the rate limit counts against.
    public init(
        address: String,
        port: Int,
        log: @escaping @Sendable (String) -> Void = { _ in },
        respond: @escaping @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply
    ) {
        self.address = address
        self.port = port
        self.log = log
        self.respond = respond
    }

    // MARK: - Public Methods

    /// Claims the port and starts accepting.
    ///
    /// **This is the step that discovers a second copy of this bot**, which
    /// is why the boot calls it before identifying to Discord. A second copy
    /// that identified first would take the live copy's session away and then
    /// die here anyway.
    ///
    /// - Throws: ``ListenerError``.
    public func start() throws {
        #if canImport(Glibc)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else { throw ListenerError.socketUnavailable(errno: errno) }

        // Without this, a restart within the kernel's TIME_WAIT window fails
        // to bind a port nothing is actually using, which under a supervisor
        // is a restart loop over a socket that is already gone.
        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
            close(handle)
            throw ListenerError.addressUnusable(address: address)
        }

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound >= 0 else {
            let code = errno
            close(handle)
            throw ListenerError.portTaken(port: port, errno: code)
        }
        guard listen(handle, 16) >= 0 else {
            let code = errno
            close(handle)
            throw ListenerError.listenFailed(errno: code)
        }

        listening = handle
        boundPort = Self.localPort(of: handle) ?? port
        running.set(true)

        let flag = running
        let handler = respond
        let report = log
        let socketHandle = handle
        let servedPort = boundPort
        // A blocking `accept` on a detached thread rather than in a task: a
        // task that blocks holds a cooperative thread, and the pool is small
        // enough that two of these would matter.
        Thread.detachNewThread {
            Self.acceptLoop(socket: socketHandle, port: servedPort, running: flag, log: report, respond: handler)
        }
    }

    /// Stops accepting and releases the port.
    public func stop() {
        running.set(false)
        guard listening >= 0 else { return }
        close(listening)
        listening = -1
    }

    // MARK: - Private Methods

    /// Accepts until told to stop, or until accepting has failed too often.
    private static func acceptLoop(
        socket listening: Int32,
        port: Int,
        running: RunFlag,
        log: @escaping @Sendable (String) -> Void,
        respond: @escaping @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply
    ) {
        var policy = AcceptFailurePolicy()

        while running.value {
            var client = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let connection = withUnsafeMutablePointer(to: &client) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    accept(listening, generic, &length)
                }
            }
            guard connection >= 0 else {
                let code = errno
                // `stop()` closes the listening socket, and every `accept`
                // after that fails at once. That is this process ending, not
                // a failure to count.
                guard running.value else { return }
                switch policy.recordFailure() {
                case .retry(let pause):
                    log("accept() on port \(port) failed (errno \(code)); retrying in "
                        + "\(Int(pause * 1_000)) ms")
                    Thread.sleep(forTimeInterval: pause)
                    continue

                case .giveUp(let failures):
                    // Left bound and unserved, this port answers a health
                    // check and a deploy gate while no callback can ever
                    // arrive. Exiting is what puts a working listener back.
                    log("The listener on port \(port) is dead: accept() failed \(failures) times in "
                        + "a row; exiting so the supervisor starts a working one")
                    running.set(false)
                    exit(1)
                }
            }
            policy.recordSuccess()

            let source = Self.addressText(client)
            // A thread each, rather than one task each or one connection at a
            // time: `recv` below blocks, so a task would hold a cooperative
            // thread and serving in line here would let one silent peer stop
            // the whole listener. The timeouts bound how long either costs.
            Thread.detachNewThread {
                Self.serve(connection: connection, source: source, respond: respond)
            }
        }
    }

    /// Reads one request, answers it, and closes.
    ///
    /// Runs on a thread of its own, so everything in it may block.
    private static func serve(
        connection: Int32,
        source: String,
        respond: @escaping @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply
    ) {
        defer { close(connection) }
        Self.applyTimeouts(connection)

        var buffer = [UInt8](repeating: 0, count: HTTPRequestHead.maximumRequestBytes)
        let read = recv(connection, &buffer, buffer.count, 0)
        // An empty read closes the connection with no answer at all, which is
        // what the contract says and what a health checker's bare connect
        // does. A peer that sent nothing before the timeout lands here too.
        guard read > 0 else { return }

        let raw = String(decoding: buffer[0..<read], as: UTF8.self)
        guard let request = HTTPRequestHead.parse(raw) else {
            write(connection, status: 400, body: "{\"error\":\"Bad Request\"}")
            return
        }
        let reply = answer(request, source: source, respond: respond)
        write(connection, status: reply.status, body: reply.body)
        if let afterReply = reply.afterReply {
            // The answer has gone out, so the work belongs on the cooperative
            // pool and nothing here waits for it.
            Task { await afterReply() }
        }
    }

    /// Asks the responder, from a thread that cannot await.
    ///
    /// The one bridge in this file between a blocking thread and the
    /// cooperative pool. The wait is bounded by the responder itself, which
    /// reads no network: it answers from values this process already holds.
    private static func answer(
        _ request: HTTPRequestHead,
        source: String,
        respond: @escaping @Sendable (HTTPRequestHead, String) async -> HTTPListenerReply
    ) -> HTTPListenerReply {
        let box = ReplyBox()
        let ready = DispatchSemaphore(value: 0)
        Task {
            box.value = await respond(request, source)
            ready.signal()
        }
        ready.wait()
        return box.value ?? HTTPListenerReply(status: 503, body: "{\"status\":\"starting\"}")
    }

    /// Gives an accepted socket a deadline.
    ///
    /// Without one, a peer that connects and says nothing holds its thread
    /// for as long as it likes, which is a denial of service that needs no
    /// key, no data and not even a valid request line.
    private static func applyTimeouts(_ connection: Int32) {
        var timeout = timeval(tv_sec: .init(peerTimeoutSeconds), tv_usec: 0)
        let width = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, width)
        setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, width)
    }

    /// The port a bound socket actually holds.
    private static func localPort(of handle: Int32) -> Int? {
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                getsockname(handle, generic, &length)
            }
        }
        guard result >= 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    /// Writes one answer.
    private static func write(_ connection: Int32, status: Int, body: String) {
        let bytes = Array(body.utf8)
        let head = """
            HTTP/1.1 \(status) \(reason(status))\r
            Content-Type: application/json\r
            Content-Length: \(bytes.count)\r
            Connection: close\r
            \r

            """
        var payload = Array(head.utf8)
        payload.append(contentsOf: bytes)
        payload.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            var sent = 0
            while sent < pointer.count {
                let written = send(connection, base + sent, pointer.count - sent, 0)
                guard written > 0 else { return }
                sent += written
            }
        }
    }

    /// The word beside a status code.
    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 429: return "Too Many Requests"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }

    /// A client's address, for the rate limit to count against.
    private static func addressText(_ address: sockaddr_in) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A flag two threads read.
///
/// A tiny class with a lock rather than an actor, because the accept loop is
/// a blocking thread and cannot `await`. It and ``ReplyBox`` are the two
/// places in this package that are not actors, and they exist for the same
/// reason: a thread that blocks has no way to reach one.
private final class RunFlag: @unchecked Sendable {

    /// What guards the flag.
    private let lock = NSLock()

    /// The flag.
    private var stored = false

    /// Whether the loop should keep going.
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    /// Sets it.
    /// - Parameter newValue: The new value.
    func set(_ newValue: Bool) {
        lock.lock()
        stored = newValue
        lock.unlock()
    }
}

/// One answer, handed from a task back to the thread waiting on it.
private final class ReplyBox: @unchecked Sendable {

    /// What guards the answer.
    private let lock = NSLock()

    /// The answer, once there is one.
    private var stored: HTTPListenerReply?

    /// The answer, once there is one.
    var value: HTTPListenerReply? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}
