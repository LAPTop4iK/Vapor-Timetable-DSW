//
//  AggregationService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

/// Собирает:
/// - расписание группы
/// - карточки всех уникальных преподавателей (через TeacherDetailsProvider)
struct AggregationService: Sendable {
    let client: any DSWClient
    let parser: any ScheduleParser
    let teacherService: any TeacherDetailsProvider
    let batchSize: Int

    init(
        client: any DSWClient,
        parser: any ScheduleParser,
        teacherService: any TeacherDetailsProvider,
        batchSize: Int = 6
    ) {
        self.client = client
        self.parser = parser
        self.teacherService = teacherService
        self.batchSize = max(1, batchSize)
    }

    func aggregate(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> AggregateResponse {

        // 1) расписание группы
        let gHTML = try await client.groupScheduleHTML(
            groupId: groupId,
            from: from,
            to: to,
            interval: intervalType
        )
        let groupEvents = try parser.parseSchedule(gHTML)

        // 2) уникальные преподаватели
        struct LiteT: Hashable, Sendable {
            let id: Int?
            let name: String?
        }

        var set = Set<LiteT>()
        for e in groupEvents {
            set.insert(LiteT(id: e.teacherId, name: e.teacherName))
        }

        var teachers = Array(set)
        teachers.sort { ($0.name ?? "") < ($1.name ?? "") }

        // 3) батч-параллельное получение карточек преподавателей
        var cards = Array(
            repeating: TeacherCard(
                id: 0,
                name: nil,
                title: nil,
                department: nil,
                email: nil,
                phone: nil,
                aboutHTML: nil,
                schedule: []
            ),
            count: teachers.count
        )

        for batchStart in stride(from: 0, to: teachers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, teachers.count)
            let slice = teachers[batchStart..<batchEnd]

            try await withThrowingTaskGroup(of: (Int, TeacherCard).self) { tg in
                for (offset, t) in slice.enumerated() {
                    let index = batchStart + offset
                    tg.addTask { @Sendable in
                        do {
                            let card = try await teacherService.getTeacherCard(
                                id: t.id,
                                fallbackName: t.name,
                                from: from,
                                to: to,
                                intervalType: intervalType
                            )
                            return (index, card)
                        } catch {
                            // fallback (если не удалось)
                            let fallback = TeacherCard(
                                id: t.id ?? 0,
                                name: t.name,
                                title: nil,
                                department: nil,
                                email: nil,
                                phone: nil,
                                aboutHTML: nil,
                                schedule: []
                            )
                            return (index, fallback)
                        }
                    }
                }

                for try await (i, card) in tg {
                    cards[i] = card
                }
            }
        }

        // 4) финальный ответ
        let isoNow = ISO8601DateFormatter().string(from: Date())
        return AggregateResponse(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType.rawValue,
            groupSchedule: groupEvents,
            teachers: cards,
            currentPeriodTeachers: nil, // For live mode, currentPeriodTeachers is nil
            fetchedAt: isoNow
        )
    }
}
