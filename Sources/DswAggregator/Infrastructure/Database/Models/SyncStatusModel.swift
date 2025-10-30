//
//  SyncStatusModel.swift
//  DswAggregator
//
//  Fluent model for sync status tracking
//

import Fluent
import Vapor

public final class SyncStatusModel: Model, @unchecked Sendable {
    static let schema = "sync_status"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "status")
    var status: String  // "ok" | "error" | "in_progress"

    @Field(key: "total_groups")
    var totalGroups: Int

    @Field(key: "processed_groups")
    var processedGroups: Int

    @Field(key: "failed_groups")
    var failedGroups: Int

    @OptionalField(key: "error_message")
    var errorMessage: String?

    @Field(key: "duration")
    var duration: Double

    @Field(key: "started_at")
    var startedAt: Date

    init() {}

    init(
        timestamp: Date,
        status: String,
        totalGroups: Int,
        processedGroups: Int,
        failedGroups: Int,
        errorMessage: String? = nil,
        duration: Double,
        startedAt: Date
    ) {
        self.timestamp = timestamp
        self.status = status
        self.totalGroups = totalGroups
        self.processedGroups = processedGroups
        self.failedGroups = failedGroups
        self.errorMessage = errorMessage
        self.duration = duration
        self.startedAt = startedAt
    }
}
