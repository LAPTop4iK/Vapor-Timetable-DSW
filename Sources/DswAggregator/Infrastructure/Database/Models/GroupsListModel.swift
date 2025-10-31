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
    var groupsJSON: String

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {
        self.groupsJSON = "[]"
    }

    init(groups: [GroupInfo]) {
        // Encode groups to JSON string
        if let data = try? JSONEncoder().encode(groups),
           let jsonString = String(data: data, encoding: .utf8) {
            self.groupsJSON = jsonString
        } else {
            self.groupsJSON = "[]"
        }
    }

    /// Decode groups from JSON string
    func getGroups() -> [GroupInfo] {
        guard let data = groupsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([GroupInfo].self, from: data) else {
            return []
        }
        return decoded
    }
}
