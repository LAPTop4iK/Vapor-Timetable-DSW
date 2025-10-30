//
//  CreateTeachers.swift
//  DswAggregator
//
//  Migration to create teachers table
//

import Fluent

public struct CreateTeachers: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema("teachers")
            .field("id", .int, .identifier(auto: false))
            .field("name", .custom("TEXT"))
            .field("title", .custom("TEXT"))
            .field("department", .custom("TEXT"))
            .field("email", .string)
            .field("phone", .string)
            .field("about_html", .custom("TEXT"))
            .field("schedule", .custom("TEXT"))
            .field("fetched_at", .datetime)
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema("teachers").delete()
    }
}

