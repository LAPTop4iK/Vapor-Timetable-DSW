import Vapor
import Fluent
import FluentPostgresDriver
import Foundation

public func runSyncRunner() async throws {
    // Setup Vapor app
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)

    let app = try await Application.make(env)

    defer {
        Task {
            try? await app.asyncShutdown()
        }
    }

    let logger = app.logger

    logger.info("🔄 DSW Sync Runner starting...")

    // Load configuration
    let config = SyncConfig.default

    // Configure database
    if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
        logger.info("✅ PostgreSQL configured from DATABASE_URL")
    } else {
        // Fallback to individual env vars
        let hostname = Environment.get("DB_HOST") ?? "localhost"
        let port = Int(Environment.get("DB_PORT") ?? "5432") ?? 5432
        let username = Environment.get("DB_USER") ?? "vapor"
        let password = Environment.get("DB_PASSWORD") ?? ""
        let database = Environment.get("DB_NAME") ?? "dsw_timetable"

        app.databases.use(
            .postgres(
                configuration: .init(
                    hostname: hostname,
                    port: port,
                    username: username,
                    password: password,
                    database: database,
                    tls: .disable
                )
            ),
            as: .psql
        )
        logger.info("✅ PostgreSQL configured: \(username)@\(hostname):\(port)/\(database)")
    }

    // Register migrations
    app.migrations.add(CreateGroups())
    app.migrations.add(CreateTeachers())
    app.migrations.add(CreateGroupsList())
    app.migrations.add(CreateSyncStatus())

    // Run migrations
    logger.info("🔄 Running database migrations...")
    try await app.autoMigrate()
    logger.info("✅ Migrations completed")

    logger.info("📝 Configuration:")
    logger.info("  - Semester: \(config.semesterFrom) to \(config.semesterTo)")
    logger.info("  - Delay between groups: \(config.delayBetweenGroupsMs)ms")
    logger.info("  - Delay between teachers: \(config.delayBetweenTeachersMs)ms")

    // Initialize database service
    let dbService = DatabaseService(db: app.db)

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
        dbService: dbService,
        logger: logger,
        config: config
    )

    await runner.syncAll()

    logger.info("👋 Sync runner finished")

    try await app.asyncShutdown()
}
