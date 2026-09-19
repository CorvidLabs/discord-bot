import Foundation

/// Mulberry32, ported literally from the JavaScript engine these games came from.
///
/// A literal port rather than a Swift stdlib generator, because a seed has to deal
/// the same shoe wherever it is replayed. The 32-bit wrapping arithmetic below
/// reproduces `|0`, `Math.imul` and `>>>` exactly, so a stored seed still means one
/// specific sequence of cards and finds rather than "some sequence".
///
/// It is a value type. A draw mutates the state in place, so anything that deals
/// holds the generator as `var` and passes it `inout`.
public struct GameRNG: Sendable, Equatable, Codable {

    // MARK: - Properties

    /// The 32-bit state. Advances by one step per draw, which is enough to store a
    /// half-played table and pick it up exactly where it stopped.
    public private(set) var state: UInt32

    // MARK: - Initializers

    /// Starts a stream at `seed`.
    ///
    /// - Parameter seed: Any 32-bit value. The same seed always yields the same
    ///   sequence, which is the whole contract of this type.
    public init(seed: UInt32) {
        self.state = seed
    }

    // MARK: - Public Methods

    /// Next draw in `[0, 1)`.
    ///
    /// `&+` and `&*` are the wrapping forms JavaScript gets for free from `|0` and
    /// `Math.imul`; the final divide by 2^32 matches the original's `>>> 0`
    /// divided by the same power of two. Both sides of that divide are exact in a
    /// `Double`, so the port is comparable bit for bit rather than within a
    /// tolerance.
    public mutating func next() -> Double {
        state = state &+ 0x6d2b_79f5
        var mixed: UInt32 = (state ^ (state >> 15)) &* (state | 1)
        mixed = (mixed &+ ((mixed ^ (mixed >> 7)) &* (mixed | 61))) ^ mixed
        return Double(mixed ^ (mixed >> 14)) / 4_294_967_296.0
    }

    /// A draw in `0..<upperBound`, floored the way `Math.floor(rand() * n)` is.
    ///
    /// Always consumes one draw, even for an empty range, so a caller that guards
    /// its own bounds cannot knock the shared stream out of step. Spending a draw
    /// and discarding it is cheap; spending one fewer than the replay expects
    /// silently changes every card after it.
    public mutating func int(below upperBound: Int) -> Int {
        let roll = next()
        guard upperBound > 0 else { return 0 }
        let scaled = (roll * Double(upperBound)).rounded(.down)
        if scaled <= 0 { return 0 }
        return min(Int(scaled), upperBound - 1)
    }

    /// A fresh 32-bit seed derived from one draw, for handing a sub-game its own
    /// stream.
    public mutating func seed32() -> UInt32 {
        let scaled = (next() * Double(UInt32.max)).rounded(.down)
        if scaled <= 0 { return 0 }
        return UInt32(min(scaled, Double(UInt32.max)))
    }
}

/// Seeded shuffling and weighted picks.
///
/// Both helpers take the generator `inout` so a caller can deal several times from
/// one stream and still replay the whole table from the seed it started with.
public enum GameShuffle: Sendable {

    // MARK: - Public Methods

    /// Copy-shuffle, walking `index` down from the end and swapping with `0...index`.
    ///
    /// The direction and the `index + 1` bound are the JavaScript's, not an
    /// arbitrary choice: any other order consumes the same draws differently, and
    /// two implementations of "shuffle" that disagree about draw order stop
    /// agreeing about shoes.
    ///
    /// - Parameters:
    ///   - items: The order the shuffle is applied to. Part of the contract, since
    ///     a seed permutes this exact arrangement.
    ///   - rng: The stream to spend draws from.
    /// - Returns: A permutation of `items`.
    public static func fisherYates<Element>(_ items: [Element], using rng: inout GameRNG) -> [Element] {
        var result = items
        var index = result.count - 1
        while index > 0 {
            let swap = rng.int(below: index + 1)
            result.swapAt(index, swap)
            index -= 1
        }
        return result
    }

    /// Index picked in proportion to `weights`, consuming exactly one draw.
    ///
    /// Walks the weights in order subtracting each from `rand() * total` and takes
    /// the first index that drives the remainder negative, so a zero weight can
    /// never be picked. That is load-bearing: a loot kind sits at weight zero until
    /// somebody's configuration gives it one, and "never" has to mean never.
    ///
    /// Nothing falls out of the walk onto a zero. A table that never drives the
    /// remainder negative, whether because every weight is zero or because of a
    /// rounding residue at the very top of the range, answers the last index
    /// carrying a positive weight rather than the last index outright, because the
    /// last index is exactly where a locked kind tends to sit. With no positive
    /// weight anywhere there is nothing honest to pick, so it answers the first
    /// index: the commonest thing in every table this package deals, rather than
    /// the rarest. Empty weights have no index to return and answer `0`; callers
    /// check first.
    ///
    /// - Parameters:
    ///   - weights: Non-negative, finite, read positionally.
    ///   - rng: The stream to spend one draw from.
    /// - Returns: An index into `weights`.
    public static func pickIndex(_ weights: [Double], using rng: inout GameRNG) -> Int {
        let total = weights.reduce(0.0) { $0 + $1 }
        var remainder = rng.next() * total
        for index in weights.indices {
            remainder -= weights[index]
            if remainder < 0 {
                return index
            }
        }
        return lastPositiveIndex(weights)
    }

    // MARK: - Private Methods

    /// The last index carrying a weight above zero, or `0` when none does.
    private static func lastPositiveIndex(_ weights: [Double]) -> Int {
        for index in weights.indices.reversed() where weights[index] > 0 {
            return index
        }
        return 0
    }
}
