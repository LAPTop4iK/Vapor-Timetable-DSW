//
//  ScheduleEvent.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct ScheduleEvent: Content, Sendable {
    let title: String

    let teacherName: String?
    let teacherId: Int?
    let teacherEmail: String?

    let room: String?
    let type: String?
    let grading: String?
    let studyTrack: String?
    let groups: String?
    let remarks: String?

    let startISO: String
    let endISO: String
}