import Foundation

/// Turning ledger values into text and back.
///
/// Offered because most hosts will keep these rows in a text column somewhere,
/// and because the decoding rule below is not the obvious one and getting it
/// wrong is expensive.
public enum ReserveCoding: Sendable {

    // MARK: - Private Methods

    /// Dates travel as epoch seconds: compact, and free of the date-formatter
    /// differences between platforms that make a round trip stop round-tripping.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: - Public Methods

    /// A value as JSON text.
    public static func encode<Value: Encodable>(_ value: Value) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// JSON text back into a value, **throwing** rather than reading as empty.
    ///
    /// This is the rule worth stating out loud. Treating an unreadable row as
    /// "nothing recorded" is right for a description of work and catastrophic
    /// here: a ledger row that failed to parse would look like an epoch nobody
    /// has been paid for, and the next run would pay all of it again. Refusing
    /// to run is strictly better than paying twice.
    public static func decode<Value: Decodable>(_ type: Value.Type, from raw: String) throws -> Value {
        try decoder.decode(Value.self, from: Data(raw.utf8))
    }
}
