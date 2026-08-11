import Foundation
import GOCompanionPersistence
import Testing

@Test func allThreeDatabasesMigrateIndependently() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("go-companion-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let databases = try DatabaseSet(directory: root)
    #expect(try databases.user.scalarInt("SELECT COUNT(*) FROM schema_migrations") == 1)
    #expect(try databases.knowledge.scalarInt("SELECT COUNT(*) FROM schema_migrations") == 1)
    #expect(try databases.derived.scalarInt("SELECT COUNT(*) FROM schema_migrations") == 1)
    #expect(try databases.user.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE name = 'pokemon'") == 1)
    #expect(try databases.knowledge.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE name = 'species_forms'") == 1)
    #expect(try databases.derived.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE name = 'derived_entries'") == 1)
}

@Test func migrationsAreIdempotentAndDetectMutation() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("go-companion-migration-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let database = try SQLiteDatabase(path: path)
    let runner = MigrationRunner()
    let original = Migration(version: 1, name: "create_sample", sql: "CREATE TABLE sample(id TEXT PRIMARY KEY);")
    try runner.migrate(database, using: [original])
    try runner.migrate(database, using: [original])
    #expect(try database.scalarInt("SELECT COUNT(*) FROM schema_migrations") == 1)

    let changed = Migration(version: 1, name: "create_sample", sql: "CREATE TABLE changed(id TEXT PRIMARY KEY);")
    #expect(throws: SQLiteError.migrationChecksumChanged(version: 1)) {
        try runner.migrate(database, using: [changed])
    }
}
