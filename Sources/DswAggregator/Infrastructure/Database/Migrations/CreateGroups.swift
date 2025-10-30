//
//  CreateGroups.swift
//  DswAggregator
//
//  Migration to create groups table
//

import Fluent

public struct CreateGroups: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema("groups")
            .field("group_id", .int, .identifier(auto: false))
            .field("from_date", .string, .required)
            .field("to_date", .string, .required)
            .field("interval_type", .int, .required)
            .field("group_schedule", .custom("TEXT"), .required)
            .field("teacher_ids", .array(of: .int), .required)
            .field("group_info", .json, .required)
            .field("fetched_at", .datetime)
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema("groups").delete()
    }
}

