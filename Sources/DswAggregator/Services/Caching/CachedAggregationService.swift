//
//  CachedAggregationService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct CachedAggregationService: Sendable {
    let base: AggregationService
    let cache: InMemoryCacheStore

    func aggregate(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> AggregateResponse {

        let key = AggregateCacheKey(
            groupId: groupId,
            from: from,
            to: to,
            intervalRaw: intervalType.rawValue
        )

        if let cached = await cache.getAggregate(for: key) {
            return cached
        }

        let fresh = try await base.aggregate(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType
        )
        await cache.setAggregate(fresh, for: key)
        return fresh
    }
}
