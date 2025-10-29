import Foundation
import Vapor

/// Сервис для работы с Google Firestore через REST API
actor FirestoreService {
    private let projectId: String
    private let auth: GoogleAuthService
    private let client: Client
    private let logger: Logger

    private var baseURL: String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    }

    init(
        projectId: String,
        credentialsPath: String,
        client: Client,
        logger: Logger
    ) throws {
        self.projectId = projectId
        self.auth = try GoogleAuthService(credentialsPath: credentialsPath, client: client, logger: logger)
        self.client = client
        self.logger = logger

        logger.info("Initialized FirestoreService for project: \(projectId)")
    }

    // MARK: - Groups

    /// Сохранить группу в Firestore
    func saveGroup(
        groupInfo: GroupInfo,
        schedule: [ScheduleEvent],
        teacherIds: [Int],
        from: String,
        to: String,
        intervalType: Int
    ) async throws {
        let document = FirestoreGroupDocument(
            groupInfo: groupInfo,
            schedule: schedule,
            teacherIds: teacherIds,
            from: from,
            to: to,
            intervalType: intervalType
        )

        try await upsertDocument(
            collection: "groups",
            documentId: String(groupInfo.groupId),
            data: document
        )

        logger.debug("Saved group \(groupInfo.groupId) to Firestore")
    }

    /// Получить группу из Firestore
    func getGroup(groupId: Int) async throws -> FirestoreGroupDocument? {
        return try await getDocument(
            collection: "groups",
            documentId: String(groupId),
            as: FirestoreGroupDocument.self
        )
    }

    // MARK: - Teachers

    /// Сохранить преподавателя в Firestore
    func saveTeacher(_ card: TeacherCard) async throws {
        let document = FirestoreTeacherDocument(teacherCard: card)

        try await upsertDocument(
            collection: "teachers",
            documentId: String(card.id),
            data: document
        )

        logger.debug("Saved teacher \(card.id) to Firestore")
    }

    /// Получить преподавателя из Firestore
    func getTeacher(teacherId: Int) async throws -> TeacherCard? {
        guard let doc = try await getDocument(
            collection: "teachers",
            documentId: String(teacherId),
            as: FirestoreTeacherDocument.self
        ) else {
            return nil
        }

        return doc.toTeacherCard()
    }

    /// Получить всех преподавателей по списку ID (батчами)
    func getAllTeachers(teacherIds: [Int]) async throws -> [TeacherCard] {
        let batchSize = 50
        var allTeachers: [TeacherCard] = []

        for batch in teacherIds.chunked(into: batchSize) {
            let teachers = try await withThrowingTaskGroup(of: TeacherCard?.self) { group in
                for teacherId in batch {
                    group.addTask {
                        try await self.getTeacher(teacherId: teacherId)
                    }
                }

                var results: [TeacherCard] = []
                for try await teacher in group {
                    if let teacher = teacher {
                        results.append(teacher)
                    }
                }
                return results
            }

            allTeachers.append(contentsOf: teachers)
        }

        logger.debug("Fetched \(allTeachers.count) teachers from Firestore")
        return allTeachers
    }

    // MARK: - Metadata

    /// Сохранить список всех групп
    func saveGroupsList(_ groups: [GroupInfo]) async throws {
        let document = FirestoreGroupsListDocument(
            groups: groups,
            totalCount: groups.count,
            lastUpdated: ISO8601DateFormatter().string(from: Date())
        )

        try await upsertDocument(
            collection: "metadata",
            documentId: "groupsList",
            data: document
        )

        logger.info("Saved groups list (\(groups.count) groups) to Firestore")
    }

    /// Получить список всех групп
    func getGroupsList() async throws -> [GroupInfo] {
        guard let doc = try await getDocument(
            collection: "metadata",
            documentId: "groupsList",
            as: FirestoreGroupsListDocument.self
        ) else {
            logger.warning("Groups list not found in Firestore")
            return []
        }

        return doc.groups
    }

    /// Сохранить список всех преподавателей
    func saveAllTeachers(_ teacherIds: [Int]) async throws {
        let document = FirestoreAllTeachersDocument(
            teacherIds: teacherIds,
            totalCount: teacherIds.count,
            lastUpdated: ISO8601DateFormatter().string(from: Date())
        )

        try await upsertDocument(
            collection: "metadata",
            documentId: "allTeachers",
            data: document
        )

        logger.info("Saved all teachers list (\(teacherIds.count) teachers) to Firestore")
    }

    /// Получить список всех ID преподавателей
    func getAllTeacherIds() async throws -> [Int] {
        guard let doc = try await getDocument(
            collection: "metadata",
            documentId: "allTeachers",
            as: FirestoreAllTeachersDocument.self
        ) else {
            logger.warning("All teachers list not found in Firestore")
            return []
        }

        return doc.teacherIds
    }

    /// Обновить статус синхронизации
    func updateSyncStatus(_ status: FirestoreSyncStatusDocument) async throws {
        try await upsertDocument(
            collection: "metadata",
            documentId: "lastSync",
            data: status
        )

        logger.info("Updated sync status: \(status.status)")
    }

    /// Получить статус последней синхронизации
    func getSyncStatus() async throws -> FirestoreSyncStatusDocument? {
        return try await getDocument(
            collection: "metadata",
            documentId: "lastSync",
            as: FirestoreSyncStatusDocument.self
        )
    }

    // MARK: - Private Helpers

    /// Создать или обновить документ в Firestore
    private func upsertDocument<T: Encodable>(
        collection: String,
        documentId: String,
        data: T
    ) async throws {
        let token = try await auth.getAccessToken()
        let url = "\(baseURL)/\(collection)/\(documentId)"

        // Конвертировать в Firestore формат
        let firestoreFields = try convertToFirestoreFields(data)

        let requestBody: [String: Any] = [
            "fields": firestoreFields
        ]

        let response = try await client.patch(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.contentType = .json
            req.body = .init(data: try JSONSerialization.data(withJSONObject: requestBody))
        }

        guard response.status == .ok else {
            let body = response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) ?? "no body"
            logger.error("Failed to upsert document \(collection)/\(documentId): \(response.status) - \(body)")
            throw Abort(.internalServerError, reason: "Failed to save to Firestore")
        }
    }

    /// Получить документ из Firestore
    private func getDocument<T: Decodable>(
        collection: String,
        documentId: String,
        as type: T.Type
    ) async throws -> T? {
        let token = try await auth.getAccessToken()
        let url = "\(baseURL)/\(collection)/\(documentId)"

        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        if response.status == .notFound {
            return nil
        }

        guard response.status == .ok else {
            let body = response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) ?? "no body"
            logger.error("Failed to get document \(collection)/\(documentId): \(response.status) - \(body)")
            throw Abort(.internalServerError, reason: "Failed to read from Firestore")
        }

        struct DocumentResponse: Codable {
            let fields: [String: FirestoreFieldValue]
        }

        let docResponse = try response.content.decode(DocumentResponse.self)
        let converted = try convertFromFirestoreFields(docResponse.fields, to: type)

        return converted
    }

    /// Конвертировать Swift значения в Firestore формат
    private func convertToFirestoreFields<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        return convertDictToFirestore(json)
    }

    private func convertDictToFirestore(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = convertValueToFirestore(value)
        }
        return result
    }

    private func convertValueToFirestore(_ value: Any) -> [String: Any] {
        if let string = value as? String {
            return ["stringValue": string]
        } else if let int = value as? Int {
            return ["integerValue": String(int)]
        } else if let double = value as? Double {
            return ["doubleValue": double]
        } else if let bool = value as? Bool {
            return ["booleanValue": bool]
        } else if let array = value as? [Any] {
            let values = array.map { convertValueToFirestore($0) }
            return ["arrayValue": ["values": values]]
        } else if let dict = value as? [String: Any] {
            return ["mapValue": ["fields": convertDictToFirestore(dict)]]
        } else if value is NSNull {
            return ["nullValue": NSNull()]
        } else {
            // Fallback to string
            return ["stringValue": String(describing: value)]
        }
    }

    /// Конвертировать Firestore формат в Swift значения
    private func convertFromFirestoreFields<T: Decodable>(
        _ fields: [String: FirestoreFieldValue],
        to type: T.Type
    ) throws -> T {
        let converted = convertFirestoreFieldsToDict(fields)
        let data = try JSONSerialization.data(withJSONObject: converted)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func convertFirestoreFieldsToDict(_ fields: [String: FirestoreFieldValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            result[key] = convertFirestoreValueToSwift(value)
        }
        return result
    }

    private func convertFirestoreValueToSwift(_ value: FirestoreFieldValue) -> Any {
        if let string = value.stringValue {
            return string
        } else if let intString = value.integerValue, let int = Int(intString) {
            return int
        } else if let double = value.doubleValue {
            return double
        } else if let bool = value.booleanValue {
            return bool
        } else if let array = value.arrayValue?.values {
            return array.map { convertFirestoreValueToSwift($0) }
        } else if let map = value.mapValue?.fields {
            return convertFirestoreFieldsToDict(map)
        } else {
            return NSNull()
        }
    }
}

// MARK: - Firestore Field Value (для парсинга)

struct FirestoreFieldValue: Codable {
    let stringValue: String?
    let integerValue: String?
    let doubleValue: Double?
    let booleanValue: Bool?
    let arrayValue: FirestoreArrayValueWrapper?
    let mapValue: FirestoreMapValueWrapper?
}

struct FirestoreArrayValueWrapper: Codable {
    let values: [FirestoreFieldValue]
}

struct FirestoreMapValueWrapper: Codable {
    let fields: [String: FirestoreFieldValue]
}

// MARK: - Array Chunking Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
