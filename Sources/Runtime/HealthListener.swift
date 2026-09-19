@preconcurrency import Dispatch
@preconcurrency import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Why the health endpoint could not be opened.
public enum HealthListenerError: Error, LocalizedError, Sendable, Equatable {

    /// The address is not one this machine can bind.
    case addressUnusable(address: String)

    /// Something is already listening there.
    case addressInUse(address: String, port: UInt16)

    /// The operating system refused, and this is what it said.
    case refused(step: String, errorNumber: Int32)

    // MARK: - Public Methods

    public var errorDescription: String? {
        switch self {
        case .addressUnusable(let address):
            return "\(RuntimeEnvironment.healthAddress) is `\(address)`, which is not an IPv4 "
                + "address this machine can bind."
        case let .addressInUse(address, port):
            return "Something is already listening on \(address):\(port). Another copy of this "
                + "bot is the likely answer, and if it is, it is still serving: leave it alone. "
                + "Otherwise give this one its own \(RuntimeEnvironment.healthPort)."
        case let .refused(step, errorNumber):
            return "The health endpoint could not be opened: \(step) failed with errno "
                + "\(errorNumber)."
        }
    }

    /// What the process exits with.
    public var exitCode: ExitCode {
        switch self {
        case .addressUnusable: return .configuration
        case .addressInUse: return .unavailable
        case .refused: return .unavailable
        }
    }
}

/// Why the accept loop stopped without being asked to.
///
/// A listener that will never accept another connection is not a degraded
/// instance, it is a dead one: the endpoint answers nothing for the rest of
/// the process's life while the process goes on holding the store's lease, so
/// the replacement a supervisor starts is refused as a duplicate. The bot this
/// was ported from logged the reason and exited so its container came back;
/// this carries the reason out instead, and ``RunningInstance`` unwinds
/// properly before the exit (RUN-7.a, SEE-8).
public enum HealthListenerDeath: Error, Sendable, Equatable {

    /// Waiting on the socket failed for a reason that is not an interruption.
    case pollFailed(errorNumber: Int32)

    /// The listening socket reported an error, a hangup or that it is not a
    /// socket at all. There is nothing to accept and there never will be.
    case listeningSocketBroken(revents: Int32)

    /// `accept` refused with something that cannot come right on its own.
    case acceptRefused(errorNumber: Int32)

    /// `accept` failed this many times in a row, which is a listener that is
    /// dead rather than one that is merely busy.
    case acceptKeptFailing(times: Int, errorNumber: Int32)

    // MARK: - Public Methods

    /// What happened, in one sentence for whoever reads the log.
    public var sentence: String {
        switch self {
        case .pollFailed(let errorNumber):
            return "waiting on the listening socket failed with errno \(errorNumber)"
        case .listeningSocketBroken(let revents):
            return "the listening socket reported 0x\(String(revents, radix: 16)) and has "
                + "nothing left to accept"
        case .acceptRefused(let errorNumber):
            return "accept() refused with errno \(errorNumber)"
        case let .acceptKeptFailing(times, errorNumber):
            return "accept() failed \(times) times in a row, the last with errno \(errorNumber)"
        }
    }
}

