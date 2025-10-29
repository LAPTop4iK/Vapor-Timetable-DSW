//
//  SyncStatusDocument.swift
//  DswAggregator
//
//  Firestore document structure for /metadata/lastSync
//

import Vapor

/// Firestore document for sync status
/// Stored in /metadata/lastSync
struct SyncStatusDocument: Content, Sendable {
    var timestamp: String  // ISO8601
    var status: String     // "ok" | "error" | "in_progress"
    var totalGroups: Int
    var processedGroups: Int
    var failedGroups: Int
    var errorMessage: String?
    var duration: Double   // seconds
    var startedAt: String? // ISO8601
}
