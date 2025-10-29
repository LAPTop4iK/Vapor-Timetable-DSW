//
//  TeacherDocument.swift
//  DswAggregator
//
//  Firestore document structure for /teachers/{teacherId}
//

import Vapor

/// Firestore document for a teacher
/// Stored in /teachers/{teacherId}
struct TeacherDocument: Content, Sendable {
    var id: Int
    var name: String?
    var title: String?
    var department: String?
    var email: String?
    var phone: String?
    var aboutHTML: String?
    var schedule: [ScheduleEvent]
    var fetchedAt: String

    /// Convert to TeacherCard for API response
    func toTeacherCard() -> TeacherCard {
        return TeacherCard(
            id: id,
            name: name,
            title: title,
            department: department,
            email: email,
            phone: phone,
            aboutHTML: aboutHTML,
            schedule: schedule
        )
    }

    /// Create from TeacherCard
    init(from card: TeacherCard, fetchedAt: String) {
        self.id = card.id
        self.name = card.name
        self.title = card.title
        self.department = card.department
        self.email = card.email
        self.phone = card.phone
        self.aboutHTML = card.aboutHTML
        self.schedule = card.schedule
        self.fetchedAt = fetchedAt
    }
}
