import Chain
import Foundation
import Gating

extension GatingConfigurationError {

    // MARK: - Internal Methods

    /// The variable this refusal is about, when it is about one.
    ///
    /// Every case is matched rather than defaulted. A `default` returning nil
    /// would silently stop naming a variable the day a case is added, and the
    /// variable is the whole reason an operator can act on the refusal
    /// (ADOPT-2).
    internal var variableName: String? {
        switch self {
        case let .missing(key, _): return key
        case let .notANumber(key, _): return key
        case let .zeroMinimum(key): return key
        case let .zeroSupply(key): return key
        case let .tooManyEntries(key, _): return key
        case let .unusableName(key, _): return key
        case let .unusableURL(key, _): return key
        case let .unusableColor(key, _): return key
        case let .unsupportedDecimals(key, _): return key
        case let .duplicateId(_, _, second): return second
        case let .duplicateName(_, _, second): return second
        case let .duplicateMinimum(_, _, second): return second
        case let .duplicateThreshold(_, _, _, second, _): return second
        case let .duplicateAsset(_, _, second): return second
        }
    }
}

extension ChainConfigurationError {

    // MARK: - Internal Methods

    /// The variable this refusal is about, when it is about one.
    internal var variableName: String? {
        switch self {
        case let .missing(variable): return variable
        case let .invalidValue(variable, _, _): return variable
        case .amountOverflows: return nil
        case .duplicatePoolId: return nil
        }
    }
}
