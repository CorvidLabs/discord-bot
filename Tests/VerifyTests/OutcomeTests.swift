import Foundation
import Testing
import Algorand
import Verify

/// One seam, two producers, and a tag that says which (VERIFY-2, HOST-2).
@Suite("Where the two routes meet")
struct OutcomeTests {

    @Test("A proved account and an asserted account differ only in the route tag")
    func oneSeamTwoProducers() async throws {
        // Goes red against two record shapes, which is how one of them
        // quietly stops enforcing something the other still does.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let outcome = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: session.id,
            now: CoordinatorFixtures.now
        )
        guard case .proved(let proved) = outcome else {
            Issue.record("the proof should have been accepted")
            return
        }

        let asserted = AssertedAccount(
            subject: proved.subject,
            address: proved.address,
            assertedAt: proved.provedAt,
            assertedBy: "a hosted portal"
        )

        let fromProof = VerifiedAccount(proved: proved)
        let fromAssertion = VerifiedAccount(asserted: asserted)

        #expect(fromProof.subject == fromAssertion.subject)
        #expect(fromProof.address == fromAssertion.address)
        #expect(fromProof.verifiedAt == fromAssertion.verifiedAt)
        #expect(fromProof.route != fromAssertion.route)
    }

    @Test("The route is in process when the signature was checked here and asserted when it was not")
    func theTagIsTheTruth() throws {
        // Goes red against tagging both the same, which hides from an
        // operator that their bot is taking another service's word for an
        // identity. The asymmetry is real, and the point of the tag is that
        // the software says so rather than the operator working it out.
        let asserted = AssertedAccount(
            subject: CoordinatorFixtures.subject,
            address: try ProofFixtures.account().address.description,
            assertedAt: CoordinatorFixtures.now,
            assertedBy: "a hosted portal"
        )
        #expect(VerifiedAccount(asserted: asserted).route == .asserted)
        #expect(ProofRoute.allCases.count == 2)
    }

    @Test("An asserted account carries whose word it was")
    func theAssertionNamesItsSource() throws {
        let asserted = AssertedAccount(
            subject: CoordinatorFixtures.subject,
            address: try ProofFixtures.account().address.description,
            assertedAt: CoordinatorFixtures.now,
            assertedBy: "a hosted portal"
        )
        #expect(asserted.assertedBy == "a hosted portal")
    }
}
