//
//  CreateGroupsList.swift
//  DswAggregator
//
//  Migration to create groups_list table
//

import Fluent

struct CreateGroupsList: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("groups_list")
            .id()
            .field("groups", .json, .required)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("groups_list").delete()
    }
}
