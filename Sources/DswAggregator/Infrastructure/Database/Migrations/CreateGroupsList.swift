//
//  CreateGroupsList.swift
//  DswAggregator
//
//  Migration to create groups_list table
//

import Fluent

public struct CreateGroupsList: AsyncMigration {
    public init() {}

    public func prepare(on database: Database) async throws {
        try await database.schema("groups_list")
            .id()
            .field("groups", .json, .required)
            .field("updated_at", .datetime)
            .create()
    }

    public func revert(on database: Database) async throws {
        try await database.schema("groups_list").delete()
    }
}

