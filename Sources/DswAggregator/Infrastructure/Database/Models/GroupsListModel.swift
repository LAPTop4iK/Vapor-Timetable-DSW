//
//  GroupsListModel.swift
//  DswAggregator
//
//  Fluent model for groups list metadata
//

import Fluent
import Vapor

final class GroupsListModel: Model, @unchecked Sendable {
    static let schema = "groups_list"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "groups")
    var groups: [GroupInfo]

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(groups: [GroupInfo]) {
        self.groups = groups
    }
}
