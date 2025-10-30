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
    var scheduleJSON: String = "[]"

    /// Computed property for accessing schedule as [ScheduleEvent]
    var schedule: [ScheduleEvent] {
        get {
            guard let data = scheduleJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ScheduleEvent].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8) {
                scheduleJSON = jsonString
            } else {
                scheduleJSON = "[]"
            }
        }
    }

    @Timestamp(key: "fetched_at", on: .update)
    var fetchedAt: Date?

    init() {}

    init(
        id: Int,
        name: String?,
        title: String?,
        department: String?,
        email: String?,
        phone: String?,
        aboutHTML: String?,
        schedule: [ScheduleEvent]
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.department = department
        self.email = email
        self.phone = phone
        self.aboutHTML = aboutHTML
        // Use the computed property setter to encode schedule
        self.schedule = schedule
    }

    func toTeacherCard() -> TeacherCard {
        TeacherCard(
            id: self.id ?? 0,
            name: self.name,
            title: self.title,
            department: self.department,
            email: self.email,
            phone: self.phone,
            aboutHTML: self.aboutHTML,
            schedule: self.schedule
        )
    }
}
