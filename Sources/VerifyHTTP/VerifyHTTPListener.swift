@preconcurrency import Dispatch
@preconcurrency import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Proof that a listener exists, carrying the port it actually got.
public struct VerifyHTTPBound: Sendable, Equatable {

    // MARK: - Properties

    /// What it bound.
    public let address: String

    /// The port it holds. Not the configured one when that was zero.
    public let port: UInt16

    // MARK: - Initializers

    /// - Parameters:
    ///   - address: What it bound.
    ///   - port: The port it holds.
    public init(address: String, port: UInt16) {
        self.address = address
        self.port = port
    }
}

/// Why the page could not be served.
public enum VerifyHTTPListenerError: Error, Sendable, Equatable, CustomStringConvertible {

    /// The address is not one this machine can bind.
    case addressUnusable(address: String)

    /// Something is already listening there.
    case addressInUse(address: String, port: UInt16)

    /// The operating system refused, and this is what it said.
    case refused(step: String, errorNumber: Int32)

    // MARK: - Public Methods

    public var description: String {
        switch self {
        case .addressUnusable(let address):
            return "`\(address)` is not an IPv4 address this machine can bind."
        case let .addressInUse(address, port):
            return "Something is already listening on \(address):\(port). Another copy of this "
                + "bot is the likely answer, and if it is, it is still serving: leave it alone."
        case let .refused(step, errorNumber):
            return "The verification page could not be served: \(step) failed with errno \(errorNumber)."
        }
    }
}

/// Why the accept loop stopped without being asked to.
public enum VerifyHTTPListenerDeath: Error, Sendable, Equatable {

    /// Waiting on the socket failed for a reason that is not an interruption.
    case pollFailed(errorNumber: Int32)

    /// The listening socket has nothing left to accept and never will.
    case listeningSocketBroken(revents: Int32)

    /// `accept` refused with something that cannot come right on its own.
    case acceptRefused(errorNumber: Int32)

