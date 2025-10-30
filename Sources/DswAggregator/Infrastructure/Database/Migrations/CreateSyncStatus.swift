//
//  CreateSyncStatus.swift
//  DswAggregator
//
//  Migration to create sync_status table
//

import Fluent

public struct CreateSyncStatus: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("sync_status")
            .id()
            .field("timestamp", .datetime, .required)
            .field("status", .string, .required)
            .field("total_groups", .int, .required)
            .field("processed_groups", .int, .required)
            .field("failed_groups", .int, .required)
            .field("error_message", .string)
            .field("duration", .double, .required)
            .field("started_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("sync_status").delete()
    }
}
