//
//  SyncAllGroupsRunner.swift
//  DswAggregator
//
//  Main runner for synchronizing all groups to PostgreSQL
//

import Vapor
import Fluent
import Foundation

/// Main sync runner that processes all groups and saves to PostgreSQL
public actor SyncAllGroupsRunner {
    private let client: any DSWClient
    private let httpClient: any Client
    private let parser: any ScheduleParser
    private let teacherService: TeacherDetailsService
    private let dbService: DatabaseService
    private let logger: Logger
    private let config: SyncConfig

    // In-memory cache for teachers within this sync run
    private var teacherCache: [Int: TeacherCard] = [:]

    public init(
        client: any DSWClient,
        httpClient: any Client,
        parser: any ScheduleParser,
        teacherService: TeacherDetailsService,
        dbService: DatabaseService,
        logger: Logger,
        config: SyncConfig
    ) {
        self.client = client
        self.httpClient = httpClient
        self.parser = parser
        self.teacherService = teacherService
        self.dbService = dbService
        self.logger = logger
        self.config = config
    }

    /// Run the full sync process
    public func syncAll() async {
        let startTime = Date()
        logger.info("🚀 Starting sync of all groups...")

        // Mark sync as in progress
        do {
            try await dbService.saveSyncStatus(
                timestamp: Date(),
                status: "in_progress",
                totalGroups: 0,
                processedGroups: 0,
                failedGroups: 0,
                errorMessage: nil,
                duration: 0,
                startedAt: startTime
            )

            // 1. Get all groups
            logger.info("📋 Fetching all groups...")
            let allGroups = try await fetchAllGroups()
            logger.info("✅ Found \(allGroups.count) groups")

            // 2. Process each group
            var processedCount = 0
            var failedCount = 0
            var allTeacherIds: Set<Int> = []

            for (index, group) in allGroups[0...10].enumerated() {
                do {
                    logger.info("[\(index + 1)/\(allGroups.count)] Processing group \(group.groupId): \(group.name)")

                    let teacherIds = try await processGroup(group)
                    allTeacherIds.formUnion(teacherIds)

                    processedCount += 1

                    // Throttle between groups to avoid overwhelming the university server
                    if index < allGroups.count - 1 {
                        try await Task.sleep(nanoseconds: UInt64(config.delayBetweenGroupsMs) * 1_000_000)
                    }
                } catch {
                    logger.error("❌ Failed to process group \(group.groupId): \(error)")
                    failedCount += 1
                }
            }

            // 3. Save groups list
            logger.info("💾 Saving groups list...")
            try await dbService.saveGroupsList(groups: allGroups)

            // 4. Final sync status
            let duration = Date().timeIntervalSince(startTime)
            try await dbService.saveSyncStatus(
                timestamp: Date(),
                status: "ok",
                totalGroups: allGroups.count,
                processedGroups: processedCount,
                failedGroups: failedCount,
                errorMessage: nil,
                duration: duration,
                startedAt: startTime
            )

            logger.info("✅ Sync completed successfully!")
            logger.info("📊 Stats: \(processedCount) groups processed, \(failedCount) failed, \(allTeacherIds.count) unique teachers, duration: \(Int(duration))s")

        } catch {
            // Save error status
            let duration = Date().timeIntervalSince(startTime)

            do {
                try await dbService.saveSyncStatus(
                    timestamp: Date(),
                    status: "error",
                    totalGroups: 0,
                    processedGroups: 0,
                    failedGroups: 0,
                    errorMessage: error.localizedDescription,
                    duration: duration,
                    startedAt: startTime
                )
            } catch {
                logger.error("Failed to save error status: \(error)")
            }

            logger.error("❌ Sync failed: \(error)")
        }
    }

    // MARK: - Private Methods

    private func fetchAllGroups() async throws -> [GroupInfo] {
        // Fetch all groups by searching with "sem" query (same as aggregator default)
        // The university site returns all groups when query is "sem" (semester groups)
        let htmlResponse = try await httpClient.post(URI(string: "https://harmonogramy.dsw.edu.pl/Plany/ZnajdzGrupe")) { request in
            request.headers.contentType = .urlEncodedForm
            try request.content.encode(["nazwaGrupy": "sem"], as: .urlEncodedForm)
        }

        guard htmlResponse.status == .ok,
              let html = htmlResponse.body?.string
        else {
            throw Abort(
                .badGateway,
                reason: "DSW returned \(htmlResponse.status.code)"
            )
        }

        let searchParser = SwiftSoupGroupSearchParser()
        return try searchParser.parseGroups(html)
    }

    private func processGroup(_ group: GroupInfo) async throws -> Set<Int> {
        // 1. Get group schedule for the semester
        let scheduleHTML = try await client.groupScheduleHTML(
            groupId: group.groupId,
            from: config.semesterFrom,
            to: config.semesterTo,
            interval: .semester
        )

        let schedule = try parser.parseSchedule(scheduleHTML)

        // 2. Extract unique teachers from schedule (with names as fallback)
        var uniqueTeachers: [Int: String] = [:] // teacherId -> teacherName
        for event in schedule {
            if let teacherId = event.teacherId {
                // Keep first occurrence of name for each teacher ID
                if uniqueTeachers[teacherId] == nil {
                    uniqueTeachers[teacherId] = event.teacherName
                }
            }
        }

        // 3. Fetch teacher details (with caching)
        for (teacherId, teacherName) in uniqueTeachers {
            if teacherCache[teacherId] == nil {
                do {
                    let card = try await fetchTeacherCard(
                        teacherId: teacherId,
                        fallbackName: teacherName
                    )
                    teacherCache[teacherId] = card

                    // Save teacher to PostgreSQL immediately
                    try await dbService.saveTeacher(card: card)

                    // Small delay between teacher requests
                    try await Task.sleep(nanoseconds: UInt64(config.delayBetweenTeachersMs) * 1_000_000)

                } catch {
                    logger.warning("Failed to fetch teacher \(teacherId): \(error)")
                }
            }
        }

        // 4. Save group to PostgreSQL
        let teacherIds = Array(uniqueTeachers.keys).sorted()

        try await dbService.saveGroup(
            groupId: group.groupId,
            fromDate: config.semesterFrom,
            toDate: config.semesterTo,
            intervalType: IntervalType.semester.rawValue,
            groupSchedule: schedule,
            teacherIds: teacherIds,
            groupInfo: group
        )

        return Set(uniqueTeachers.keys)
    }

    private func fetchTeacherCard(teacherId: Int, fallbackName: String?) async throws -> TeacherCard {
        return try await teacherService.fetchTeacherCard(
            teacherId: teacherId,
            fallbackName: fallbackName,
            from: config.semesterFrom,
            to: config.semesterTo,
            intervalType: .semester
        )
    }
}

/// Configuration for sync runner
public struct SyncConfig {
    public let semesterFrom: String
    public let semesterTo: String
    public let delayBetweenGroupsMs: Int  // milliseconds
    public let delayBetweenTeachersMs: Int  // milliseconds

    public init(semesterFrom: String, semesterTo: String, delayBetweenGroupsMs: Int, delayBetweenTeachersMs: Int) {
        self.semesterFrom = semesterFrom
        self.semesterTo = semesterTo
        self.delayBetweenGroupsMs = delayBetweenGroupsMs
        self.delayBetweenTeachersMs = delayBetweenTeachersMs
    }

    public static var `default`: SyncConfig {
        return SyncConfig(
            semesterFrom: Environment.get("DSW_DEFAULT_FROM") ?? "2025-09-06",
            semesterTo: Environment.get("DSW_DEFAULT_TO") ?? "2026-02-08",
            delayBetweenGroupsMs: Int(Environment.get("SYNC_DELAY_GROUPS_MS") ?? "150") ?? 150,
            delayBetweenTeachersMs: Int(Environment.get("SYNC_DELAY_TEACHERS_MS") ?? "100") ?? 100
        )
    }
}
