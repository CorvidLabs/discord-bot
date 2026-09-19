import Foundation
import Testing
@testable import StoreSQLite

/// The volume refusal, on both platforms this builds for.
///
/// The decision is separated from the lookup precisely so it can be tested:
/// no check anywhere has a network mount, so what is proved is that a local
/// volume is recognised and allowed, and that every filesystem named as unable
/// to keep the promise is in fact refused.
@Suite("Which volumes can promise a write is on storage")
struct DurableVolumeTests {

    @Test("A local volume is recognised and allowed")
    func aLocalVolumeIsAllowed() async throws {
        try await withTemporaryDirectory { directory in
            let path = directory + "/bot.sqlite3"
            let kind = try #require(
                DurableVolume.kind(of: path),
                "the volume under the temporary directory could not be identified"
            )
            #expect(!DurableVolume.isRefused(kind: kind), "a local volume was refused as \(kind)")
            #expect(throws: Never.self) { try DurableVolume.require(path: path) }
        }
    }

    @Test(
        "Every filesystem that cannot flush a commit is refused",
        arguments: ["nfs", "nfs4", "smbfs", "afpfs", "webdav", "ftp", "smb", "smb2", "smb3", "cifs", "fuse.sshfs", "9p"]
    )
    func networkFilesystemsAreRefused(_ kind: String) {
        #expect(DurableVolume.isRefused(kind: kind))
    }

    @Test("A network mount is found in a mount table, and the local one beside it is not")
    func aMountTableIsRead() {
        // The case that decides this rule is a network mount, and no check
        // anywhere has one, so the table is supplied rather than read. The
        // longest mount point wins, and a mount point only holds a path at a
        // path boundary: `/var` does not hold `/variable`.
        let table = """
            /dev/sda1 / ext4 rw,relatime 0 0
            server:/exports /var/lib/bot nfs rw,relatime 0 0
            /dev/sdb1 /variable ext4 rw,relatime 0 0
            tmpfs /var/lib/bot/scratch\\040two tmpfs rw 0 0
            """
        #expect(DurableVolume.mountedFilesystem(at: "/var/lib/bot", table: table) == "nfs")
        #expect(DurableVolume.mountedFilesystem(at: "/var/lib/bot/data", table: table) == "nfs")
        #expect(DurableVolume.mountedFilesystem(at: "/variable/data", table: table) == "ext4")
        #expect(DurableVolume.mountedFilesystem(at: "/var/lib", table: table) == "ext4")
        #expect(
            DurableVolume.mountedFilesystem(at: "/var/lib/bot/scratch two", table: table) == "tmpfs"
        )
        #expect(DurableVolume.mountedFilesystem(at: "/var/lib/bot", table: nil) == nil)
    }

    @Test("A volume nobody can identify is allowed rather than refused")
    func anUnknownVolumeIsAllowed() {
        // An unanswered question is not evidence of a bad answer. Refusing to
        // start over one would stop a bot on every platform this does not know
        // about, which is a worse failure than the one it would be guarding
        // against.
        #expect(!DurableVolume.isRefused(kind: "something nobody here has heard of"))
        #expect(throws: Never.self) {
            try DurableVolume.require(path: "/no/such/directory/anywhere/bot.sqlite3")
        }
    }
}
