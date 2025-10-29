//
//  InMemoryCacheStore.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Foundation

actor InMemoryCacheStore {

    private let tz = TimeZone(identifier: "Europe/Warsaw")!
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private var groupScheduleCache: [GroupScheduleCacheKey: CacheEntry<GroupScheduleResponse>] = [:]
    private var groupSearchCache: [GroupSearchCacheKey: CacheEntry<[GroupInfo]>] = [:]
    private var aggregateCache: [AggregateCacheKey: CacheEntry<AggregateResponse>] = [:]
    private var teacherCache: [TeacherCacheKey: CacheEntry<TeacherCard>] = [:]
    private var dailyScheduleCache: [DailyScheduleCacheKey: CacheEntry<GroupScheduleResponse>] = [:]

    // MARK: - expiry helpers (как было)

    private func next8am(after now: Date) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let today8 = cal.date(from: comps)!
        if now < today8 {
            return today8
        } else {
            return cal.date(byAdding: .day, value: 1, to: today8)!
        }
    }

    private func makeExpiry(
        now: Date,
        ttlSeconds: TimeInterval,
        resetAt8am: Bool
    ) -> Date {
        let ttlExpiry = now.addingTimeInterval(ttlSeconds)
        if resetAt8am {
            let hardReset = next8am(after: now)
            return min(ttlExpiry, hardReset)
        } else {
            return ttlExpiry
        }
    }

    // MARK: - Group Schedule (30 min)

    func getGroupSchedule(for key: GroupScheduleCacheKey) -> GroupScheduleResponse? {
        if let entry = groupScheduleCache[key], !entry.isExpired {
            return entry.value
        }
        groupScheduleCache.removeValue(forKey: key)
        return nil
    }

    func setGroupSchedule(_ value: GroupScheduleResponse,
                          for key: GroupScheduleCacheKey) {
        let now = Date()
        let expires = makeExpiry(
            now: now,
            ttlSeconds: 30 * 60,
            resetAt8am: false
        )
        groupScheduleCache[key] = CacheEntry(value: value, expiresAt: expires)
    }

    // MARK: - Group Search (3 days)

    func getGroupSearch(for key: GroupSearchCacheKey) -> [GroupInfo]? {
        if let entry = groupSearchCache[key], !entry.isExpired {
            return entry.value
        }
        groupSearchCache.removeValue(forKey: key)
        return nil
    }

    func setGroupSearch(_ value: [GroupInfo],
                        for key: GroupSearchCacheKey) {
        let now = Date()
        let expires = makeExpiry(
            now: now,
            ttlSeconds: 3 * 24 * 60 * 60,
            resetAt8am: false
        )
        groupSearchCache[key] = CacheEntry(value: value, expiresAt: expires)
    }

    // MARK: - Aggregate (5h, reset 8am)

    func getAggregate(for key: AggregateCacheKey) -> AggregateResponse? {
        if let entry = aggregateCache[key], !entry.isExpired {
            return entry.value
        }
        aggregateCache.removeValue(forKey: key)
        return nil
    }

    func setAggregate(_ value: AggregateResponse,
                      for key: AggregateCacheKey) {
        let now = Date()
        let expires = makeExpiry(
            now: now,
            ttlSeconds: 5 * 60 * 60,
            resetAt8am: true
        )
        aggregateCache[key] = CacheEntry(value: value, expiresAt: expires)
    }

    // MARK: - Teacher (5h, reset 8am)

    func getTeacher(for key: TeacherCacheKey) -> TeacherCard? {
        if let entry = teacherCache[key], !entry.isExpired {
            return entry.value
        }
        teacherCache.removeValue(forKey: key)
        return nil
    }

    func setTeacher(_ value: TeacherCard,
                    for key: TeacherCacheKey) {
        let now = Date()
        let expires = makeExpiry(
            now: now,
            ttlSeconds: 5 * 60 * 60,
            resetAt8am: true
        )
        teacherCache[key] = CacheEntry(value: value, expiresAt: expires)
    }

    // MARK: - Daily Schedule (60 seconds, для "живого" /schedule)

    func getDailySchedule(for key: DailyScheduleCacheKey) -> GroupScheduleResponse? {
        if let entry = dailyScheduleCache[key], !entry.isExpired {
            return entry.value
        }
        dailyScheduleCache.removeValue(forKey: key)
        return nil
    }

    func setDailySchedule(_ value: GroupScheduleResponse,
                          for key: DailyScheduleCacheKey) {
        let now = Date()
        let expires = makeExpiry(
            now: now,
            ttlSeconds: 60, // 60 seconds TTL
            resetAt8am: false
        )
        dailyScheduleCache[key] = CacheEntry(value: value, expiresAt: expires)
    }

    // MARK: - Stats / memory approx

    /// Очень грубая оценка объёма кэша в байтах.
    /// Идея: сериализуем значения в JSON и суммируем Data.count.
    /// Это не "истинный RSS процесса", но норм для мониторинга тренда.
    func stats() -> CacheStats {
        let encoder = JSONEncoder()

        func sizeOf<T: Encodable>(_ value: T) -> Int {
            // Если вдруг что-то нельзя закодировать в JSON (хотя все Content и Codable),
            // просто считаем как 0, чтобы не падать.
            (try? encoder.encode(value))?.count ?? 0
        }

        var totalBytes = 0

        for entry in groupScheduleCache.values where !entry.isExpired {
            totalBytes += sizeOf(entry.value)
        }
        for entry in groupSearchCache.values where !entry.isExpired {
            totalBytes += sizeOf(entry.value)
        }
        for entry in aggregateCache.values where !entry.isExpired {
            totalBytes += sizeOf(entry.value)
        }
        for entry in teacherCache.values where !entry.isExpired {
            totalBytes += sizeOf(entry.value)
        }
        for entry in dailyScheduleCache.values where !entry.isExpired {
            totalBytes += sizeOf(entry.value)
        }

        return CacheStats(
            groupScheduleCount: groupScheduleCache.values.filter { !$0.isExpired }.count,
            groupSearchCount:   groupSearchCache.values.filter { !$0.isExpired }.count,
            aggregateCount:     aggregateCache.values.filter { !$0.isExpired }.count,
            teacherCount:       teacherCache.values.filter { !$0.isExpired }.count,
            dailyScheduleCount: dailyScheduleCache.values.filter { !$0.isExpired }.count,
            approxTotalBytes:   totalBytes
        )
    }
}
