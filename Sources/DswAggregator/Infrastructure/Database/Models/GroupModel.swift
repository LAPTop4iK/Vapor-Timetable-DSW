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
    var groupScheduleJSON: String

    @Field(key: "teacher_ids")
    var teacherIds: [Int]

    @Field(key: "group_info")
    var groupInfo: GroupInfo

    @Timestamp(key: "fetched_at", on: .update)
    var fetchedAt: Date?

    init() {
        self.groupScheduleJSON = "[]"
    }

    init(
        id: Int,
        fromDate: String,
        toDate: String,
        intervalType: Int,
        groupScheduleJSON: String,
        teacherIds: [Int],
        groupInfo: GroupInfo
    ) {
        self.id = id
        self.fromDate = fromDate
        self.toDate = toDate
        self.intervalType = intervalType
        self.groupScheduleJSON = groupScheduleJSON
        self.teacherIds = teacherIds
        self.groupInfo = groupInfo
    }
}
