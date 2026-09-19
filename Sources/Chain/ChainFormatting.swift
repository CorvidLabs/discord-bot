import Foundation

/// Writing integer smallest units out for a person to read.
///
/// Nothing here touches `Double`, `NumberFormatter` or a locale. An operator
/// reconciling a balance against what a wallet shows them is checking digits: a
/// formatter that shortens the number, or that swaps the separators because the
/// process happens to be running in another locale, has destroyed the only
/// evidence they had.
///
/// Deliberately a copy of the same idea in the payout engine rather than a
/// shared dependency. This layer knows about the chain and that layer knows
/// about money, and neither should have to import the other to print a number.
public enum ChainFormatting: Sendable {

    // MARK: - Public Methods

    /// `1234567` as `1,234,567`.
    ///
    /// Hand rolled because `NumberFormatter` is locale sensitive and, on Linux,
    /// not identical to its Darwin counterpart.
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
    /// - Parameters:
    ///   - baseUnits: The amount, in the asset's smallest unit.
    ///   - decimals: How many decimal places that asset has. Configuration,
    ///     never a literal: an asset with two decimals printed as though it had
    ///     six is wrong by a factor of ten thousand.
    /// - Returns: The amount as grouped digits, with a fraction only when there
    ///   is one.
    public static func amount(_ baseUnits: UInt64, decimals: Int) -> String {
        // Ten to the twentieth overflows `UInt64` and `*=` traps, taking the
        // process with it. A nonsensical `decimals` is answered with the raw
        // units rather than a crash.
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

    /// A share of a pool, in millionths, written as a percentage with four
    /// decimal places.
    ///
    /// Integer arithmetic on the millionths rather than `String(format: "%.4f")`
    /// on a `Double`, so the digits printed are the digits computed.
    public static func percent(millionths: UInt64) -> String {
        let whole = millionths / 10_000
        let fraction = millionths % 10_000
        var digits = String(fraction)
        if digits.count < 4 {
            digits = String(repeating: "0", count: 4 - digits.count) + digits
        }
        return "\(grouped(whole)).\(digits)%"
    }

    /// An address with its middle removed, for a card that has no room for
    /// fifty-eight characters.
    ///
    /// Keeps enough of both ends that two addresses a person holds are still
    /// told apart, which is the whole job.
    public static func shortenAddress(_ address: String, keeping count: Int = 6) -> String {
        guard count > 0, address.count > count * 2 + 3 else { return address }
        return "\(address.prefix(count))...\(address.suffix(count))"
    }
}
