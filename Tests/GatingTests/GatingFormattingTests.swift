import Foundation
import Testing
@testable import Gating

/// Writing amounts out, and keeping a card inside what Discord will accept.
@Suite("Formatting")
struct GatingFormattingTests {

    // MARK: - Amounts

    @Test("An amount keeps every digit, at whatever precision the asset has")
    func amountsKeepTheirDigits() {
        #expect(GatingFormatting.amount(269_230_769_230, decimals: 6) == "269,230.76923")
        #expect(GatingFormatting.amount(1_500_000, decimals: 6) == "1.5")
        #expect(GatingFormatting.amount(1_000_000, decimals: 6) == "1")
        #expect(GatingFormatting.amount(1, decimals: 6) == "0.000001")
        #expect(GatingFormatting.amount(1_234, decimals: 2) == "12.34")
        #expect(GatingFormatting.amount(1_234, decimals: 0) == "1,234")
    }

    @Test("A silly precision answers with the raw units rather than taking the process down")
    func absurdPrecision() {
        // Ten to the twentieth overflows and the multiply traps, which would
        // end the process rather than the card.
        #expect(GatingFormatting.amount(1_234, decimals: 20) == "1,234")
        #expect(GatingFormatting.amount(1_234, decimals: -1) == "1,234")
    }

    @Test("Grouping is the same on every machine, because it is not a formatter")
    func grouping() {
        #expect(GatingFormatting.grouped(0) == "0")
        #expect(GatingFormatting.grouped(999) == "999")
        #expect(GatingFormatting.grouped(1_000) == "1,000")
        #expect(GatingFormatting.grouped(1_234_567) == "1,234,567")
    }

    @Test("The short form is for a glance and never for money")
    func compactIsLossy() {
        // Kept, and kept labelled. The exact figure and the short one are
        // both wanted, in different places, and the whole danger is somebody
        // reaching for this one when they meant the other.
        #expect(GatingFormatting.compact(1_500_000_000, decimals: 6) == "1.5K")
        #expect(GatingFormatting.compact(269_230_769_230, decimals: 6) == "269K")
        #expect(GatingFormatting.compact(1_000_000, decimals: 6) == "1")
        // The same amount, written the way an operator can check it.
        #expect(GatingFormatting.amount(269_230_769_230, decimals: 6) == "269,230.76923")
    }

    @Test("The short form never shows more than is held")
    func compactTruncates() {
        // 1.999 rounds to 2.00 and truncates to 1.99. Showing somebody more
        // than they have is the one direction that is not merely untidy.
        #expect(GatingFormatting.compact(1_999_999, decimals: 6) == "1.99")
    }

    // MARK: - Payload bounds

    @Test("Text too long for Discord is cut and says it was cut")
    func clamping() {
        let long = String(repeating: "a", count: 300)
        let clamped = GatingFormatting.clamp(long, to: DiscordPayloadLimit.embedTitle)
        #expect(clamped.count == DiscordPayloadLimit.embedTitle)
        #expect(clamped.hasSuffix("..."))
        #expect(GatingFormatting.clamp("short", to: 100) == "short")
        #expect(GatingFormatting.clamp("short", to: 0) == "")
        #expect(GatingFormatting.clamp("short", to: 2) == "sh")
    }

    @Test("A list that will not fit loses whole lines and counts them, rather than being cut mid-word")
    func joining() {
        // A line cut in half reads as a rendering bug. "and 4 more" reads as
        // intent, which is what it is.
        let lines = (1...10).map { "line \($0)" }
        let joined = GatingFormatting.joinWithinLimit(lines, limit: 40)
        #expect(joined.count <= 40)
        #expect(joined.contains("more"))
        #expect(joined.hasPrefix("line 1"))

        let all = GatingFormatting.joinWithinLimit(lines, limit: 1_000)
        #expect(all.contains("more") == false)
        #expect(GatingFormatting.joinWithinLimit([], limit: 10) == "")
    }

    @Test("A single line longer than the whole limit is clamped rather than dropped")
    func oneEnormousLine() {
        let joined = GatingFormatting.joinWithinLimit([String(repeating: "a", count: 200)], limit: 20)
        #expect(joined.count == 20)
        #expect(joined.hasSuffix("..."))
    }
}
