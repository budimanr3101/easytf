import Foundation

indirect enum JSONValue: Codable, Hashable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var text: String { if case .string(let v) = self { return v }; return "" }
    var number: Double { if case .number(let v) = self { return v }; return 0 }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    subscript(_ key: String) -> JSONValue {
        get { object[key] ?? .null }
        set { var v = object; v[key] = newValue; self = .object(v) }
    }
    func at(_ path: [String]) -> JSONValue { path.reduce(self) { $0[$1] } }
    mutating func set(_ value: JSONValue, at path: [String]) {
        guard let first = path.first else { self = value; return }
        var child = self[first]; child.set(value, at: Array(path.dropFirst())); self[first] = child
    }
    mutating func remove(at path: [String]) {
        guard let first = path.first else { return }
        if path.count == 1 { var v = object; v.removeValue(forKey: first); self = .object(v) }
        else { var v = self[first]; v.remove(at: Array(path.dropFirst())); self[first] = v }
    }
    func pretty() -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "{}"
    }
    static func parse(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    static func environment(name: String, project: String, region: String, profile: String, backend: JSONValue) -> JSONValue {
        .object(["backend": backend, "values": .object([
            "aws_region": .string(region), "aws_profile": profile.isEmpty ? .null : .string(profile),
            "tags": .object(["env": .string(name), "project": .string(project)]),
            "instances": .object([:]), "security_groups": .object([:]), "load_balancers": .object([:])
        ])])
    }
}
