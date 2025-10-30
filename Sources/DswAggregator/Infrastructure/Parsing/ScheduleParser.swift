//
//  ScheduleParser.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public protocol ScheduleParser: Sendable {
    func parseSchedule(_ html: String) throws -> [ScheduleEvent]
    func parseTeacherInfo(_ html: String, teacherId: Int) throws
      -> (name: String?, title: String?, dept: String?,
          email: String?, phone: String?, aboutHTML: String?)
}