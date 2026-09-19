import Foundation
import Testing
@testable import Chain

/// An incomplete reading is not an empty one.
///
/// This is the suite that protects people from being demoted for something
/// that happened to the network. Every case here is one where a failure and a
/// real zero look identical from the outside, and the whole design exists to
/// keep them apart.
@Suite("An incomplete reading is not an empty one")
internal struct IncompleteReadingTests {

    // MARK: - The reading itself

    @Test("A complete reading hands over its number")
    internal func completeReadingGivesItsValue() throws {
        let reading = ChainReading<UInt64>.complete(500)
        #expect(reading.isComplete)
        #expect(reading.completeValue == 500)
        #expect(try reading.requireComplete() == 500)
        #expect(reading.gaps.isEmpty)
    }

    @Test("A short reading refuses to hand over a number that may be acted on")
    internal func shortReadingWithholdsItsValue() {
        let reading = ChainReading<UInt64>.short(500, gaps: [.poolReservesUnavailable(poolId: "pair-one")])
        #expect(reading.isComplete == false)
        // The number exists, and getting at it takes a name that says what it
        // is. That is the difference between reading it on a card and deciding
        // somebody's roles with it.
        #expect(reading.completeValue == nil)
        #expect(reading.valueEvenIfShort == 500)
        #expect(throws: ChainError.incompleteRead(gaps: [.poolReservesUnavailable(poolId: "pair-one")])) {
            _ = try reading.requireComplete()
        }
    }

    @Test("A reading that never arrived has no number at all")
    internal func unavailableReadingHasNothing() {
        let reading = ChainReading<UInt64>.unavailable(gaps: [.requestFailed("timed out")])
        #expect(reading.completeValue == nil)
        #expect(reading.valueEvenIfShort == nil)
        #expect(reading.gaps == [.requestFailed("timed out")])
    }

    @Test("Completeness survives being transformed, so nothing looks whole again on the way out")
    internal func mappingKeepsCompleteness() {
        let short = ChainReading<UInt64>.short(2, gaps: [.budgetSpent])
        let doubled = short.map { $0 * 2 }
        #expect(doubled.valueEvenIfShort == 4)
        #expect(doubled.isComplete == false)
        #expect(doubled.gaps == [.budgetSpent])
    }

    @Test("What was missing is named in words an operator can act on")
    internal func gapsExplainThemselves() {
        #expect(ChainReadGap.budgetSpent.summary.contains("budget"))
        #expect(ChainReadGap.poolReservesUnavailable(poolId: "pair-one").summary.contains("pair-one"))
        #expect(ChainReadGap.notRead.summary.contains("never"))
        #expect(ChainReadGap.requestFailed("timed out").summary.contains("timed out"))
    }

    // MARK: - Deciding a tier

    @Test("A tier is not recalculated from a total that is short by an unknown amount")
    internal func cannotDecideATierOnAShortTotal() {
        #expect(
            LiquidityCompleteness.canDecideTier(
                liquidityIncomplete: true,
                cacheSuppliedLiquidity: false
            ) == false
        )
    }

    @Test("A stored figure standing in for the missing pool makes the total whole again")
    internal func storedFiguresRestoreCompleteness() {
        #expect(LiquidityCompleteness.canDecideTier(liquidityIncomplete: true, cacheSuppliedLiquidity: true))
        #expect(LiquidityCompleteness.canDecideTier(liquidityIncomplete: false, cacheSuppliedLiquidity: false))
    }

    // MARK: - Granting and taking away a collection role

    @Test("Holding one of them grants the role even when another wallet could not be read")
    internal func grantingOnAPartialPositive() {
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: false,
                heldNothing: false,
                registryAnswered: true,
                matchCount: 1
            ) == true
        )
    }

    @Test("A wallet that could not be read never takes a collection role away")
    internal func strippingNeedsACompleteNegative() {
        // Nil is 'leave the member exactly as they are'. A role that flickers
        // off on a bad sweep and back on the next one is worse than one that
        // is a sweep out of date.
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: false,
                heldNothing: true,
                registryAnswered: true
            ) == nil
        )
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: false,
                heldNothing: false,
                registryAnswered: true,
                matchCount: 0
            ) == nil
        )
    }

    @Test("A complete read of somebody holding none of them does take the role away")
    internal func completeNegativeStrips() {
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: true,
                heldNothing: true,
                registryAnswered: true
            ) == false
        )
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: true,
                heldNothing: false,
                registryAnswered: true,
                matchCount: 0
            ) == false
        )
    }

    @Test("A catalogue that did not answer decides nothing either way")
    internal func registrySilenceDecidesNothing() {
        #expect(
            CollectionCompleteness.decidedHoldsCollection(
                holdingsComplete: true,
                heldNothing: false,
                registryAnswered: false,
                matchCount: 5
            ) == nil
        )
    }

    // MARK: - Writing a reading down

    @Test("A failed read is never written down as a wallet that holds nothing")
    internal func incompleteReadsAreNotStored() {
        #expect(
            HoldingsCacheWrite.persistableAssetIds(holdingsIncomplete: true, heldAssetIds: []) == nil
        )
        #expect(
            HoldingsCacheWrite.persistableAssetIds(
                holdingsIncomplete: true,
                heldAssetIds: [Fixture.collectibleId]
            ) == nil
        )
    }

    @Test("A completed read is written down, including a wallet that really holds nothing")
    internal func completeReadsAreStored() {
        #expect(HoldingsCacheWrite.persistableAssetIds(holdingsIncomplete: false, heldAssetIds: []) == [])
        #expect(
            HoldingsCacheWrite.persistableAssetIds(
                holdingsIncomplete: false,
                heldAssetIds: [Fixture.collectibleId]
            ) == [Fixture.collectibleId]
        )
    }

    @Test("The same rule reads straight off a reading, so a caller cannot get it wrong")
    internal func cacheWriteFromAReading() {
        #expect(HoldingsCacheWrite.persistableAssetIds(from: .complete([Fixture.collectibleId]))
            == [Fixture.collectibleId])
        #expect(HoldingsCacheWrite.persistableAssetIds(from: .unavailable(gaps: [.budgetSpent])) == nil)
        #expect(HoldingsCacheWrite.persistableAssetIds(from: .short([], gaps: [.budgetSpent])) == nil)
    }
}
