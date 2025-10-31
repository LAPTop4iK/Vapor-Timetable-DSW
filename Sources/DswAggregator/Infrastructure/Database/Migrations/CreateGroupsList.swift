//
//  CreateGroupsList.swift
//  DswAggregator
//
//  Migration to create groups_list table
//

import Fluent

public struct CreateGroupsList: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema("groups_list")
            .id()
            .field("groups", .custom("TEXT"), .required)
            .field("updated_at", .datetime)
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema("groups_list").delete()
    }
}

