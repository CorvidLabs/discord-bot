import Foundation
import Testing

@testable import Surface

/// Payload bounds, in the unit Discord counts in.
@Suite("Reply bounds")
struct ReplyBoundsTests {

    // MARK: - The unit

    @Test("A thumbs-up is one character and two code units, and the limit is the code units")
    func thumbsUpIsTwoUnits() {
        let thumb = "\u{1F44D}"
        #expect(thumb.count == 1)
        #expect(ReplyLimits.length(thumb) == 2)

        // A thousand of them is a thousand `Character`s, which passes any
        // `count` check against the two thousand character message limit,
        // and two thousand code units, which is exactly at Discord's. One
        // more is refused there, and because the handler has already
        // deferred, the member sees a thinking indicator that never resolves.
        let thousand = String(repeating: thumb, count: 1_000)
        #expect(thousand.count == 1_000)
        #expect(ReplyLimits.fits(thousand, within: ReplyLimits.messageContent))

        let oneMore = thousand + thumb
        #expect(oneMore.count == 1_001)
        #expect(ReplyLimits.fits(oneMore, within: ReplyLimits.messageContent) == false)
    }

    @Test("Clamping never splits a character, and never exceeds the limit")
    func clampKeepsCharactersWhole() {
        let thumbs = String(repeating: "\u{1F44D}", count: 10)
        let clamped = ReplyLimits.clamp(thumbs, to: 10)
        #expect(ReplyLimits.length(clamped) <= 10)
        #expect(clamped.hasSuffix("\u{2026}"))
        // Four whole thumbs (eight units) plus the marker. A cut at UTF-16
        // index nine would leave half a surrogate pair, which is not a
        // shorter message but an invalid one.
        #expect(clamped == String(repeating: "\u{1F44D}", count: 4) + "\u{2026}")
    }

    @Test("Text that already fits is returned untouched")
    func shortTextIsUnchanged() {
        #expect(ReplyLimits.clamp("short", to: 100) == "short")
    }

    @Test("A limit too small for the marker gives the marker or nothing, never half of one")
    func tinyLimits() {
        #expect(ReplyLimits.clamp("abcdef", to: 1) == "\u{2026}")
        #expect(ReplyLimits.clamp("abcdef", to: 0) == "")
    }

    // MARK: - Lists

    @Test("A list drops whole lines and says how many went (RAIN-1.d)")
    func listsDropWholeLines() {
        let lines = (1...50).map { "line number \($0)" }
        let joined = ReplyLimits.joinWithinLimit(lines, limit: 80)
        #expect(ReplyLimits.length(joined) <= 80)
        #expect(joined.contains("more"))
        // No line is cut in half: every line kept is one of the originals.
        for line in joined.components(separatedBy: "\n") where !line.hasPrefix("and ") {
            #expect(lines.contains(line))
        }
    }

    @Test("A list of links too long for even one is dropped whole rather than sliced")
    func urlListsAreNotSliced() {
        // Half a receipt link is a link to nothing, and a member who taps it
        // learns less than one told the list did not fit.
        let links = ["https://explorer.example.test/tx/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]
        let joined = ReplyLimits.joinWithinLimit(links, limit: 20, sliceable: false)
        #expect(joined == "and 1 more")
        #expect(joined.contains("https") == false)
    }

    // MARK: - Refuse or clamp

    @Test("A long card is clamped and still sent")
    func longCardIsClamped() {
        let card = SurfaceCard(title: String(repeating: "t", count: 300), description: "body")
        let outcome = ReplyBounds.enforce(VisibleMessage(card: card))
        guard case .clamped(let bounded) = outcome else {
            Issue.record("expected a clamp, got \(outcome)")
            return
        }
        #expect(ReplyLimits.fits(bounded.card?.title ?? "", within: ReplyLimits.embedTitle))
    }

    @Test("A payload whose shortened form would still read as complete is refused, not cut")
    func refusedRatherThanCut() {
        let message = VisibleMessage(
            content: String(repeating: "a", count: 2_100),
            truncation: .refuse
        )
        guard case .refused(let reason) = ReplyBounds.enforce(message) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("2100"))
        #expect(reason.contains("2000"))
    }

