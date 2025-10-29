//
//  GroupDocument.swift
//  DswAggregator
//
//  Firestore document structure for /groups/{groupId}
//

import Vapor

/// Firestore document for a group
/// Stored in /groups/{groupId}
struct GroupDocument: Content, Sendable {
    var groupId: Int
    var from: String
    var to: String
    var intervalType: Int
    var groupSchedule: [ScheduleEvent]
    var teacherIds: [Int]  // Array of teacher IDs, not full TeacherCard objects
    var fetchedAt: String
    var groupInfo: GroupInfoNested
}

/// Nested group info inside GroupDocument
struct GroupInfoNested: Content, Sendable {
    let code: String
    let name: String
    let tracks: [TrackInfo]
    let program: String
    let faculty: String

    init(from groupInfo: GroupInfo) {
        self.code = groupInfo.code
        self.name = groupInfo.name
        self.tracks = groupInfo.tracks
        self.program = groupInfo.program
        self.faculty = groupInfo.faculty
    }
}
