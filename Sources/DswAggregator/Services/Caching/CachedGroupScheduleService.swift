//
//  CachedGroupScheduleService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct CachedGroupScheduleService: Sendable {
    let base: GroupScheduleService
    let cache: InMemoryCacheStore

    func fetchSchedule(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> GroupScheduleResponse {

        let key = GroupScheduleCacheKey(
            groupId: groupId,
            from: from,
            to: to,
            intervalRaw: intervalType.rawValue
        )

        if let cached = await cache.getGroupSchedule(for: key) {
            return cached
        }

        let fresh = try await base.fetchSchedule(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType
        )
        await cache.setGroupSchedule(fresh, for: key)
        return fresh
    }
}
