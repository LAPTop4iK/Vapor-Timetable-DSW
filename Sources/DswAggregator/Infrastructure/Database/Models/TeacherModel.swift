//
//  TeacherModel.swift
//  DswAggregator
//
//  Fluent model for cached teacher data
//

import Fluent
import Vapor

final class TeacherModel: Model, @unchecked Sendable {
    static let schema = "teachers"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "name")
    var name: String?

    @Field(key: "title")
    var title: String?

    @Field(key: "department")
    var department: String?

    @Field(key: "email")
    var email: String?

    @Field(key: "phone")
    var phone: String?

    @Field(key: "about_html")
    var aboutHTML: String?

    @Field(key: "schedule")
    var scheduleJSON: String

    @Timestamp(key: "fetched_at", on: .update)
    var fetchedAt: Date?

    init() {
        self.scheduleJSON = "[]"
    }

    init(
        id: Int,
        name: String?,
        title: String?,
        department: String?,
        email: String?,
        phone: String?,
        aboutHTML: String?,
        scheduleJSON: String
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.department = department
        self.email = email
        self.phone = phone
        self.aboutHTML = aboutHTML
        self.scheduleJSON = scheduleJSON
    }

    func toTeacherCard() -> TeacherCard {
        // Decode schedule from JSON string
        let schedule: [ScheduleEvent]
        if let data = scheduleJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ScheduleEvent].self, from: data) {
            schedule = decoded
        } else {
            schedule = []
        }

        return TeacherCard(
            id: self.id ?? 0,
            name: self.name,
            title: self.title,
            department: self.department,
            email: self.email,
            phone: self.phone,
            aboutHTML: self.aboutHTML,
            schedule: schedule
        )
    }
}
