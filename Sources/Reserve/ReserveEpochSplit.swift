import Foundation

/// How one slot's whole-schedule share is cut into epochs.
///
/// A share rarely divides evenly by the epoch count. There are two ways to
/// handle that and only one of them is defensible.
///
/// The tempting way is to spread the remainder: pay a few epochs one unit more
/// so the total comes out exact. Then every epoch is a slightly different
/// number, nobody can be told what they will receive, and the figure quoted in
/// the first epoch is wrong by the last.
///
/// This is the other way. **Every epoch pays the identical floored figure**, and
/// what will not divide is a residue that is never paid and never hidden: it is
/// stated, and paid plus residue equals the share exactly. The residue is
/// usually tiny — twenty smallest units per slot, a fifty-thousandth of a whole
/// unit — but it is accounted for rather than swallowed, because an amount that
/// cannot be reconciled is an amount somebody will eventually accuse you of
/// taking.
public struct ReserveEpochSplit: Sendable, Equatable {

    // MARK: - Properties

    /// The stream this split spends.
    public let streamId: String

    /// Epochs the share was cut for.
    public let epochCount: UInt64

    /// Smallest units every epoch pays. The same number in every epoch.
    public let perEpochBaseUnits: UInt64

    /// Smallest units of the share that will not divide. Never paid.
    public let residueBaseUnits: UInt64

    // MARK: - Initializers

    public init(
        streamId: String,
        epochCount: UInt64,
        perEpochBaseUnits: UInt64,
        residueBaseUnits: UInt64
    ) {
        self.streamId = streamId
        self.epochCount = epochCount
        self.perEpochBaseUnits = perEpochBaseUnits
        self.residueBaseUnits = residueBaseUnits
    }

    // MARK: - Public Methods

    /// Smallest units one slot is paid in `epoch`, numbered from 1.
    ///
    /// The same number in every epoch of the schedule. It does not depend on how
    /// many are eligible, on what earlier epochs paid, or on the epoch number.
    /// An epoch outside the schedule pays nothing rather than being clamped into
    /// range, so a caller's off-by-one cannot become a payment.
    public func payout(epoch: UInt64) -> UInt64 {
        guard epoch >= 1, epoch <= epochCount else { return 0 }
        return perEpochBaseUnits
    }

    /// Every epoch's payout summed: what one slot actually receives.
    ///
    /// For a split built by ``ReserveConfiguration`` this cannot overflow, since
    /// `perEpochBaseUnits` is the share floor-divided by `epochCount` and the
    /// product is therefore at most the share. The saturation exists only so a
    /// hand-built split cannot trap the process.
    public var totalBaseUnits: UInt64 {
        let (product, overflow) = perEpochBaseUnits.multipliedReportingOverflow(by: epochCount)
        return overflow ? UInt64.max : product
    }

    /// `totalBaseUnits + residueBaseUnits`: one slot's nominal share.
    public var shareBaseUnits: UInt64 {
        let (sum, overflow) = totalBaseUnits.addingReportingOverflow(residueBaseUnits)
        return overflow ? UInt64.max : sum
    }

    /// True when the share divides evenly and nothing stays behind.
    public var isEven: Bool { residueBaseUnits == 0 }

    /// One line an operator can check the arithmetic against.
    ///
    /// Takes the asset so the residue is printed both as raw units and as the
    /// amount a person recognises. Both matter: the raw count is what
    /// reconciles, the amount is what reassures.
    public func residueNote(asset: ReserveAsset, unitName: String) -> String {
        guard residueBaseUnits > 0 else {
            return "Divides evenly across \(epochCount) epochs; no residue."
        }
        return "Every epoch pays the same \(asset.formatWithSymbol(perEpochBaseUnits)). "
            + "\(ReserveFormatting.grouped(residueBaseUnits)) smallest unit(s) per \(unitName) "
            + "(\(asset.formatWithSymbol(residueBaseUnits))) will not divide into \(epochCount) epochs "
            + "and are never paid; they stay in the reserve."
    }
}
