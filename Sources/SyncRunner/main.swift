//
//  main.swift
//  SyncRunner
//
//  Executable entrypoint for syncing all groups to Firestore
//

import Vapor
import Foundation

@main
struct SyncRunnerApp {
    static func main() async throws {
        // Setup Vapor app (we need it for HTTP client, but won't start the server)
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try Application(env)
        defer { app.shutdown() }

        let logger = app.logger

        logger.info("🔄 DSW Sync Runner starting...")

        // Load configuration
        let config = SyncConfig.default

        guard let projectId = Environment.get("FIRESTORE_PROJECT_ID") else {
            logger.error("❌ FIRESTORE_PROJECT_ID not set")
            throw Abort(.internalServerError, reason: "FIRESTORE_PROJECT_ID required")
        }

        guard let credPath = Environment.get("FIRESTORE_CREDENTIALS_PATH") else {
            logger.error("❌ FIRESTORE_CREDENTIALS_PATH not set")
            throw Abort(.internalServerError, reason: "FIRESTORE_CREDENTIALS_PATH required")
        }

        logger.info("📝 Configuration:")
        logger.info("  - Project ID: \(projectId)")
        logger.info("  - Credentials: \(credPath)")
        logger.info("  - Semester: \(config.semesterFrom) to \(config.semesterTo)")
        logger.info("  - Delay between groups: \(config.delayBetweenGroupsMs)ms")
        logger.info("  - Delay between teachers: \(config.delayBetweenTeachersMs)ms")

        // Initialize Firestore
        logger.info("🔐 Initializing Firestore...")
        let credentials = try ServiceAccountCredentials.load(from: credPath)

        let firestoreClient = try FirestoreClient(
            projectId: projectId,
            credentials: credentials,
            client: app.client,
            logger: logger
        )

        let firestoreWriter = FirestoreWriter(
            client: firestoreClient,
            logger: logger
        )

        // Initialize services
        let dswClient = VaporDSWClient(client: app.client)
        let parser = SwiftSoupScheduleParser(logger: logger)
        let teacherService = TeacherDetailsService(client: dswClient, parser: parser)

        // Create and run sync runner
        let runner = SyncAllGroupsRunner(
            client: dswClient,
            httpClient: app.client,
            parser: parser,
            teacherService: teacherService,
            writer: firestoreWriter,
            logger: logger,
            config: config
        )

        await runner.syncAll()

        logger.info("👋 Sync runner finished")
    }
}
