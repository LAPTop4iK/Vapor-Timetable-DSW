//
//  ScheduleEvent.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public struct ScheduleEvent: Content, Sendable {
    public let title: String

    public let teacherName: String?
    public let teacherId: Int?
    public let teacherEmail: String?

    public let room: String?
    public let type: String?
    public let grading: String?
    public let studyTrack: String?
    public let groups: String?
    public let remarks: String?

    public let startISO: String
    public let endISO: String

    public init(
        title: String,
        teacherName: String? = nil,
        teacherId: Int? = nil,
        teacherEmail: String? = nil,
        room: String? = nil,
        type: String? = nil,
        grading: String? = nil,
        studyTrack: String? = nil,
        groups: String? = nil,
        remarks: String? = nil,
        startISO: String,
        endISO: String
    ) {
        self.title = title
        self.teacherName = teacherName
        self.teacherId = teacherId
        self.teacherEmail = teacherEmail
        self.room = room
        self.type = type
        self.grading = grading
        self.studyTrack = studyTrack
        self.groups = groups
        self.remarks = remarks
        self.startISO = startISO
        self.endISO = endISO
    }
}