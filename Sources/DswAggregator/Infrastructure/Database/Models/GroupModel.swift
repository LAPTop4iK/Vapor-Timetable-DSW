//
//  GroupModel.swift
//  DswAggregator
//
//  Fluent model for cached group data
//

import Fluent
import Vapor

final class GroupModel: Model, @unchecked Sendable {
    static let schema = "groups"

    @ID(custom: "group_id", generatedBy: .user)
    var id: Int?

    @Field(key: "from_date")
    var fromDate: String

    @Field(key: "to_date")
    var toDate: String

    @Field(key: "interval_type")
    var intervalType: Int

    @Field(key: "group_schedule")
    var groupScheduleJSON: String = "[]"

    /// Computed property for accessing groupSchedule as [ScheduleEvent]
    var groupSchedule: [ScheduleEvent] {
        get {
            guard let data = groupScheduleJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ScheduleEvent].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8) {
                groupScheduleJSON = jsonString
            } else {
                groupScheduleJSON = "[]"
            }
        }
    }

    @Field(key: "teacher_ids")
    var teacherIds: [Int]

    @Field(key: "group_info")
    var groupInfo: GroupInfo

    @Timestamp(key: "fetched_at", on: .update)
    var fetchedAt: Date?

    init() {}

    init(
        id: Int,
        fromDate: String,
        toDate: String,
        intervalType: Int,
        groupSchedule: [ScheduleEvent],
        teacherIds: [Int],
        groupInfo: GroupInfo
    ) {
        self.id = id
        self.fromDate = fromDate
        self.toDate = toDate
        self.intervalType = intervalType
        self.teacherIds = teacherIds
        self.groupInfo = groupInfo
        // Use the computed property setter to encode groupSchedule
        self.groupSchedule = groupSchedule
    }
}
