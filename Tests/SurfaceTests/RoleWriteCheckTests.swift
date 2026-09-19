@preconcurrency import Foundation
import Testing

@testable import Surface

/// What a role write that Discord accepted and ignored has to produce.
///
/// The sentence is the point. Discord answers `200` and drops an id it does
/// not know, so the only way anybody ever finds out is a line naming the
/// exact ids, and a line nobody wrote is a role that is never granted again.
@Suite("Role writes Discord ignores")
struct RoleWriteCheckTests {

    @Test("A write that landed whole says nothing")
    func nothingToReport() {
        let ignored = RoleWriteCheck.silentlyIgnored(
            wanted: ["role-one", "role-verified"],
            observed: ["role-one", "role-verified", "role-somebody-else-granted"]
        )
        #expect(ignored.isEmpty)
        #expect(RoleWriteCheck.incidentLine(externalId: "100000000000000001", ignored: ignored) == nil)
    }

    @Test("A role Discord dropped is named, with its id, in one line")
    func theIncidentIsNamed() throws {
        // One wrong digit in a configured role id is the likeliest mistake
        // anybody adopting this will make, and without this line it looks
        // exactly like a bot that works.
        let ignored = RoleWriteCheck.silentlyIgnored(
            wanted: ["role-one", "role-two", "role-verified"],
            observed: ["role-verified"]
        )
        #expect(ignored == ["role-one", "role-two"])

        let line = try #require(RoleWriteCheck.incidentLine(
            externalId: "100000000000000001",
            ignored: ignored
        ))
        #expect(line.contains("100000000000000001"))
        #expect(line.contains("2 role(s)"))
        // Sorted, so two runs of the same failure read the same.
        #expect(line.contains("[role-one, role-two]"))
    }
}
