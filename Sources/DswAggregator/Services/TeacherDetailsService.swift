//
//  TeacherDetailsService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

/// Базовый сервис получения карточки преподавателя (инфа + расписание)
public struct TeacherDetailsService: Sendable {
    let client: any DSWClient
    let parser: any ScheduleParser

    public init(client: any DSWClient, parser: any ScheduleParser) {
        self.client = client
        self.parser = parser
    }

    func fetchTeacherCard(
        teacherId: Int?,
        fallbackName: String?,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> TeacherCard {

        // Если у пары нет teacherId (бывает) — возвращаем "заглушку"
        guard let tid = teacherId else {
            return TeacherCard(
                id: 0,
                name: fallbackName,
                title: nil,
                department: nil,
                email: nil,
                phone: nil,
                aboutHTML: nil,
                schedule: []
            )
        }

        // teacher info
        let infoHTML = try await client.teacherInfoHTML(teacherId: tid)
        let info = try parser.parseTeacherInfo(infoHTML, teacherId: tid)

        // teacher schedule
        let schHTML = try await client.teacherScheduleHTML(
            teacherId: tid,
            from: from,
            to: to,
            interval: intervalType
        )
        let sched = try parser.parseSchedule(schHTML)

        return TeacherCard(
            id: tid,
            name: fallbackName ?? info.name,
            title: info.title,
            department: info.dept,
            email: info.email,
            phone: info.phone,
            aboutHTML: info.aboutHTML,
            schedule: sched
        )
    }
}

/// Протокол, чтобы AggregationService не зависел от конкретной реализации.
protocol TeacherDetailsProvider: Sendable {
    func getTeacherCard(
        id: Int?,
        fallbackName: String?,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> TeacherCard
}

/// Кэширующая обёртка над TeacherDetailsService.
struct CachedTeacherDetailsService: TeacherDetailsProvider, Sendable {
    let base: TeacherDetailsService
    let cache: InMemoryCacheStore

    func getTeacherCard(
        id: Int?,
        fallbackName: String?,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> TeacherCard {

        // если нет id — смысла кешировать нет, сразу собираем фолбек
        guard let tid = id else {
            return try await base.fetchTeacherCard(
                teacherId: nil,
                fallbackName: fallbackName,
                from: from,
                to: to,
                intervalType: intervalType
            )
        }

        let key = TeacherCacheKey(
            teacherId: tid,
            from: from,
            to: to,
            intervalRaw: intervalType.rawValue
        )

        if let cached = await cache.getTeacher(for: key) {
            return cached
        }

        let fresh = try await base.fetchTeacherCard(
            teacherId: tid,
            fallbackName: fallbackName,
            from: from,
            to: to,
            intervalType: intervalType
        )
        await cache.setTeacher(fresh, for: key)
        return fresh
    }
}