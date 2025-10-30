//
//  TeacherCard.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public struct TeacherCard: Content, Sendable {
    public var id: Int
    public var name: String?
    public var title: String?
    public var department: String?
    public var email: String?
    public var phone: String?
    public var aboutHTML: String?
    public var schedule: [ScheduleEvent]

    public init(
        id: Int,
        name: String? = nil,
        title: String? = nil,
        department: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        aboutHTML: String? = nil,
        schedule: [ScheduleEvent] = []
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.department = department
        self.email = email
        self.phone = phone
        self.aboutHTML = aboutHTML
        self.schedule = schedule
    }
}