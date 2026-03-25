//// Types for the gorrion migration system.

/// A database migration with up (apply) and down (rollback) SQL.
pub type Migration {
  Migration(version: Int, name: String, up: String, down: String)
}

/// Record of an applied migration stored in _schema_migrations.
pub type AppliedMigration {
  AppliedMigration(version: Int, name: String, applied_at: String)
}

/// Errors that can occur during migration operations.
pub type MigrationError {
  QueryError(String)
  MigrationFailed(version: Int, name: String, reason: String)
  RollbackFailed(version: Int, name: String, reason: String)
  NoMigrationsToRollback
  FileError(String)
}

/// Status report showing applied and pending migrations.
pub type MigrationStatus {
  MigrationStatus(applied: List(AppliedMigration), pending: List(Migration))
}
