//
//  CacheKey.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Foundation

/// /api/groups/:groupId/schedule
struct GroupScheduleCacheKey: Hashable, Sendable {
    let groupId: Int
    let from: String
    let to: String
    let intervalRaw: Int
}

/// /api/groups/search?q=...
struct GroupSearchCacheKey: Hashable, Sendable {
    let query: String
}

/// /api/groups/:groupId/aggregate
struct AggregateCacheKey: Hashable, Sendable {
    let groupId: Int
    let from: String
    let to: String
    let intervalRaw: Int
}

/// Отдельный кэш по преподавателю:
/// фактически "карточка преподавателя + его расписание" за интервал
struct TeacherCacheKey: Hashable, Sendable {
    let teacherId: Int
    let from: String
    let to: String
    let intervalRaw: Int
}
