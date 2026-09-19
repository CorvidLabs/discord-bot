@preconcurrency import Foundation
import Testing

@testable import Surface

/// A payout that takes a long time still says how it went (`RAIN-13`).
@Suite("Long-running jobs")
struct JobMailboxTests {

    private let started = Date(timeIntervalSince1970: 1_000)

    private func mailbox(fallback: JobFallback, now: Date) -> JobMailbox {
        JobMailbox(fallback: fallback, now: { now })
    }

    @Test("Inside fifteen minutes the report goes where it was asked for")
    func insideTheWindow() async {
        let box = mailbox(fallback: .directMessageToInvoker, now: started.addingTimeInterval(60))
        await box.start(
            id: JobId("j"),
            invokerExternalId: "100000000000000001",
            token: "t",
            deadline: started.addingTimeInterval(900)
        )
        let delivery = await box.finish(id: JobId("j"), report: VisibleMessage(content: "done"))
        #expect(delivery == .followUp(token: "t", VisibleMessage(content: "done")))
    }

    @Test("Past fifteen minutes the report reaches the person another way (RAIN-13.a)")
    func pastTheWindow() async {
        // The interaction token is gone. Without a fallback the person who
        // pressed the button never learns whether their money moved.
        let box = mailbox(fallback: .directMessageToInvoker, now: started.addingTimeInterval(1_000))
        await box.start(
            id: JobId("j"),
            invokerExternalId: "100000000000000001",
            token: "t",
            deadline: started.addingTimeInterval(900)
        )
        let delivery = await box.finish(id: JobId("j"), report: VisibleMessage(content: "done"))
        #expect(delivery == .directMessage(
            externalId: "100000000000000001",
            VisibleMessage(content: "done")
        ))
    }

    @Test("An operator channel is used when one was named, and none is invented when one was not")
    func fallbackDestination() async {
        let named = mailbox(fallback: .channel(id: "channel-9"), now: started.addingTimeInterval(1_000))
        await named.start(id: JobId("j"), invokerExternalId: "1", token: "t", deadline: started)
        #expect(await named.finish(id: JobId("j"), report: VisibleMessage(content: "x"))
            == .channel(id: "channel-9", VisibleMessage(content: "x")))

        // No default channel: one this package picked would be a channel
        // somebody else chose (ADOPT-6.a).
        let none = mailbox(fallback: .none, now: started.addingTimeInterval(1_000))
        await none.start(id: JobId("k"), invokerExternalId: "1", token: "t", deadline: started)
        #expect(await none.finish(id: JobId("k"), report: VisibleMessage(content: "x"))
            == .undeliverable(JobId("k")))
    }

    @Test("Losing the report never loses the record of the work (RAIN-13.b)")
    func theRecordSurvivesTheDelivery() async {
        let box = mailbox(fallback: .none, now: started.addingTimeInterval(1_000))
        await box.start(id: JobId("j"), invokerExternalId: "1", token: "t", deadline: started)
        _ = await box.finish(id: JobId("j"), report: VisibleMessage(content: "paid 12"))

        // Nobody could be told. The outcome is still here to read.
        let record = await box.record(id: JobId("j"))
        #expect(record?.report == VisibleMessage(content: "paid 12"))
    }

    @Test("Finishing a job nobody started answers rather than throwing away a report in hand")
    func unknownJobIsAnswered() async {
        let box = mailbox(fallback: .directMessageToInvoker, now: started)
        #expect(await box.finish(id: JobId("ghost"), report: VisibleMessage(content: "x"))
            == .undeliverable(JobId("ghost")))
    }
}