/// The one socket this process opens on the operator's own machine.
///
/// A hand written listener over the platform's sockets, answering one path.
/// An async networking package for one endpoint would be a new pin and a new
/// thing a reader of TRUST-1 has to weigh, which is a poor trade for a few
/// hundred bytes of answer.
///
/// **The bind is what tells a second copy that a first one is here**, which is
/// why it happens before anything could identify to a chat service and why its
/// result is a ``ListenerBound`` rather than a `Bool` (RUN-7.a). It is also
/// why a bound socket is not readiness: the endpoint answers `starting` until
/// the parts that must be up are up (SEE-1.a).
///
/// Answering costs no chain request. Everything in the answer is read from
/// ``HealthState``, which the rest of the process has already written, so a
/// check still answers when the day's budget is spent (SEE-1.b).
public actor HealthListener {

    // MARK: - Properties

    /// How many bytes of a request are read before it is answered or dropped.
    ///
    /// Only the first line is wanted. Reading until the client stops is how a
    /// listener with one route becomes something that holds memory for
    /// whoever asks it to.
    public static let maximumRequestBytes = 4096

    /// Seconds a client has to send its request line.
    public static let readTimeoutSeconds = 2

    /// How many `accept` failures in a row mean the listener is dead rather
    /// than busy.
    public static let maximumConsecutiveAcceptFailures = 50

    private let state: HealthState
    private let acceptQueue = DispatchQueue(label: "health.accept", qos: .utility)

    /// Where a connection is read.
    ///
    /// Not the accept queue, because `recv` blocks for up to
    /// ``readTimeoutSeconds`` and a client that connects and sends nothing
    /// would otherwise hold the whole endpoint for that long, and ten of them
    /// for ten times that, which is past any orchestrator's probe timeout. Not
    /// a cooperative task either: a blocking read there holds one of the
    /// pool's few threads, so the same client would starve everything else
    /// this process is doing rather than only the endpoint.
    private let connectionQueue = DispatchQueue(
        label: "health.connection",
        qos: .utility,
        attributes: .concurrent
    )

    /// The write end of the pipe that wakes the accept loop.
    ///
    /// **The loop owns the listening socket and is the only thing that closes
    /// it.** Closing it from here to make `accept` fail was the obvious way
    /// and it is wrong: between the close and the loop's next `accept` the
    /// operating system is free to hand the same descriptor number to the
    /// next socket anybody opens, and the stale loop then accepts connections
    /// on somebody else's listener and answers them from the wrong state. It
    /// is a race, so it shows up as a health check that intermittently
    /// answers for an instance that is not the one being asked, which is the
    /// worst way for it to show up.
    private var wakeWriteEnd: Int32 = -1

    /// Whether a bind is live and its loop has not finished.
    private var isRunning = false

    /// Whether the loop has finished, so a stop after it does not wait for
    /// something that has already happened.
    private var loopFinished = false

    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    /// Why the loop stopped, when it stopped on its own rather than on ask.
    private var death: HealthListenerDeath?

    /// Told when the loop dies on its own.
    private var deathHandler: (@Sendable (HealthListenerDeath) async -> Void)?

    // MARK: - Initializers

    /// - Parameter state: What the answer is assembled from.
    public init(state: HealthState) {
        self.state = state
    }

    // MARK: - Public Methods

    /// Binds, listens, and starts answering.
    ///
    /// - Parameters:
    ///   - address: The address to bind. Loopback unless the operator said
    ///     otherwise.
    ///   - port: The port. Zero lets the operating system choose, which is
    ///     what lets a test bind without picking a number.
    /// - Returns: Proof that a listener exists, carrying the port actually
    ///   obtained.
    @discardableResult
    public func bind(address: String, port: UInt16) throws -> ListenerBound {
        #if canImport(Glibc) || canImport(Musl)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else {
            throw HealthListenerError.refused(step: "socket", errorNumber: errno)
        }

        // SO_REUSEADDR and deliberately never SO_REUSEPORT. Reuse of the
        // address lets a restart bind while the previous socket is in
        // TIME_WAIT. Reuse of the *port* permits a second live listener on
        // the same address and port, which is precisely the second bind this
        // bind exists to refuse: with it set, a duplicate instance would come
        // up beside the live one instead of stopping.
        var reuseAddress: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))

        var boundAddress = sockaddr_in()
        boundAddress.sin_family = sa_family_t(AF_INET)
        boundAddress.sin_port = port.bigEndian
        #if canImport(Darwin)
        boundAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        guard inet_pton(AF_INET, address, &boundAddress.sin_addr) == 1 else {
            close(handle)
            throw HealthListenerError.addressUnusable(address: address)
        }

        let bound = withUnsafePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Foundation.bind(handle, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let failure = errno
            close(handle)
            if failure == EADDRINUSE {
                throw HealthListenerError.addressInUse(address: address, port: port)
            }
            throw HealthListenerError.refused(step: "bind", errorNumber: failure)
        }

        guard listen(handle, 16) == 0 else {
            let failure = errno
            close(handle)
            throw HealthListenerError.refused(step: "listen", errorNumber: failure)
        }

        // The port actually obtained, which is not the configured one when
        // the configured one was zero. Reported rather than assumed, because
        // the report has to print somewhere an operator can curl.
        var obtained = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &obtained) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                getsockname(handle, generic, &length)
            }
        }
        guard read == 0 else {
            let failure = errno
            close(handle)
            throw HealthListenerError.refused(step: "getsockname", errorNumber: failure)
        }

        // The pipe the loop is woken by. A flag would not do: `accept` blocks
        // until a connection arrives, so a flag is read at the one moment it
        // is not needed.
        var pipeEnds: [Int32] = [-1, -1]
        guard pipe(&pipeEnds) == 0 else {
            let failure = errno
            close(handle)
            throw HealthListenerError.refused(step: "pipe", errorNumber: failure)
        }
        let wakeReadEnd = pipeEnds[0]
        wakeWriteEnd = pipeEnds[1]
        isRunning = true
        loopFinished = false

        let answering = state
        let listener = self
        let connections = connectionQueue
        acceptQueue.async {
            let death = HealthListener.acceptLoop(
                on: handle,
                wokenBy: wakeReadEnd,
                answering: answering,
                handlingOn: connections
            )
            // Closed here and nowhere else, which is what makes the number
            // safe to reuse: nothing can be accepting on it any more.
            close(handle)
            close(wakeReadEnd)
            Task { await listener.noteLoopFinished(death: death) }
        }
        return ListenerBound(address: address, port: UInt16(bigEndian: obtained.sin_port))
    }

    /// Stops answering and gives the port back.
    ///
    /// It waits for the accept loop to finish, and that is the point rather
    /// than politeness: the loop is what closes the listening socket, so
    /// returning before it has would let the next bind of the same port race
    /// a socket that is still open.
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        // Asked **before** the write, not after. A loop that has already
        // retired closed the read end on its way out, so writing to the pipe
        // then is a write with no reader: EPIPE, and SIGPIPE with it, which
        // would kill the process on the way to a clean shutdown.
        guard !loopFinished else {
            close(wakeWriteEnd)
            wakeWriteEnd = -1
            return
        }
        // One byte, then the write end goes. Either is enough to make the
        // read end readable, and doing both means a loop that missed the byte
        // still sees the hangup.
        var wake: UInt8 = 1
        _ = write(wakeWriteEnd, &wake, 1)
        close(wakeWriteEnd)
        wakeWriteEnd = -1
        guard !loopFinished else { return }
        // No `await` between the check above and the append below, so the
        // loop's own notice cannot land in between and leave this waiting for
        // something that has already happened.
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    /// What to do if the accept loop dies on its own.
    ///
    /// Set after the bind, because the thing that has to be told about it is
    /// built from the bind's own result. A loop that died before the handler
    /// arrived is not lost: the reason is kept and handed over here.
    ///
    /// - Parameter handler: Told the reason, once.
    public func onDeath(_ handler: @escaping @Sendable (HealthListenerDeath) async -> Void) {
        deathHandler = handler
        if let death {
            Task { await handler(death) }
        }
    }

    // MARK: - Internal Methods

    /// Called by the accept loop once it has closed the socket.
    ///
    /// - Parameter death: Why it stopped, or nil when it was asked to.
    internal func noteLoopFinished(death: HealthListenerDeath?) {
        loopFinished = true
        self.death = death
        let waiting = stopWaiters
        stopWaiters = []
        for continuation in waiting {
            continuation.resume()
        }
        // Handed over on a task of its own rather than awaited here: whoever
        // is told will shut this listener down, and that call comes back into
        // this actor.
        if let death, let deathHandler {
            Task { await deathHandler(death) }
        }
    }

    // MARK: - Private Methods

    /// Takes connections until it is woken, and never touches a descriptor
    /// it does not own.
    ///
    /// It waits on the listening socket **and** the wake pipe together, so
    /// stopping does not depend on a connection arriving and does not depend
    /// on somebody else closing the socket underneath it.
    private static func acceptLoop(
        on handle: Int32,
        wokenBy wake: Int32,
        answering state: HealthState,
        handlingOn connections: DispatchQueue
    ) -> HealthListenerDeath? {
        // A listening socket that has gone bad makes accept fail instantly
        // and for ever. Backing off stops the loop spinning a core, and the
        // run of failures is bounded so a listener that will never work again
        // is not mistaken for one that is merely busy. Every way out but the
        // wake pipe carries a reason, because a listener that stopped and
        // said nothing is the outage nobody notices until somebody asks why
        // the checks stopped arriving.
        var backoff: useconds_t = 100_000
        var consecutiveFailures = 0
        var lastFailure: Int32 = 0
        while true {
            var waiting = [
                pollfd(fd: handle, events: Int16(POLLIN), revents: 0),
                pollfd(fd: wake, events: Int16(POLLIN), revents: 0)
            ]
            let ready = poll(&waiting, nfds_t(waiting.count), -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return .pollFailed(errorNumber: errno)
            }
            // The wake pipe, which is the only way this loop is asked to
            // stop. Checked before the socket, so a connection arriving at
            // the same moment does not delay a shutdown.
            guard waiting[1].revents == 0 else { return nil }
            guard waiting[0].revents & Int16(POLLIN) != 0 else {
                // POLLERR, POLLHUP or POLLNVAL on the listening socket. There
                // is nothing to accept and there never will be again.
                if waiting[0].revents != 0 {
                    return .listeningSocketBroken(revents: Int32(waiting[0].revents))
                }
                continue
            }

            var client = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let connection = withUnsafeMutablePointer(to: &client) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    accept(handle, generic, &length)
                }
            }
            guard connection >= 0 else {
                let failure = errno
                // Nothing was waiting after all, which `poll` allows.
                if failure == EAGAIN || failure == EWOULDBLOCK || failure == EINTR {
                    continue
                }
                if failure == EBADF || failure == EINVAL || failure == ENOTSOCK {
                    return .acceptRefused(errorNumber: failure)
                }
                consecutiveFailures += 1
                lastFailure = failure
                if consecutiveFailures >= maximumConsecutiveAcceptFailures {
                    return .acceptKeptFailing(
                        times: consecutiveFailures,
                        errorNumber: lastFailure
                    )
                }
                usleep(backoff)
                backoff = min(backoff * 2, 5_000_000)
                continue
            }
            consecutiveFailures = 0
            backoff = 100_000
            refuseSignalOnWrite(connection)

            // Read on a thread of its own, and only then hop for the answer.
            // The answer is assembled from state the process already holds,
            // so that part is a hop rather than a request. The socket is
            // handed over with it and closed there, after exactly one answer.
            connections.async {
                guard let line = requestLine(from: connection) else {
                    close(connection)
                    return
                }
                Task {
                    await answer(line: line, on: connection, from: state)
                }
            }
        }
    }

    /// Asks the kernel to report a write to a peer that has gone as an error
    /// rather than as a signal.
    ///
    /// **It is asked for as early as it can be, and it is not enough on its
    /// own.** Darwin takes it as a socket option, and that option fails with
    /// `EINVAL` on a connection the peer has already reset, which is exactly
    /// the connection the protection is wanted for: measured here, three of
    /// six aborted connections set it too late and the write then raised
    /// SIGPIPE. Linux has no such option and takes a flag on the write
    /// instead, which cannot be too late. What actually keeps a process alive
    /// on either is ignoring the signal, which the executable does before
    /// anything else it does (RT-001).
    ///
    /// - Parameter connection: The accepted socket.
    private static func refuseSignalOnWrite(_ connection: Int32) {
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(
            connection,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
        #endif
    }

    /// Reads the request line, bounded in both bytes and seconds.
    private static func requestLine(from connection: Int32) -> String? {
        var timeout = timeval(tv_sec: readTimeoutSeconds, tv_usec: 0)
        setsockopt(
            connection,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var buffer = [UInt8](repeating: 0, count: maximumRequestBytes)
        let received = recv(connection, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }
        let text = String(decoding: buffer[0..<received], as: UTF8.self)
        return text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)
    }

    /// Answers one request and closes the connection.
    private static func answer(line: String, on connection: Int32, from state: HealthState) async {
        defer { close(connection) }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: 400, body: "{\"error\":\"bad request\"}", headers: [:], on: connection)
            return
        }
        let method = String(parts[0])
        // The query string is dropped before matching, so `/health?x=1` is
        // the same route. Everything else is 404: one path, and no second one
        // that somebody has to think about.
        let path = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        guard method == "GET", path == "/health" else {
            send(status: 404, body: "{\"error\":\"not found\"}", headers: [:], on: connection)
            return
        }
        let answer = await state.answer()
        send(status: answer.statusCode, body: answer.body, headers: answer.headers, on: connection)
    }

    /// Writes one HTTP answer.
    private static func send(
        status: Int,
        body: String,
        headers: [String: String],
        on connection: Int32
    ) {
        var lines = [
            "HTTP/1.1 \(status) \(reason(for: status))",
            "Content-Type: application/json",
            "Content-Length: \(body.utf8.count)",
            "Connection: close"
        ]
        // A provider's header is somebody else's text arriving over the
        // network. A newline in one would end the header block early and let
        // whatever follows be read as a header of its own, so a value
        // carrying one is dropped rather than repaired.
        for name in headers.keys.sorted() {
            guard
                let value = headers[name],
                isSafeHeaderName(name),
                isSafeHeaderValue(value)
            else { continue }
            lines.append("\(name): \(value)")
        }
        let response = lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        let bytes = Array(response.utf8)
        var written = 0
        while written < bytes.count {
            let sent = bytes.withUnsafeBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Foundation.send(
                    connection,
                    base + written,
                    bytes.count - written,
                    writeFlags
                )
            }
            guard sent > 0 else { return }
            written += sent
        }
    }

    /// Flags for the write, so a peer that has gone away is an error rather
    /// than a signal.
    ///
    /// Darwin has no `MSG_NOSIGNAL` and sets the option on the socket
    /// instead; Linux and Musl have no socket option and take the flag here.
    /// Between the two of them, and the process ignoring `SIGPIPE` besides,
    /// an aborted connection cannot take the bot down with it.
    private static var writeFlags: Int32 {
        #if canImport(Glibc) || canImport(Musl)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }

    private static func isSafeHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            scalar == "-" || ("0"..."9").contains(scalar) || ("A"..."Z").contains(scalar)
                || ("a"..."z").contains(scalar)
        }
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.utf8.contains { $0 == 0x0d || $0 == 0x0a }
    }
}
