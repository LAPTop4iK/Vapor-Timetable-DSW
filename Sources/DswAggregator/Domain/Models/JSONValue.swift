//
//  JSONValue.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Foundation

enum JSONValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from d: any Decoder) throws {
        let c = try d.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: c.codingPath,
                  debugDescription: "Unsupported JSON")
        )
    }

    func encode(to e: any Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}