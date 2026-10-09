import Foundation

/// Any JSON value, with its types kept apart and object keys kept in order.
///
/// Two jobs, both about what `Codable` alone cannot say:
///
/// - **Reading payloads we do not trust the shape of.** Swiggy's delivery status
///   is relayed raw (`GET api/groceries/order/{id}`) and its docs have been wrong
///   about it before, so `InstamartOrders.readOrderStatus` reads it field by
///   field. That needs `true` and `1` and `"true"` to stay three different
///   things — the webapp's `=== true` — which `as? Bool` on a
///   `JSONSerialization` result does not guarantee (an `NSNumber` 1 bridges to
///   `true`).
/// - **Writing bodies whose key order matters.** `JSONEncoder` does not keep
///   keyed-container insertion order (measured: it scrambles the eight shopping
///   categories), so the cart request is built as a `JSONValue` and serialized by
///   `jsonData`, which writes objects in the order given.
public enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    /// Ordered. Decoded objects come back in the decoder's order, which is not
    /// the document's; only values built in code have a meaningful order.
    case object([(String, JSONValue)])

    /// The value under `key` when this is an object, else nil. An explicit JSON
    /// `null` is `.null`, not nil — presence and absence stay distinguishable.
    public subscript(key: String) -> JSONValue? {
        guard case let .object(members) = self else { return nil }
        return members.first { $0.0 == key }?.1
    }

    /// The string when this is a JSON string, else nil.
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    /// The compact JSON text for this value, objects in their given order.
    public var jsonData: Data {
        var out = ""
        write(into: &out)
        return Data(out.utf8)
    }

    private func write(into out: inout String) {
        switch self {
        case .null:
            out += "null"
        case let .bool(value):
            out += value ? "true" : "false"
        case let .number(value):
            out += Self.numberText(value)
        case let .string(value):
            Self.writeString(value, into: &out)
        case let .array(values):
            out += "["
            for (index, value) in values.enumerated() {
                if index > 0 { out += "," }
                value.write(into: &out)
            }
            out += "]"
        case let .object(members):
            out += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { out += "," }
                Self.writeString(member.0, into: &out)
                out += ":"
                member.1.write(into: &out)
            }
            out += "}"
        }
    }

    /// JavaScript's number-to-string for the values we send: whole numbers
    /// without a ".0" (what `JSON.stringify` and `JSONEncoder` both write) and
    /// the shortest round-tripping form otherwise. JSON has no NaN/Infinity;
    /// `JSON.stringify` writes them as null, and so does this.
    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(.towardZero), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return "\(value)"
    }

    /// RFC 8259 escaping: quote, backslash and control characters. Everything
    /// else, `/` and non-ASCII included, is written as-is in UTF-8.
    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{C}": out += "\\f"
            case let control where control.value < 0x20:
                out += String(format: "\\u%04x", control.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }
}

extension JSONValue: Decodable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            // Bool first: JSONDecoder refuses a number as a Bool, so a `1` falls
            // through to `.number` rather than reading as a flag.
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([JSONValue].self) {
            self = .array(value)
        } else {
            let object = try decoder.container(keyedBy: AnyKey.self)
            self = .object(try object.allKeys.map { key in
                (key.stringValue, try object.decode(JSONValue.self, forKey: key))
            })
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
