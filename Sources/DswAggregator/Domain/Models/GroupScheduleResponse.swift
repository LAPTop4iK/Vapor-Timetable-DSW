//
//  GroupScheduleResponse.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct GroupScheduleResponse: Content, Sendable {
    var groupId: Int
    var from: String
    var to: String
    var intervalType: Int
    var groupSchedule: [ScheduleEvent]
    var fetchedAt: String
}