//
//  GroupScheduleService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct GroupScheduleService: Sendable {
    let client: any DSWClient
    let parser: any ScheduleParser

    func fetchSchedule(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> GroupScheduleResponse {

        let gHTML = try await client.groupScheduleHTML(
            groupId: groupId,
            from: from,
            to: to,
            interval: intervalType
        )
        let groupEvents = try parser.parseSchedule(gHTML)

        return GroupScheduleResponse(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType.rawValue,
            groupSchedule: groupEvents,
            fetchedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
