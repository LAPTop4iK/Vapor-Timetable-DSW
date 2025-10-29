//
//  FirestoreWriter.swift
//  DswAggregator
//
//  High-level service for writing data to Firestore
//  Used by SyncRunner
//

import Vapor

/// Service for writing preloaded data to Firestore
actor FirestoreWriter {
    private let client: FirestoreClient
    private let logger: Logger

    init(client: FirestoreClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    /// Save a group document
    func saveGroup(
        groupId: Int,
        groupInfo: GroupInfo,
        schedule: [ScheduleEvent],
        teacherIds: [Int],
        from: String,
        to: String,
        intervalType: IntervalType,
        fetchedAt: String
    ) async throws {
        let doc = GroupDocument(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType.rawValue,
            groupSchedule: schedule,
            teacherIds: teacherIds,
            fetchedAt: fetchedAt,
            groupInfo: GroupInfoNested(from: groupInfo)
        )

        try await client.setDocument(
            collection: "groups",
            documentId: String(groupId),
            data: doc
        )

        logger.info("Saved group \(groupId) to Firestore")
    }

    /// Save a teacher document
    func saveTeacher(_ card: TeacherCard, fetchedAt: String) async throws {
        let doc = TeacherDocument(from: card, fetchedAt: fetchedAt)

        try await client.setDocument(
            collection: "teachers",
            documentId: String(card.id),
            data: doc
        )

        logger.debug("Saved teacher \(card.id) to Firestore")
    }

    /// Save the groups list
    func saveGroupsList(_ groups: [GroupInfo]) async throws {
        let isoNow = ISO8601DateFormatter().string(from: Date())
        let doc = GroupsListDocument(groups: groups, updatedAt: isoNow)

        try await client.setDocument(
            collection: "metadata",
            documentId: "groupsList",
            data: doc
        )

        logger.info("Saved groups list (\(groups.count) groups) to Firestore")
    }

    /// Update sync status
    func updateSyncStatus(_ status: SyncStatusDocument) async throws {
        try await client.setDocument(
            collection: "metadata",
            documentId: "lastSync",
            data: status
        )

        logger.info("Updated sync status: \(status.status)")
    }

    /// Batch save multiple teachers (more efficient)
    func batchSaveTeachers(_ cards: [TeacherCard], fetchedAt: String) async throws {
        let writes = cards.map { card in
            BatchWrite(
                collection: "teachers",
                documentId: String(card.id),
                data: TeacherDocument(from: card, fetchedAt: fetchedAt)
            )
        }

        try await client.batchWrite(writes: writes)
        logger.info("Batch saved \(cards.count) teachers to Firestore")
    }
}
