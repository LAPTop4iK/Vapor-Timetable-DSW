//
//  AggregateResponse.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct AggregateResponse: Content, Sendable {
    var groupId: Int
    var from: String
    var to: String
    var intervalType: Int
    var groupSchedule: [ScheduleEvent]
    var teachers: [TeacherCard]
    var fetchedAt: String
}