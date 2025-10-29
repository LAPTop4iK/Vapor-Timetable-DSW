import Foundation
import Vapor

/// Сервис для получения агрегированных данных из Firestore
struct FirestoreAggregationService {
    private let firestore: FirestoreService
    private let logger: Logger

    init(firestore: FirestoreService, logger: Logger) {
        self.firestore = firestore
        self.logger = logger
    }

    /// Получить агрегированный ответ для группы
    /// ВАЖНО: Теперь возвращает ВСЕХ преподавателей университета, а не только из текущей группы
    func aggregate(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> AggregateResponse {
        // 1. Получить данные группы из Firestore
        guard let groupDoc = try await firestore.getGroup(groupId: groupId) else {
            logger.warning("Group \(groupId) not found in Firestore")
            throw Abort(.notFound, reason: "Group not found")
        }

        // 2. Получить список ВСЕХ преподавателей университета
        let allTeacherIds = try await firestore.getAllTeacherIds()
        logger.debug("Fetching \(allTeacherIds.count) teachers for aggregate response")

        // 3. Получить карточки всех преподавателей
        let teacherCards = try await firestore.getAllTeachers(teacherIds: allTeacherIds)

        // 4. Сформировать ответ
        let response = AggregateResponse(
            groupId: groupId,
            from: groupDoc.from,
            to: groupDoc.to,
            intervalType: groupDoc.intervalType,
            groupSchedule: groupDoc.schedule,
            teachers: teacherCards,
            fetchedAt: ISO8601DateFormatter().string(from: Date())
        )

        logger.info("Fetched aggregate for group \(groupId) from Firestore with \(teacherCards.count) teachers")

        return response
    }
}

/// Сервис для получения списка групп из Firestore
struct FirestoreGroupSearchService {
    private let firestore: FirestoreService
    private let logger: Logger

    init(firestore: FirestoreService, logger: Logger) {
        self.firestore = firestore
        self.logger = logger
    }

    /// Поиск групп по запросу (локальная фильтрация)
    func search(query: String) async throws -> [GroupInfo] {
        // Получить полный список групп из Firestore
        let allGroups = try await firestore.getGroupsList()

        // Если query пустой - вернуть все
        if query.isEmpty || query == "sem" {
            return allGroups
        }

        // Фильтровать по query (case-insensitive)
        let lowercaseQuery = query.lowercased()
        let filtered = allGroups.filter { group in
            group.code.lowercased().contains(lowercaseQuery) ||
            group.name.lowercased().contains(lowercaseQuery) ||
            group.program.lowercased().contains(lowercaseQuery)
        }

        logger.debug("Searched groups with query '\(query)': found \(filtered.count)/\(allGroups.count)")

        return filtered
    }
}
