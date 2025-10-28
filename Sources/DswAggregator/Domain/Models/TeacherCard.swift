//
//  TeacherCard.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct TeacherCard: Content, Sendable {
    var id: Int
    var name: String?
    var title: String?
    var department: String?
    var email: String?
    var phone: String?
    var aboutHTML: String?
    var schedule: [ScheduleEvent]
}