import Foundation

/// The few MessagePack headers this suite writes by hand.
///
/// Only for shapes a canonical encoder cannot produce: a duplicate key, keys
/// out of order, a length the bytes do not carry. Every fixture that has to
/// be well formed comes from the dependency's own encoder instead, and every
/// one of these is named for **the shape** rather than for a wallet, because
/// a recorded wallet blob carries a real account and cannot go into a public
/// repository.
enum MessagePackBytes {

    /// A short string, as a fixstr.
    static func string(_ value: String) -> Data {
        var bytes = Data([0xA0 + UInt8(value.utf8.count)])
        bytes.append(contentsOf: value.utf8)
        return bytes
    }

    /// A short run of bytes, as a bin8.
    static func binary(_ value: Data) -> Data {
        var bytes = Data([0xC4, UInt8(value.count)])
        bytes.append(value)
        return bytes
    }

    /// A map header for up to fifteen pairs.
    static func map(_ count: Int) -> Data {
        Data([0x80 + UInt8(count)])
    }

    /// An array header for up to fifteen elements.
    static func array(_ count: Int) -> Data {
        Data([0x90 + UInt8(count)])
    }

    /// A small unsigned integer, as a positive fixint.
    static func uint(_ value: UInt8) -> Data {
        Data([value])
    }

    /// An unsigned integer that does not fit a fixint.
    static func uint16(_ value: UInt16) -> Data {
        Data([0xCD, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Nil.
    static let null: Data = Data([0xC0])

    /// A map of string keys to already-encoded values, in the order given.
    ///
    /// The order is the caller's on purpose: the shape a real wallet was
    /// once refused for puts its keys in an order no canonical encoder
    /// would, and a helper that quietly sorted them would make that case
    /// untestable.
    static func envelope(_ pairs: [(String, Data)]) -> Data {
        var bytes = map(pairs.count)
        for pair in pairs {
            bytes.append(string(pair.0))
            bytes.append(pair.1)
        }
        return bytes
    }
}
