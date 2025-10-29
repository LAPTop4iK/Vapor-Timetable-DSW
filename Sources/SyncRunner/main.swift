import DswCore
import Foundation
import Vapor
import Logging

@main
struct SyncRunner {
    static func main() async throws {
        print("═══════════════════════════════════════════════════════════════")
        print("  DSW Timetable Sync Runner")
        print("  Firestore Data Preloading Script")
        print("═══════════════════════════════════════════════════════════════")

        // Setup logging
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        defer {
            Task {
                try? await app.asyncShutdown()
            }
        }

        let logger = Logger(label: "sync-runner")

        // Read configuration from environment
        guard let projectId = Environment.get("FIRESTORE_PROJECT_ID") else {
            logger.error("FIRESTORE_PROJECT_ID environment variable not set")
            throw ExitCode.failure
        }

        guard let credentialsPath = Environment.get("FIRESTORE_CREDENTIALS_PATH") else {
            logger.error("FIRESTORE_CREDENTIALS_PATH environment variable not set")
            throw ExitCode.failure
        }

        let defaultFrom = Environment.get("DSW_DEFAULT_FROM") ?? "2025-09-06"
        let defaultTo = Environment.get("DSW_DEFAULT_TO") ?? "2026-02-08"
        let intervalRaw = Environment.get("DSW_DEFAULT_INTERVAL") ?? "semester"

        let intervalType: IntervalType
        switch intervalRaw.lowercased() {
        case "week": intervalType = .week
        case "month": intervalType = .month
        case "semester": intervalType = .semester
        default: intervalType = .semester
        }

        logger.info("Configuration loaded", metadata: [
            "projectId": .string(projectId),
            "from": .string(defaultFrom),
            "to": .string(defaultTo),
            "interval": .string(intervalRaw)
        ])

        // Initialize services
        // Create a temporary request to get access to Client protocol
        // This is needed because app.http.client.shared is HTTPClient, not Client
        let tempRequest = Request(application: app, on: app.eventLoopGroup.next())
        let client = tempRequest.client

        let firestoreService: FirestoreService

        do {
            firestoreService = try FirestoreService(
                projectId: projectId,
                credentialsPath: credentialsPath,
                client: client,
                logger: logger
            )
            logger.info("Firestore service initialized")
        } catch {
            logger.error("Failed to initialize Firestore service: \(error)")
            throw ExitCode.failure
        }

        // Initialize scraping services
        let dswClient = VaporDSWClient(client: client)
        let parser = SwiftSoupScheduleParser(logger: logger)
        let groupSearchParser = SwiftSoupGroupSearchParser()

        let groupSearchService = GroupSearchService(
            client: dswClient,
            parser: groupSearchParser,
            logger: logger
        )

        let teacherDetailsService = TeacherDetailsService(
            client: dswClient,
            parser: parser,
            logger: logger
        )

        let groupScheduleService = GroupScheduleService(
            client: dswClient,
            parser: parser,
            from: defaultFrom,
            to: defaultTo,
            intervalType: intervalType,
            logger: logger
        )

        // Start sync
        let startTime = Date()
        logger.info("Starting full sync at \(startTime)")

        do {
            // 1. Get all groups
            logger.info("Fetching list of all groups...")
            let allGroups = try await groupSearchService.search(query: "")
            logger.info("Found \(allGroups.count) groups")

            // Save groups list to Firestore
            try await firestoreService.saveGroupsList(allGroups)

            // Update sync status: started
            let syncStatus = FirestoreSyncStatusDocument.started(totalGroups: allGroups.count)
            try await firestoreService.updateSyncStatus(syncStatus)

            // 2. Process each group
            var processedGroups = 0
            var failedGroups = 0
            var errorLog: [String] = []

            // Cache for teachers (to avoid duplicate fetches in one run)
            var teacherCache: [Int: TeacherCard] = [:]
            var allTeacherIds: Set<Int> = []

            logger.info("Processing groups...")

            for (index, group) in allGroups.enumerated() {
                let progress = Double(index + 1) / Double(allGroups.count) * 100
                logger.info("[\(index + 1)/\(allGroups.count)] [\(String(format: "%.1f", progress))%] Processing group \(group.groupId): \(group.name)")

                do {
                    // Fetch group schedule
                    let schedule = try await groupScheduleService.fetch(groupId: group.groupId)

                    // Extract unique teacher IDs from schedule
                    let teacherIds = Set(schedule.compactMap(\.teacherId))
                    allTeacherIds.formUnion(teacherIds)

                    logger.debug("  - Found \(teacherIds.count) unique teachers in group \(group.groupId)")

                    // Fetch teacher details for new teachers
                    for teacherId in teacherIds {
                        if teacherCache[teacherId] == nil {
                            do {
                                let card = try await teacherDetailsService.fetchTeacherCard(
                                    teacherId: teacherId,
                                    from: defaultFrom,
                                    to: defaultTo,
                                    intervalType: intervalType
                                )
                                teacherCache[teacherId] = card
                                logger.debug("  - Fetched teacher \(teacherId): \(card.name ?? "unknown")")

                                // Throttle teacher requests
                                try await Task.sleep(for: .milliseconds(Int.random(in: 300...500)))
                            } catch {
                                logger.warning("  - Failed to fetch teacher \(teacherId): \(error)")
                                // Continue even if teacher fetch fails
                            }
                        }
                    }

                    // Save group to Firestore
                    try await firestoreService.saveGroup(
                        groupInfo: group,
                        schedule: schedule,
                        teacherIds: Array(teacherIds),
                        from: defaultFrom,
                        to: defaultTo,
                        intervalType: intervalType.rawValue
                    )

                    processedGroups += 1

                    // Throttle group requests
                    try await Task.sleep(for: .milliseconds(Int.random(in: 500...1000)))

                } catch {
                    failedGroups += 1
                    let errorMsg = "Failed to process group \(group.groupId): \(error)"
                    logger.error("\(errorMsg)")
                    errorLog.append(errorMsg)
                }

                // Log progress every 50 groups
                if (index + 1) % 50 == 0 {
                    logger.info("Progress: \(processedGroups) successful, \(failedGroups) failed, \(teacherCache.count) unique teachers")
                }
            }

            // 3. Save all teachers to Firestore
            logger.info("Saving \(teacherCache.count) teachers to Firestore...")
            var processedTeachers = 0
            var failedTeachers = 0

            for (teacherId, card) in teacherCache {
                do {
                    try await firestoreService.saveTeacher(card)
                    processedTeachers += 1
                } catch {
                    failedTeachers += 1
                    let errorMsg = "Failed to save teacher \(teacherId): \(error)"
                    logger.error("\(errorMsg)")
                    errorLog.append(errorMsg)
                }
            }

            // 4. Save list of all teachers
            logger.info("Saving list of all teacher IDs (\(allTeacherIds.count))...")
            try await firestoreService.saveAllTeachers(Array(allTeacherIds))

            // 5. Update final sync status
            let finalStatus = syncStatus.completed(
                processedGroups: processedGroups,
                failedGroups: failedGroups,
                totalTeachers: teacherCache.count,
                processedTeachers: processedTeachers,
                failedTeachers: failedTeachers,
                errorLog: errorLog
            )
            try await firestoreService.updateSyncStatus(finalStatus)

            let endTime = Date()
            let duration = Int(endTime.timeIntervalSince(startTime))

            logger.info("═══════════════════════════════════════════════════════════════")
            logger.info("Sync completed!", metadata: [
                "duration": .stringConvertible(duration),
                "processedGroups": .stringConvertible(processedGroups),
                "failedGroups": .stringConvertible(failedGroups),
                "processedTeachers": .stringConvertible(processedTeachers),
                "failedTeachers": .stringConvertible(failedTeachers),
                "status": .string(finalStatus.status)
            ])
            logger.info("═══════════════════════════════════════════════════════════════")

            if failedGroups > 0 || failedTeachers > 0 {
                throw ExitCode(1) // Partial success
            }

        } catch let error as ExitCode {
            throw error
        } catch {
            logger.error("Sync failed with error: \(error)")
            throw ExitCode.failure
        }

        try await app.asyncShutdown()
    }
}

// MARK: - Exit Code

struct ExitCode: Error {
    let code: Int32

    init(_ code: Int32) {
        self.code = code
    }

    static let success = ExitCode(0)
    static let failure = ExitCode(1)
}
