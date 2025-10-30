import Foundation

/// A wrapper that prevents Fluent Postgres from mapping `[T]` to `jsonb[]`
/// and instead stores the entire payload as a single `jsonb` value.
public struct JSONBlob<T: Codable & Sendable>: Codable, Sendable {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }
}

extension JSONBlob: Equatable where T: Equatable {}
