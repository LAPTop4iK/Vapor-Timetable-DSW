//
//  GroupsListDocument.swift
//  DswAggregator
//
//  Firestore document structure for /metadata/groupsList
//

import Vapor

/// Firestore document containing list of all groups
/// Stored in /metadata/groupsList
struct GroupsListDocument: Content, Sendable {
    var groups: [GroupInfo]
    var updatedAt: String
}
