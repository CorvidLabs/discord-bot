@preconcurrency import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Whether a volume can be asked to promise anything about a write.
///
/// The claim-before-pay discipline rests on a commit having reached storage
/// before the call returns. A network filesystem cannot honour that: its
/// locking is unreliable, and it acknowledges a flush that has not happened. So
/// it is refused at the start rather than discovered after a power cut.
///
/// Both halves of this are exercised by the project's own checks, on both
/// platforms it builds for. What is not exercised anywhere is a real network
/// mount, because no check has one: what is proved is that a local volume is
/// recognised and allowed, and the refusal itself is proved by its own test
/// against the values below.
internal enum DurableVolume: Sendable {

    // MARK: - Properties

    /// Filesystems that cannot promise a write is on storage when it returns.
    ///
    /// Every spelling both platforms use for the same handful of network
    /// filesystems, because they do not agree and a refusal that misses a
    /// spelling is a refusal that quietly does not happen. Matched by prefix
    /// as well, so `nfs4` and `smb3` are caught by `nfs` and `smb`.
    internal static let refusedNames: Set<String> = [
        "nfs", "smb", "smbfs", "cifs", "afpfs", "afp", "webdav", "ftp",
        "sshfs", "fuse.sshfs", "9p"
    ]

    // MARK: - Internal Methods

    /// What the volume holding `path` is, or nil when it cannot be
    /// established.
    ///
    /// Nil allows the store to open. A volume nobody could identify is not
    /// evidence of a bad one, and refusing to start over an unanswered
    /// question would stop a bot on every platform this does not know about.
    internal static func kind(of path: String) -> String? {
        let directory = (path as NSString).deletingLastPathComponent
        let target = directory.isEmpty ? "." : directory
        let absolute = (target as NSString).standardizingPath
        #if canImport(Darwin)
        var info = statfs()
        guard absolute.withCString({ statfs($0, &info) }) == 0 else { return nil }
        return withUnsafeBytes(of: &info.f_fstypename) { raw in
            guard let base = raw.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self)).lowercased()
        }
        #else
        // Read from the kernel's own table rather than through `statfs`, which
        // Swift does not expose on this platform and whose type field is a
        // different width on different architectures. The table is plain text
        // and needs no C interop at all, which is worth more here than the
        // syscall would be.
        return mountedFilesystem(at: absolute, table: mountTable())
        #endif
    }

    /// The kernel's mount table, or nil when it cannot be read.
    internal static func mountTable() -> String? {
        try? String(contentsOfFile: "/proc/self/mounts", encoding: .utf8)
    }

    /// The filesystem holding `path`, according to a mount table.
    ///
    /// Taken as a parameter rather than read inside, so the matching can be
    /// checked against tables this machine does not have: the case that
    /// matters is a network mount, and no check anywhere has one.
    internal static func mountedFilesystem(at path: String, table: String?) -> String? {
        guard let table else { return nil }
        var best: (mountPoint: String, kind: String)?
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3 else { continue }
            let mountPoint = unescaped(String(fields[1]))
            let kind = String(fields[2]).lowercased()
            guard covers(mountPoint: mountPoint, path: path) else { continue }
            if let current = best, current.mountPoint.count >= mountPoint.count { continue }
            best = (mountPoint, kind)
        }
        return best?.kind
    }

    /// Whether a volume of this kind can keep the promise the ledger makes.
    ///
    /// Split from ``kind(of:)`` so the decision can be tested without a
    /// network mount, which no check anywhere has.
    internal static func isRefused(kind: String) -> Bool {
        refusedNames.contains(where: { kind == $0 || kind.hasPrefix($0) })
    }

    /// Refuses a volume that cannot keep the promise the ledger makes.
    internal static func require(path: String) throws {
        guard let kind = kind(of: path), isRefused(kind: kind) else { return }
        throw SQLiteStoreError.settingRefused(
            setting: "the volume holding \(path)",
            wanted: "a local filesystem, which can be asked to flush a commit",
            inForce: kind
        )
    }

    // MARK: - Private Methods

    /// Whether a mount point holds a path, respecting path boundaries.
    ///
    /// `/var` does not hold `/variable`, and getting that wrong would answer
    /// with the wrong filesystem for a directory beside the one mounted.
    private static func covers(mountPoint: String, path: String) -> Bool {
        if mountPoint == "/" { return path.hasPrefix("/") }
        if path == mountPoint { return true }
        return path.hasPrefix(mountPoint + "/")
    }

    /// A mount point with the kernel's octal escapes put back.
    ///
    /// A space in a directory name arrives as four characters, and a path
    /// compared without undoing that matches nothing.
    private static func unescaped(_ value: String) -> String {
        guard value.contains("\\") else { return value }
        var output = ""
        var digits = ""
        var escaping = false
        for character in value {
            if escaping {
                digits.append(character)
                if digits.count == 3 {
                    if let code = UInt8(digits, radix: 8) {
                        output.append(Character(UnicodeScalar(code)))
                    }
                    digits = ""
                    escaping = false
                }
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            output.append(character)
        }
        return output
    }
}
