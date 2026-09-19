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

    @Test("A precision no divisor could hold is still written out exactly")
    func precisionPastADivisor() {
        // Dividing needed ten to the power of the precision to fit in a
        // UInt64, so twenty places answered with the smallest units
        // themselves: 1,234 hundred-quintillionths printed as 1,234 whole
        // ones, a hundred quintillion times too large, and nothing said. The
        // point is moved through the digits now, so there is no ceiling to
        // fall off.
        #expect(GatingFormatting.amount(1_234, decimals: 20) == "0.00000000000000001234")
        #expect(GatingFormatting.amount(UInt64.max, decimals: 19) == "1.8446744073709551615")
        #expect(GatingFormatting.amount(UInt64.max, decimals: 20) == "0.18446744073709551615")
        #expect(GatingFormatting.amount(1, decimals: 255) == "0." + String(repeating: "0", count: 254) + "1")

        // A precision of none is not a silly precision: a zero-decimal asset
        // holds whole units in its smallest unit, and that is all of them.
        #expect(GatingFormatting.amount(1_234, decimals: 0) == "1,234")

        // Below zero there is no honest answer, so `UInt8` means there is no
        // question: `GatingFormatting.amount(1_234, decimals: -1)` no longer
        // compiles, where it used to answer "1,234".
    }

    @Test("An amount keeps its grouping on the whole side and every digit on the fraction side")
    func groupingAndFractionTogether() {
        #expect(GatingFormatting.amount(1_234_567_000_001, decimals: 6) == "1,234,567.000001")
        #expect(GatingFormatting.amount(0, decimals: 6) == "0")
        #expect(GatingFormatting.amount(UInt64.max, decimals: 6) == "18,446,744,073,709.551615")
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
