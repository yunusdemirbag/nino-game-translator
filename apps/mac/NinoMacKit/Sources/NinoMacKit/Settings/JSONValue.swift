// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Herhangi bir JSON değeri. Ayar dosyasındaki tanınmayan alanları kaybetmeden
/// taşımak ve alanları tek tek, hoşgörüyle okumak için.
public enum JSONValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            // Tam sayılar tam sayı olarak yazılsın ("30", "30.0" değil).
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var double: Double? { if case .number(let n) = self { return n }; return nil }
    public var int: Int? {
        guard case .number(let n) = self, n.isFinite else { return nil }
        return Int(n.rounded())
    }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

/// Bir JSON nesnesinden alan alan okuma. Her okuma kullanılan alanı işaretler;
/// geri kalanlar "tanınmayan alanlar" olarak saklanır.
struct FieldReader {
    private let fields: [String: JSONValue]
    private(set) var used: Set<String> = []

    init(_ fields: [String: JSONValue]) { self.fields = fields }

    mutating func raw(_ key: String) -> JSONValue? {
        used.insert(key)
        return fields[key]
    }

    mutating func string(_ key: String) -> String? { raw(key)?.string }
    mutating func bool(_ key: String) -> Bool? { raw(key)?.bool }
    mutating func int(_ key: String) -> Int? { raw(key)?.int }
    mutating func double(_ key: String) -> Double? { raw(key)?.double }
    mutating func object(_ key: String) -> [String: JSONValue]? { raw(key)?.object }
    mutating func array(_ key: String) -> [JSONValue]? { raw(key)?.array }
    mutating func choice<T: RawRepresentable>(_ key: String, as: T.Type = T.self) -> T? where T.RawValue == String {
        string(key).flatMap(T.init(rawValue:))
    }

    var leftovers: [String: JSONValue] { fields.filter { !used.contains($0.key) } }
}
