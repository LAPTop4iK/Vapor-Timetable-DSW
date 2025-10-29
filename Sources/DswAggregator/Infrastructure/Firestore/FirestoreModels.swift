import Foundation

// MARK: - Firestore Document Models

/// Документ группы в Firestore (groups/{groupId})
struct FirestoreGroupDocument: Codable, Sendable {
    let groupId: Int
    let groupCode: String
    let groupName: String
    let program: String
    let faculty: String
    let from: String
    let to: String
    let intervalType: Int
    let schedule: [ScheduleEvent]
    let teacherIds: [Int]
    let lastUpdated: String
    let syncStatus: String
}

/// Документ преподавателя в Firestore (teachers/{teacherId})
struct FirestoreTeacherDocument: Codable, Sendable {
    let id: Int
    let name: String?
    let title: String?
    let department: String?
    let email: String?
    let phone: String?
    let aboutHTML: String?
    let schedule: [ScheduleEvent]
    let lastUpdated: String
    let syncStatus: String
}

/// Список всех групп (metadata/groupsList)
struct FirestoreGroupsListDocument: Codable, Sendable {
    let groups: [GroupInfo]
    let totalCount: Int
    let lastUpdated: String
}

/// Список всех преподавателей (metadata/allTeachers)
struct FirestoreAllTeachersDocument: Codable, Sendable {
    let teacherIds: [Int]
    let totalCount: Int
    let lastUpdated: String
}

/// Статус синхронизации (metadata/lastSync)
struct FirestoreSyncStatusDocument: Codable, Sendable {
    let startedAt: String
    let completedAt: String?
    let status: String // "running", "ok", "partial_error", "failed"
    let totalGroups: Int
    let processedGroups: Int
    let failedGroups: Int
    let totalTeachers: Int
    let processedTeachers: Int
    let failedTeachers: Int
    let errorLog: [String]
    let durationSeconds: Int?
}

// MARK: - Firestore REST API Response Models

struct FirestoreDocument<T: Codable>: Codable {
    let name: String?
    let fields: T
    let createTime: String?
    let updateTime: String?
}

struct FirestoreValue: Codable {
    let stringValue: String?
    let integerValue: String?
    let doubleValue: Double?
    let booleanValue: Bool?
    let arrayValue: FirestoreArrayValue?
    let mapValue: FirestoreMapValue?

    init(string: String) {
        self.stringValue = string
        self.integerValue = nil
        self.doubleValue = nil
        self.booleanValue = nil
        self.arrayValue = nil
        self.mapValue = nil
    }

    init(int: Int) {
        self.stringValue = nil
        self.integerValue = String(int)
        self.doubleValue = nil
        self.booleanValue = nil
        self.arrayValue = nil
        self.mapValue = nil
    }

    init(double: Double) {
        self.stringValue = nil
        self.integerValue = nil
        self.doubleValue = double
        self.booleanValue = nil
        self.arrayValue = nil
        self.mapValue = nil
    }

    init(bool: Bool) {
        self.stringValue = nil
        self.integerValue = nil
        self.doubleValue = nil
        self.booleanValue = bool
        self.arrayValue = nil
        self.mapValue = nil
    }
}

struct FirestoreArrayValue: Codable {
    let values: [FirestoreValue]
}

struct FirestoreMapValue: Codable {
    let fields: [String: FirestoreValue]
}

// MARK: - Helper Extensions

extension FirestoreGroupDocument {
    init(
        groupInfo: GroupInfo,
        schedule: [ScheduleEvent],
        teacherIds: [Int],
        from: String,
        to: String,
        intervalType: Int
    ) {
        self.groupId = groupInfo.groupId
        self.groupCode = groupInfo.code
        self.groupName = groupInfo.name
        self.program = groupInfo.program
        self.faculty = groupInfo.faculty
        self.from = from
        self.to = to
        self.intervalType = intervalType
        self.schedule = schedule
        self.teacherIds = teacherIds
        self.lastUpdated = ISO8601DateFormatter().string(from: Date())
        self.syncStatus = "ok"
    }
}

extension FirestoreTeacherDocument {
    init(teacherCard: TeacherCard) {
        self.id = teacherCard.id
        self.name = teacherCard.name
        self.title = teacherCard.title
        self.department = teacherCard.department
        self.email = teacherCard.email
        self.phone = teacherCard.phone
        self.aboutHTML = teacherCard.aboutHTML
        self.schedule = teacherCard.schedule
        self.lastUpdated = ISO8601DateFormatter().string(from: Date())
        self.syncStatus = "ok"
    }

    func toTeacherCard() -> TeacherCard {
        TeacherCard(
            id: id,
            name: name,
            title: title,
            department: department,
            email: email,
            phone: phone,
            aboutHTML: aboutHTML,
            schedule: schedule
        )
    }
}

extension FirestoreSyncStatusDocument {
    static func started(totalGroups: Int) -> Self {
        FirestoreSyncStatusDocument(
            startedAt: ISO8601DateFormatter().string(from: Date()),
            completedAt: nil,
            status: "running",
            totalGroups: totalGroups,
            processedGroups: 0,
            failedGroups: 0,
            totalTeachers: 0,
            processedTeachers: 0,
            failedTeachers: 0,
            errorLog: [],
            durationSeconds: nil
        )
    }

    func completed(
        processedGroups: Int,
        failedGroups: Int,
        totalTeachers: Int,
        processedTeachers: Int,
        failedTeachers: Int,
        errorLog: [String]
    ) -> Self {
        let completedAt = Date()
        let startDate = ISO8601DateFormatter().date(from: startedAt) ?? Date()
        let duration = Int(completedAt.timeIntervalSince(startDate))

        return FirestoreSyncStatusDocument(
            startedAt: startedAt,
            completedAt: ISO8601DateFormatter().string(from: completedAt),
            status: failedGroups > 0 ? "partial_error" : "ok",
            totalGroups: totalGroups,
            processedGroups: processedGroups,
            failedGroups: failedGroups,
            totalTeachers: totalTeachers,
            processedTeachers: processedTeachers,
            failedTeachers: failedTeachers,
            errorLog: Array(errorLog.prefix(100)), // First 100 errors
            durationSeconds: duration
        )
    }
}