    @Test("An over-long custom id is refused whatever the policy, because a clamped id routes to nobody")
    func overLongCustomIdIsRefused() {
        let card = SurfaceCard(
            title: "Card",
            buttons: [ButtonSpec(id: String(repeating: "x", count: 200), label: "Go")]
        )
        guard case .refused = ReplyBounds.enforce(VisibleMessage(card: card, truncation: .clamp)) else {
            Issue.record("expected a refusal")
            return
        }
    }

    @Test("A card that fits comes back exactly as written")
    func withinIsUntouched() {
        let card = SurfaceCard(title: "Title", description: "Body", fields: [
            SurfaceField(name: "One", value: "Two")
        ])
        let message = VisibleMessage(card: card)
        guard case .within(let bounded) = ReplyBounds.enforce(message) else {
            Issue.record("expected it to fit")
            return
        }
        #expect(bounded == message)
    }

    @Test("Fields past Discord's cap are dropped from the end, keeping what the builder put first")
    func fieldCapKeepsTheTop() {
        let fields = (1...30).map { SurfaceField(name: "F\($0)", value: "v") }
        let outcome = ReplyBounds.enforce(VisibleMessage(card: SurfaceCard(title: "T", fields: fields)))
        guard case .clamped(let bounded) = outcome else {
            Issue.record("expected a clamp")
            return
        }
        #expect(bounded.card?.fields.count == ReplyLimits.embedFieldCount)
        #expect(bounded.card?.fields.first?.name == "F1")
    }

    @Test("Under refuse, a card with too many fields is not sent with the rest missing")
    func fieldCapIsRefusedRatherThanCut() {
        // A receipt whose last recipients were dropped reads as a complete
        // receipt, which is the whole reason `refuse` exists (REQ-surface-011).
        let fields = (1...30).map { SurfaceField(name: "F\($0)", value: "v") }
        let outcome = ReplyBounds.enforce(VisibleMessage(
            card: SurfaceCard(title: "T", fields: fields),
            truncation: .refuse
        ))
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains("30"))
        #expect(reason.contains("25"))
    }

    @Test("Under refuse, a card with too many buttons is not sent with the rest missing")
    func buttonCapIsRefusedRatherThanCut() {
        let buttons = (1...30).map { ButtonSpec(id: "b\($0)", label: "B\($0)") }
        let outcome = ReplyBounds.enforce(VisibleMessage(
            card: SurfaceCard(title: "T", buttons: buttons),
            truncation: .refuse
        ))
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains("30"))
    }

    @Test("Under refuse, an embed over the total is not sent with its last sections gone")
    func totalIsRefusedRatherThanCut() {
        let fields = (1...10).map {
            SurfaceField(name: "F\($0)", value: String(repeating: "x", count: 1_000))
        }
        let outcome = ReplyBounds.enforce(VisibleMessage(
            card: SurfaceCard(title: "T", fields: fields),
            truncation: .refuse
        ))
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains("6000"))
    }

    @Test("Every part passing while the whole embed does not is still caught")
    func totalIsChecked() {
        // Ten fields of a thousand each is under every per-field limit and
        // over the six thousand Discord adds them up to.
        let fields = (1...10).map {
            SurfaceField(name: "F\($0)", value: String(repeating: "x", count: 1_000))
        }
        let outcome = ReplyBounds.enforce(VisibleMessage(card: SurfaceCard(title: "T", fields: fields)))
        guard case .clamped(let bounded) = outcome, let card = bounded.card else {
            Issue.record("expected a clamp")
            return
        }
        let total = ReplyLimits.length(card.title) + ReplyLimits.length(card.description)
            + card.fields.reduce(0) { $0 + ReplyLimits.length($1.name) + ReplyLimits.length($1.value) }
        #expect(total <= ReplyLimits.embedTotal)
    }
}
