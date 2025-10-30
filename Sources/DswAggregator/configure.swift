import Vapor
import Fluent
import FluentPostgresDriver

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.logger.logLevel = .debug

    // Configure database
    if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
        app.logger.info("PostgreSQL configured from DATABASE_URL")
    } else {
        // Fallback to individual env vars
        let hostname = Environment.get("DB_HOST") ?? "localhost"
        let port = Int(Environment.get("DB_PORT") ?? "5432") ?? 5432
        let username = Environment.get("DB_USER") ?? "vapor"
        let password = Environment.get("DB_PASSWORD") ?? ""
        let database = Environment.get("DB_NAME") ?? "dsw_timetable"

        app.databases.use(
            .postgres(
                hostname: hostname,
                port: port,
                username: username,
                password: password,
                database: database
            ),
            as: .psql
        )
        app.logger.info("PostgreSQL configured: \(username)@\(hostname):\(port)/\(database)")
    }

    // Register migrations
    app.migrations.add(CreateGroups())
    app.migrations.add(CreateTeachers())
    app.migrations.add(CreateGroupsList())
    app.migrations.add(CreateSyncStatus())

    // Run migrations automatically on startup
    if app.environment != .testing {
        try await app.autoMigrate()
    }

    // register routes
    try routes(app)
}
