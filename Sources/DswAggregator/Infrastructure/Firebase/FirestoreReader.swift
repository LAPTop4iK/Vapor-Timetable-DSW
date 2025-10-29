//
//  FirestoreReader.swift
//  DswAggregator
//
//  High-level service for reading data from Firestore
//  Used by Vapor API endpoints
//

import Vapor

/// Service for reading preloaded data from Firestore
actor FirestoreReader {
    private let client: FirestoreClient
    private let logger: Logger

    init(client: FirestoreClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    /// Get aggregate data for a group
    /// Returns group schedule + ALL teachers (not just from this group)
    func getGroupAggregate(groupId: Int) async throws -> AggregateResponse? {
        // 1. Get group document
        guard let groupDoc: GroupDocument = try await client.getDocument(
            collection: "groups",
            documentId: String(groupId)
        ) else {
            logger.warning("Group \(groupId) not found in Firestore")
            return nil
        }

        // 2. Get all teachers referenced by this group
        var teachers: [TeacherCard] = []
        for teacherId in groupDoc.teacherIds {
            if let teacherDoc: TeacherDocument = try await client.getDocument(
                collection: "teachers",
                documentId: String(teacherId)
            ) {
                teachers.append(teacherDoc.toTeacherCard())
            } else {
                logger.warning("Teacher \(teacherId) referenced but not found in Firestore")
            }
        }

        // 3. Build response
        return AggregateResponse(
            groupId: groupDoc.groupId,
            from: groupDoc.from,
            to: groupDoc.to,
            intervalType: groupDoc.intervalType,
            groupSchedule: groupDoc.groupSchedule,
            teachers: teachers,
            fetchedAt: groupDoc.fetchedAt
        )
    }

    /// Get list of all groups for search
    func getGroupsList() async throws -> [GroupInfo]? {
        guard let doc: GroupsListDocument = try await client.getDocument(
            collection: "metadata",
            documentId: "groupsList"
        ) else {
            logger.warning("Groups list not found in Firestore")
            return nil
        }

        return doc.groups
    }

    /// Get sync status
    func getSyncStatus() async throws -> SyncStatusDocument? {
        return try await client.getDocument(
            collection: "metadata",
            documentId: "lastSync"
        )
    }

    /// Get a single teacher
    func getTeacher(teacherId: Int) async throws -> TeacherCard? {
        guard let doc: TeacherDocument = try await client.getDocument(
            collection: "teachers",
            documentId: String(teacherId)
        ) else {
            return nil
        }
        return doc.toTeacherCard()
    }
}