    /// `accept` failed this many times in a row, which is a dead listener
    /// rather than a busy one.
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

/// The socket the page is served on.
///
/// A hand written listener over the platform's own sockets, the same shape as
/// the health endpoint in this package and for the same reason: an async
/// networking package for four routes would be a new pin and a new thing a
/// reader has to weigh, which is a poor trade.
///
/// **Deliberately its own port, and not the health endpoint's.** The health
/// endpoint is what a supervisor polls and it must answer while everything
/// else is broken; this one talks to browsers and is rate limited. Sharing a
/// port would mean one of those properties bending to the other.
///
/// **The one place in this target that reads a clock.** Every rule below it
/// takes `now` as a parameter, so the suite pins every expiry and every
/// window; here, once per request, the wall clock is read and handed down.
///
/// Nothing in it parses or decides anything. The parsing is
/// ``VerifyHTTPRequest/parse(_:)`` and the rules are ``VerifyHTTPService``,
/// neither of which has a socket in it, so every one of them is a unit test.
public actor VerifyHTTPListener {

    // MARK: - Properties

    /// Seconds a peer has to send its request, and to take its answer.
    ///
    /// The whole request, not one read of it. The socket option underneath
    /// bounds a single `recv`, which a peer dripping one byte at a time
    /// restarts for ever; the deadline in ``readRequest(from:within:)`` is
    /// what makes this number mean the sentence above.
    public static let peerTimeoutSeconds = 5

    /// How many connections may be being read at once.
    ///
    /// A browser's request arrives in microseconds, so ordinary traffic
    /// never reaches this. It is here for the peer that connects and does
    /// not send: that read blocks, and a bound on how many may block at
    /// once is the difference between a slow page and a process holding
    /// hundreds of descriptors it will never answer on, beside the store
    /// and the chat gateway. A connection over the bound is closed at
    /// accept, which is something the peer finds out now.
    public static let maximumConcurrentReads = 16

    /// How many `accept` failures in a row mean the listener is dead rather
    /// than busy.
    public static let maximumConsecutiveAcceptFailures = 50

    /// Whether a bind is live and its loop has not finished.
    ///
    /// A program that wants its health answer to reflect a verification page
    /// that has died asks this. It is not an exit: a library that calls
    /// `exit` takes a decision that belongs to the composition root, and
    /// this one has a chat gateway to unwind.
    public var isServing: Bool { isRunning && !loopFinished }

    /// Why the loop stopped, when it stopped on its own.
    public var death: VerifyHTTPListenerDeath? { stoppedBecause }

    private let service: VerifyHTTPService
    private let log: @Sendable (String) -> Void

    /// Seconds one peer gets for its whole request.
    private let peerTimeout: Int

    /// How many connections may be being read at once.
    private let concurrentReads: Int

    private var stoppedBecause: VerifyHTTPListenerDeath?
    private var wakeWriteEnd: Int32 = -1
    private var isRunning = false
    private var loopFinished = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    /// - Parameters:
    ///   - service: What decides every answer.
    ///   - peerTimeoutSeconds: Seconds one peer gets for its whole request.
    ///     Clamped to at least one, because a budget of nothing refuses
    ///     every request including the ones that arrive in time.
    ///   - maximumConcurrentReads: How many connections may be being read at
    ///     once. Clamped to at least one for the same reason.
    ///   - log: Where a line about the listener goes. It is never handed a
    ///     session id.
    public init(
        service: VerifyHTTPService,
        peerTimeoutSeconds: Int = VerifyHTTPListener.peerTimeoutSeconds,
        maximumConcurrentReads: Int = VerifyHTTPListener.maximumConcurrentReads,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.service = service
        self.peerTimeout = max(1, peerTimeoutSeconds)
        self.concurrentReads = max(1, maximumConcurrentReads)
        self.log = log
    }

    // MARK: - Public Methods

    /// Binds, listens, and starts answering.
    ///
    /// - Parameters:
    ///   - address: The address to bind. Loopback unless the operator meant
    ///     otherwise, because anything public belongs behind the operator's
    ///     own TLS.
    ///   - port: The port. Zero lets the operating system choose, which is
    ///     what lets a test bind without picking a number.
    /// - Returns: Proof that a listener exists, carrying the port obtained.
    /// - Throws: ``VerifyHTTPListenerError``.
    @discardableResult
    public func bind(address: String, port: UInt16) throws -> VerifyHTTPBound {
        #if canImport(Glibc) || canImport(Musl)
        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard handle >= 0 else {
            throw VerifyHTTPListenerError.refused(step: "socket", errorNumber: errno)
        }

        // SO_REUSEADDR and deliberately never SO_REUSEPORT: reuse of the
        // address lets a restart bind while the previous socket is in
        // TIME_WAIT, and reuse of the port would let a second copy of this
        // bot come up beside the live one instead of stopping.
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
            throw VerifyHTTPListenerError.addressUnusable(address: address)
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
                throw VerifyHTTPListenerError.addressInUse(address: address, port: port)
            }
            throw VerifyHTTPListenerError.refused(step: "bind", errorNumber: failure)
        }
        guard listen(handle, 16) == 0 else {
            let failure = errno
            close(handle)
            throw VerifyHTTPListenerError.refused(step: "listen", errorNumber: failure)
        }

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
            throw VerifyHTTPListenerError.refused(step: "getsockname", errorNumber: failure)
        }

        // The pipe the loop is woken by. A flag would not do: `accept`
        // blocks until a connection arrives, so a flag is read at the one
        // moment it is not needed.
        var pipeEnds: [Int32] = [-1, -1]
        guard pipe(&pipeEnds) == 0 else {
            let failure = errno
            close(handle)
            throw VerifyHTTPListenerError.refused(step: "pipe", errorNumber: failure)
        }
        let wakeReadEnd = pipeEnds[0]
        wakeWriteEnd = pipeEnds[1]
        isRunning = true
        loopFinished = false

        let answering = service
        let listener = self
        let report = log
        let budget = peerTimeout
        // One per bind rather than one per listener, so a listener stopped
        // and bound again starts with every slot free rather than with
        // whatever the last loop left.
        let reading = DispatchSemaphore(value: concurrentReads)
        // A detached thread rather than a dispatch queue. This loop blocks
        // until the listener is stopped, so on a queue it owns one of
        // libdispatch's pool threads for the whole life of the listener.
        // The pool is bounded on Linux and grown on demand on Darwin, which
        // is why that shape passed here and starved there: a test run that
        // binds several listeners at once exhausted the pool and every
        // request went unanswered until its peer timed out. It is the same
        // rule `SocketHTTPListener` already follows, and the same one the
        // chat surface's own listener was written against: nothing that
        // blocks runs on a shared pool.
        Thread.detachNewThread {
            let death = VerifyHTTPListener.acceptLoop(
                on: handle,
                wokenBy: wakeReadEnd,
                answering: answering,
                bounding: reading,
                within: budget
            )
            // Closed here and nowhere else, which is what makes the
            // descriptor number safe to reuse: nothing can be accepting on
            // it any more. Closing it from `stop` would let the operating
            // system hand the same number to the next socket anybody opens
            // while this loop is still between two calls.
            close(handle)
            close(wakeReadEnd)
            if let death {
                report("verify: the page listener stopped: \(death.sentence)")
            }
            Task { await listener.noteLoopFinished(death: death) }
        }
        return VerifyHTTPBound(address: address, port: UInt16(bigEndian: obtained.sin_port))
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
        // Asked before the write, not after. A loop that has already retired
        // closed the read end on its way out, so writing to the pipe then is
        // a write with no reader: EPIPE, and SIGPIPE with it.
        guard !loopFinished else {
            close(wakeWriteEnd)
            wakeWriteEnd = -1
            return
        }
        var wake: UInt8 = 1
        _ = write(wakeWriteEnd, &wake, 1)
        close(wakeWriteEnd)
        wakeWriteEnd = -1
        guard !loopFinished else { return }
        // No `await` between the check above and the append below, so the
        // loop's own notice cannot land in between and leave this waiting
        // for something that has already happened.
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    // MARK: - Internal Methods

    /// Called by the accept loop once it has closed the socket.
    ///
    /// - Parameter death: Why it stopped, or nil when it was asked to.
    internal func noteLoopFinished(death: VerifyHTTPListenerDeath?) {
        loopFinished = true
        stoppedBecause = death
        let waiting = stopWaiters
        stopWaiters = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    // MARK: - Private Methods

    /// Takes connections until it is woken, and never touches a descriptor
    /// it does not own.
    private static func acceptLoop(
        on handle: Int32,
        wokenBy wake: Int32,
        answering service: VerifyHTTPService,
        bounding reading: DispatchSemaphore,
        within peerTimeout: Int
    ) -> VerifyHTTPListenerDeath? {
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
            // The wake pipe first, so a connection arriving at the same
            // moment does not delay a shutdown.
            guard waiting[1].revents == 0 else { return nil }
            guard waiting[0].revents & Int16(POLLIN) != 0 else {
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
                if failure == EAGAIN || failure == EWOULDBLOCK || failure == EINTR {
                    continue
                }
                if failure == EBADF || failure == EINVAL || failure == ENOTSOCK {
                    return .acceptRefused(errorNumber: failure)
                }
                consecutiveFailures += 1
                lastFailure = failure
                if consecutiveFailures >= maximumConsecutiveAcceptFailures {
                    return .acceptKeptFailing(times: consecutiveFailures, errorNumber: lastFailure)
                }
                usleep(backoff)
                backoff = min(backoff * 2, 5_000_000)
                continue
            }
            consecutiveFailures = 0
            backoff = 100_000
            refuseSignalOnWrite(connection)

            // Counted here, before the dispatch, and never inside it: a
            // block queued on a concurrent queue whose workers are all
            // blocked never runs, so a bound taken in there is a bound a
            // flood never reaches. It waits for nothing at all, so the
            // accept loop stays free to accept; over the bound the
            // connection is closed at once, which is a thing the peer
            // learns now rather than a descriptor held open unanswered.
            //
            // A semaphore rather than an actor because this loop is a
            // synchronous function on a dispatch queue and cannot await,
            // and because putting the bound behind the cooperative pool
            // would put it behind the very scheduler a flood is starving.
            guard reading.wait(timeout: .now()) == .success else {
                close(connection)
                continue
            }
            let source = addressText(client)
            // Also a thread of its own, for the same reason: this read
            // blocks for up to the peer's whole budget, and the bound in
            // front of it only limits how many do so at once. Sixteen
            // blocked pool threads is most of the pool.
            Thread.detachNewThread {
                // Given back when the read is over rather than when the
                // answer is written: the blocking read is what this bounds,
                // and the answer goes out from a task nothing here waits
                // for.
                defer { reading.signal() }
                guard let raw = readRequest(from: connection, within: peerTimeout) else {
                    close(connection)
                    return
                }
                // Answered on this thread, waiting for the async work
                // rather than handing the socket to a detached task.
                //
                // `Task { }` runs on the cooperative pool, and the whole
                // point of this endpoint is to answer when the process is
                // busy. A pool saturated by the program's own async work —
                // or, in a test run, by other tests — meant the answer was
                // never scheduled and the peer timed out having connected
                // successfully. Waiting here costs the thread this
                // connection already owns and nothing shared.
                let done = DispatchSemaphore(value: 0)
                Task {
                    await answer(raw: raw, from: source, on: connection, by: service)
                    done.signal()
                }
                done.wait()
            }
        }
    }

    /// Asks the kernel to report a write to a peer that has gone as an error
    /// rather than as a signal.
    ///
    /// **It is asked for as early as it can be, and it is not enough on its
    /// own.** Darwin takes it as a socket option, and that option fails with
    /// `EINVAL` on a connection the peer has already reset, which is exactly
    /// the connection the protection is wanted for: measured on the health
    /// endpoint this listener follows, three of six aborted connections set
    /// it too late and the write then raised SIGPIPE. Linux has no such
    /// option and takes a flag on the write instead, which cannot be too
    /// late.
    ///
    /// **What actually keeps the process alive is ignoring the signal, and
    /// that is the host's to do.** This is a library with no executable of
    /// its own, so a program serving these routes has to ignore SIGPIPE
    /// before anything else it does, the way this package's own executable
    /// does (RT-001). Without it an aborted page load can still take the
    /// process down, whatever this function managed to set.
    ///
    /// - Parameter connection: The accepted socket.
    private static func refuseSignalOnWrite(_ connection: Int32) {
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    /// Reads one whole request, bounded in bytes and in seconds.
    ///
    /// **It reads until the declared body has arrived**, unlike the callback
    /// listener beside it, which takes whatever one read produced. That
    /// listener talks to one cooperating service; this one talks to
    /// browsers, which are free to put the headers in one segment and the
    /// body in the next, and a surface that loses a submission one time in
    /// twenty is a surface nobody can debug.
    ///
    /// **The seconds are the request's, not one read's.** `SO_RCVTIMEO`
    /// bounds a single `recv`, so every byte a peer sends restarts it: one
    /// byte every four seconds held a connection here for as long as the
    /// peer cared to keep sending, against a budget that says five seconds.
    /// The deadline is what makes the budget the whole request's, and the
    /// option is re-armed from what is left of it before every read so the
    /// last one cannot overrun it either.
    ///
    /// - Parameters:
    ///   - connection: The accepted socket.
    ///   - seconds: The whole request's budget.
    private static func readRequest(from connection: Int32, within seconds: Int) -> String? {
        let deadline = DispatchTime.now() + .seconds(seconds)
        var sending = timeval(tv_sec: .init(seconds), tv_usec: 0)
        let width = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &sending, width)

        var accumulated: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while accumulated.count < VerifyHTTPRequest.maximumRequestBytes {
            guard var left = timeLeft(until: deadline) else { break }
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &left, width)
            let received = recv(connection, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            accumulated.append(contentsOf: buffer[0..<received])
            let text = String(decoding: accumulated, as: UTF8.self)
            if let request = VerifyHTTPRequest.parse(text) {
                if request.isComplete { return text }
            } else if headerBlockHasEnded(text) {
                // The header block is over and it still does not parse, so
                // nothing arriving later can make it: a request line with
                // one word in it, line endings that are not a request's,
                // two content lengths that disagree. Answered now rather
                // than held for the whole budget, which is what let four
                // bytes hold a connection for five seconds and still look
                // like an ordinary slow client.
                break
            }
        }
        guard !accumulated.isEmpty else { return nil }
        return String(decoding: accumulated.prefix(VerifyHTTPRequest.maximumRequestBytes), as: UTF8.self)
    }

    /// What is left of a request's budget, or nil when it has run out.
    ///
    /// Measured on the monotonic clock, because this is a duration and it
    /// must not move when the machine's date does. The wall clock is read
    /// once per request, in ``answer(raw:from:on:by:)``, and handed down.
    ///
    /// - Parameter deadline: When the budget runs out.
    private static func timeLeft(until deadline: DispatchTime) -> timeval? {
        let now = DispatchTime.now()
        guard now < deadline else { return nil }
        let nanoseconds = deadline.uptimeNanoseconds - now.uptimeNanoseconds
        // A `timeval` of zero is not a short timeout, it is no timeout at
        // all, so the last sliver of a budget is spent here rather than
        // handed to a peer as permission to block for ever.
        guard nanoseconds >= 1_000_000 else { return nil }
        return timeval(
            tv_sec: .init(nanoseconds / 1_000_000_000),
            tv_usec: .init((nanoseconds % 1_000_000_000) / 1_000)
        )
    }

    /// Whether the peer has finished sending headers.
    ///
    /// Asked only of text that did not parse, to tell "not yet" from
    /// "never". A bare newline counts, because a sender that does not use
    /// CRLF is a sender this surface will never parse and should not wait
    /// for.
    ///
    /// - Parameter text: What has arrived so far.
    private static func headerBlockHasEnded(_ text: String) -> Bool {
        text.contains("\r\n\r\n") || text.contains("\n\n")
    }

    /// Answers one request and closes the connection.
    private static func answer(
        raw: String,
        from source: String,
        on connection: Int32,
        by service: VerifyHTTPService
    ) async {
        defer { close(connection) }
        guard let request = VerifyHTTPRequest.parse(raw) else {
            send(
                VerifyHTTPResponse.json(status: 400, body: "{\"error\":\"That was not a request.\"}"),
                on: connection
            )
            return
        }
        // The one clock read in this target, handed down as a parameter from
        // here so that nothing below it has to reach for one.
        let response = await service.respond(to: request, from: source, now: Date())
        send(response, on: connection)
    }

    /// Writes one answer.
    private static func send(_ response: VerifyHTTPResponse, on connection: Int32) {
        let bytes = response.wireBytes
        var written = 0
        while written < bytes.count {
            let sent = bytes.withUnsafeBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Foundation.send(connection, base + written, bytes.count - written, writeFlags)
            }
            guard sent > 0 else { return }
            written += sent
        }
    }

    /// Flags for the write, so a peer that has gone away is an error rather
    /// than a signal.
    private static var writeFlags: Int32 {
        #if canImport(Glibc) || canImport(Musl)
        return Int32(MSG_NOSIGNAL)
        #else
        return 0
        #endif
    }

    /// A peer's address, for the rate limit to count against.
    private static func addressText(_ address: sockaddr_in) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
