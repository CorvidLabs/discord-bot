import Foundation

/// Writing integer smallest units out for a person to read.
///
/// None of this touches `Double`, `NumberFormatter` or a locale, and that is the
/// whole point rather than a stylistic preference. A weekly share of
/// 269,230.76923 is a number an operator reconciles against an allocation by
/// hand; a formatter that shortens it to `269K`, or that swaps the separators
/// because the process happens to be running in another locale, has destroyed
/// the only evidence they had. Floating point cannot represent these values
/// exactly in the first place, so it is never allowed near them.
public enum ReserveFormatting: Sendable {

    // MARK: - Public Methods

    /// `1234567` as `1,234,567`.
    ///
    /// Hand-rolled because `NumberFormatter` is locale-sensitive and, on Linux,
    /// not identical to its Darwin counterpart. A grouping separator that moves
    /// between platforms turns a reconciliation into an argument.
    public static func grouped(_ value: UInt64) -> String {
        let digits = Array(String(value))
        var out: [Character] = []
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                out.append(",")
            }
            out.append(digit)
        }
        return String(out)
    }

    /// Smallest units written as a decimal amount, with no digit lost.
    ///
    /// Trailing zeros of the fraction are trimmed because `269,230.769230` and
    /// `269,230.76923` are the same number and the shorter one is easier to
    /// check. Nothing else is rounded away.
    ///
    /// - Parameters:
    ///   - baseUnits: The amount, in the asset's smallest unit.
    ///   - decimals: How many decimal places that asset has.
    /// - Returns: The amount as digits, grouped, with a fraction only when there
    ///   is one.
    public static func amount(_ baseUnits: UInt64, decimals: Int) -> String {
        // 10^20 overflows `UInt64` and `*=` traps, taking the process with it.
        // A nonsensical `decimals` is answered with the raw units rather than a
        // crash: the caller asked a silly question and gets a truthful answer.
        guard decimals > 0, decimals <= 19 else { return grouped(baseUnits) }
        var divisor: UInt64 = 1
        for _ in 0..<decimals {
            divisor *= 10
        }
        let whole = baseUnits / divisor
        let fraction = baseUnits % divisor
        guard fraction > 0 else { return grouped(whole) }
        var digits = String(fraction)
        if digits.count < decimals {
            digits = String(repeating: "0", count: decimals - digits.count) + digits
        }
        while digits.hasSuffix("0") {
            digits.removeLast()
        }
        return "\(grouped(whole)).\(digits)"
    }
}
