@preconcurrency import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The one thing that keeps a second process out of one store.
///
/// A payout is serialised inside a process by a gate that is an actor, and an
/// actor cannot see another process at all. Two instances pointed at one file
/// can each decide the same epoch is next, each claim it in their own
/// transaction, and each pay everybody. The database's own write lock does not
/// stop that: it serialises the two writes, and then both of them happen.
///
/// So the lease is taken **before** anything else, on a sibling file, and a
/// refusal stops the process. Taking it first matters for a second reason: an
/// instance that had already announced itself to a chat gateway before
/// discovering it was the duplicate would take the live instance's session away
/// on the way out, and under a supervisor that restarts it, that is a loop that
/// knocks the healthy instance offline every time the doomed one boots.
///
/// The limits, stated: `flock` is advisory, so it stops another copy of this
/// software and not a text editor, and it is unreliable on network
/// filesystems, which is one of the reasons those are refused outright.
internal final class InstanceLease {

    // MARK: - Properties

    private var descriptor: Int32?
    private let path: String

    // MARK: - Initializers

    /// Takes the lease, or refuses.
    ///
    /// - Parameter storePath: The store. The lease is a sibling of it, so a
    ///   directory holding two stores has two leases.
    internal init(storePath: String) throws {
        self.path = storePath + ".lock"
        let opened = self.path.withCString { pointer in
            open(pointer, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        }
        guard opened >= 0 else {
            throw SQLiteStoreError.cannotOpen(
                path: self.path,
                reason: "the lock file could not be created (errno \(errno))"
            )
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            throw SQLiteStoreError.alreadyHeldByAnotherProcess(path: storePath)
        }
        self.descriptor = opened
    }

    deinit {
        release()
    }

    // MARK: - Internal Methods

    /// Gives the lease up. Safe to call more than once.
    internal func release() {
        guard let descriptor else { return }
        self.descriptor = nil
        // Closing the descriptor drops the lock, which is what a stopped
        // process does too, so there is no state a crash leaves behind for the
        // next start to clean up.
        close(descriptor)
    }
}
