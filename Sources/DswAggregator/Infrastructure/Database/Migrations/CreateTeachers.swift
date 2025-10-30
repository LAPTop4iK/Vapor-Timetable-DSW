//
//  CreateTeachers.swift
//  DswAggregator
//
//  Migration to create teachers table
//

import Fluent

struct CreateTeachers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("teachers")
            .field("id", .int, .identifier(auto: false))
            .field("name", .string)
            .field("title", .string)
            .field("department", .string)
            .field("email", .string)
            .field("phone", .string)
            .field("about_html", .string)
            .field("schedule", .json, .required)
            .field("fetched_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("teachers").delete()
    }
}
