import Foundation
import Testing
@testable import Games

/// The generator, pinned to the sequence the engine this was ported from produces.
///
/// The property under test is not "does it produce random numbers". It is "does
/// this exact seed produce this exact sequence", because that is the only thing
/// that makes a stored table replayable and a rule provable.
@Suite("Game generator")
struct GameRNGTests {

    /// The exact 32-bit values the JavaScript mulberry32 yields for seed 42, before
    /// it divides by 2^32. Both sides of that divide are exact in a `Double`, so
    /// the port is compared bit for bit rather than within a tolerance.
    private let seed42Raw: [Double] = [
        2_581_720_956, 1_925_393_290, 3_661_312_704, 2_876_485_805, 750_819_978
    ]

    @Test("The same seed deals the same stream, value for value")
    func sequenceReplays() {
        var rng = GameRNG(seed: 42)
        var drawn: [Double] = []
        for _ in seed42Raw {
            drawn.append(rng.next())
        }
        #expect(drawn == seed42Raw.map { $0 / 4_294_967_296.0 })

        var again = GameRNG(seed: 42)
        var replayed: [Double] = []
        for _ in seed42Raw {
            replayed.append(again.next())
        }
        #expect(replayed == drawn)
    }

    @Test("Every draw lands in [0, 1) and two seeds do not agree")
    func rangeAndSeeds() {
        var rng = GameRNG(seed: 7)
        for _ in 0..<200 {
            let draw = rng.next()
            #expect(draw >= 0)
            #expect(draw < 1)
        }

        var left = GameRNG(seed: 42)
        var right = GameRNG(seed: 43)
        #expect(left.next() != right.next())
    }

    @Test("A bounded draw and a forked seed follow the same stream")
    func derivedDraws() {
        var seeds = GameRNG(seed: 0)
        var forked: [UInt32] = []
        for _ in 0..<3 {
            forked.append(seeds.seed32())
        }
        #expect(forked == [1_144_304_737, 1_416_246, 958_946_055])

        var rolls = GameRNG(seed: 99)
        let ten: [Int] = (0..<8).map { _ in rolls.int(below: 10) }
        #expect(ten == [2, 8, 5, 6, 0, 8, 0, 1])
        #expect(ten.allSatisfy { $0 >= 0 && $0 < 10 })
    }

    @Test("An impossible bound still spends its draw, so the stream stays in step")
    func emptyBoundSpendsADraw() {
        var rng = GameRNG(seed: 99)
        #expect(rng.int(below: 0) == 0)
        #expect(rng.state == Fixture.stateAfterDraws(seed: 99, times: 1))
        #expect(rng.int(below: -5) == 0)
        #expect(rng.state == Fixture.stateAfterDraws(seed: 99, times: 2))
    }

    @Test("A stored generator picks the stream up exactly where it stopped")
    func codableRoundTrip() throws {
        var rng = GameRNG(seed: 21)
        _ = rng.next()
        let data = try JSONEncoder().encode(rng)
        var restored = try JSONDecoder().decode(GameRNG.self, from: data)
        #expect(restored == rng)
        #expect(restored.next() == rng.next())
    }

    @Test("A shuffle is a permutation, and the same seed permutes it the same way")
    func shuffleReplays() {
        let source: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        var rng = GameRNG(seed: 42)
        let shuffled = GameShuffle.fisherYates(source, using: &rng)
        #expect(shuffled.sorted() == source)
        #expect(shuffled == [0, 7, 3, 5, 2, 1, 8, 9, 4, 6])

        var replay = GameRNG(seed: 42)
        #expect(GameShuffle.fisherYates(source, using: &replay) == shuffled)

        var other = GameRNG(seed: 7)
        #expect(GameShuffle.fisherYates(source, using: &other) == [6, 5, 8, 1, 2, 3, 4, 7, 9, 0])

        var untouched = GameRNG(seed: 1)
        #expect(GameShuffle.fisherYates([Int](), using: &untouched).isEmpty)
    }

    @Test("A weight of zero is never picked, however many times you ask")
    func zeroWeightsAreUnreachable() {
        var rng = GameRNG(seed: 5)
        let picks: [Int] = (0..<10).map { _ in GameShuffle.pickIndex([1, 0, 1], using: &rng) }
        #expect(picks == [2, 2, 0, 2, 0, 2, 2, 0, 2, 0])
        #expect(!picks.contains(1))

        var trailing = GameRNG(seed: 5)
        #expect((0..<5).map { _ in GameShuffle.pickIndex([1, 0], using: &trailing) } == [0, 0, 0, 0, 0])
    }

    @Test("Weights that add to nothing answer the first index, never the last")
    func degenerateWeights() {
        // The last index is where a locked kind sits: a zero-weight table that fell
        // through to it handed out the rarest thing in the table every single time.
        // With nothing positive to pick, the answer is the first index.
        var allZero = GameRNG(seed: 5)
        #expect((0..<3).map { _ in GameShuffle.pickIndex([0, 0, 0], using: &allZero) } == [0, 0, 0])

        // And a table whose only positive weight is not the last one never answers
        // a zero either, whichever way the walk ends.
        var trailingZeroes = GameRNG(seed: 5)
        #expect((0..<5).map { _ in GameShuffle.pickIndex([1, 0, 0, 0], using: &trailingZeroes) } == [0, 0, 0, 0, 0])

        var single = GameRNG(seed: 11)
        #expect(GameShuffle.pickIndex([3], using: &single) == 0)

        var bare = GameRNG(seed: 11)
        #expect(GameShuffle.pickIndex([], using: &bare) == 0)
    }

    @Test("A weighted pick costs exactly one draw")
    func pickSpendsOneDraw() {
        var rng = GameRNG(seed: 5)
        _ = GameShuffle.pickIndex([1, 2, 3], using: &rng)
        #expect(rng.state == Fixture.stateAfterDraws(seed: 5, times: 1))
    }
}
