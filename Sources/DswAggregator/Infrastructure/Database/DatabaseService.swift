//
//  DatabaseService.swift
//  DswAggregator
//
//  Service for reading/writing cached data to PostgreSQL
//

import Fluent
import Vapor

public struct DatabaseService: Sendable {
    let db: Database

    public init(db: Database) {
        self.db = db
    }

    // MARK: - Read Operations

    /// Get group aggregate data
    public func getGroupAggregate(groupId: Int) async throws -> AggregateResponse? {
        guard let groupModel = try await GroupModel.find(groupId, on: db) else {
            return nil
        }

        // Fetch all teachers
        let teacherModels = try await TeacherModel.query(on: db).all()
        let teachers = teacherModels.map { $0.toTeacherCard() }

        let isoFormatter = ISO8601DateFormatter()
        let fetchedAt = groupModel.fetchedAt.map { isoFormatter.string(from: $0) } ?? ""

        return AggregateResponse(
            groupId: groupId,
            from: groupModel.fromDate,
            to: groupModel.toDate,
            intervalType: groupModel.intervalType,
            groupSchedule: groupModel.groupSchedule,
            teachers: teachers,
            fetchedAt: fetchedAt
        )
    }

    /// Get groups list for search
    public func getGroupsList() async throws -> [GroupInfo] {
        guard let listModel = try await GroupsListModel.query(on: db)
            .sort(\.$updatedAt, .descending)
            .first() else {
            return []
        }
        return listModel.groups
    }

    /// Get latest sync status
    public func getLatestSyncStatus() async throws -> SyncStatusModel? {
        try await SyncStatusModel.query(on: db)
            .sort(\.$timestamp, .descending)
            .first()
    }

    // MARK: - Write Operations

    /// Save or update group data
    public func saveGroup(
        groupId: Int,
        fromDate: String,
        toDate: String,
        intervalType: Int,
        groupSchedule: [ScheduleEvent],
        teacherIds: [Int],
        groupInfo: GroupInfo
    ) async throws {
        let group = GroupModel(
            id: groupId,
            fromDate: fromDate,
            toDate: toDate,
            intervalType: intervalType,
            groupSchedule: groupSchedule,
            teacherIds: teacherIds,
            groupInfo: groupInfo
        )
        try await group.save(on: db)
    }

    /// Save or update teacher data
    public func saveTeacher(card: TeacherCard) async throws {
        let teacher = TeacherModel(
            id: card.id,
            name: card.name,
            title: card.title,
            department: card.department,
            email: card.email,
            phone: card.phone,
            aboutHTML: card.aboutHTML,
            schedule: card.schedule
        )
        try await teacher.save(on: db)
    }

    /// Save groups list
    public func saveGroupsList(groups: [GroupInfo]) async throws {
        // Delete old entries
        try await GroupsListModel.query(on: db).delete()

        // Insert new
        let listModel = GroupsListModel(groups: groups)
        try await listModel.save(on: db)
    }

    /// Save sync status
    public func saveSyncStatus(
        timestamp: Date,
        status: String,
        totalGroups: Int,
        processedGroups: Int,
        failedGroups: Int,
        errorMessage: String? = nil,
        duration: Double,
        startedAt: Date
    ) async throws {
        let statusModel = SyncStatusModel(
            timestamp: timestamp,
            status: status,
            totalGroups: totalGroups,
            processedGroups: processedGroups,
            failedGroups: failedGroups,
            errorMessage: errorMessage,
            duration: duration,
            startedAt: startedAt
        )
        try await statusModel.save(on: db)
    }

    /// Batch save teachers
    public func saveTeachers(_ cards: [TeacherCard]) async throws {
        for card in cards {
            try await saveTeacher(card: card)
        }
    }
}
