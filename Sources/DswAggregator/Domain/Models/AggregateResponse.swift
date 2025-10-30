//
//  AggregateResponse.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public struct AggregateResponse: Content, Sendable {
    public var groupId: Int
    public var from: String
    public var to: String
    public var intervalType: Int
    public var groupSchedule: [ScheduleEvent]
    public var teachers: [TeacherCard]
    public var fetchedAt: String

    public init(
        groupId: Int,
        from: String,
        to: String,
        intervalType: Int,
        groupSchedule: [ScheduleEvent],
        teachers: [TeacherCard],
        fetchedAt: String
    ) {
        self.groupId = groupId
        self.from = from
        self.to = to
        self.intervalType = intervalType
        self.groupSchedule = groupSchedule
        self.teachers = teachers
        self.fetchedAt = fetchedAt
    }
}