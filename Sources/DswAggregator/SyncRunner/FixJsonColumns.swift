import Fluent
import SQLKit

fileprivate enum MigrationSQLError: Error { case sqlUnavailable }

public struct FixJsonColumns: AsyncMigration {
    public func prepare(on database: Database) async throws {
        // Use SQLKit to run raw SQL on Postgres
        guard let sql = database as? SQLDatabase else { throw MigrationSQLError.sqlUnavailable }

        // Alter teachers.schedule from jsonb[] to jsonb
        try await sql.raw(
            """
            ALTER TABLE teachers
            ALTER COLUMN schedule
            TYPE jsonb
            USING to_jsonb(schedule);
            """
        ).run()
        
        // Alter groups.group_schedule from jsonb[] to jsonb
        try await sql.raw(
            """
            ALTER TABLE groups
            ALTER COLUMN group_schedule
            TYPE jsonb
            USING to_jsonb(group_schedule);
            """
        ).run()
    }
    
    public func revert(on database: Database) async throws {
        // Use SQLKit to run raw SQL on Postgres
        guard let sql = database as? SQLDatabase else { throw MigrationSQLError.sqlUnavailable }

        // Reverting from jsonb to jsonb[] is ambiguous.
        // Perform best-effort revert by wrapping the jsonb in a single-element array.
        try await sql.raw(
            """
            ALTER TABLE teachers
            ALTER COLUMN schedule
            TYPE jsonb[]
            USING ARRAY[schedule]::jsonb[];
            """
        ).run()
        
        try await sql.raw(
            """
            ALTER TABLE groups
            ALTER COLUMN group_schedule
            TYPE jsonb[]
            USING ARRAY[group_schedule]::jsonb[];
            """
        ).run()
    }
}
