//// Manages the _schema_migrations tracking table.

import common_sql as sql
import gleam/dynamic/decode
import gleam/result
import gleam/string
import gorrion/types.{
  type AppliedMigration, type MigrationError, AppliedMigration, QueryError,
}

/// Create the _schema_migrations table if it doesn't exist.
pub fn ensure_table(
  driver: sql.Driver(conn),
  conn: conn,
) -> Result(Nil, MigrationError) {
  let query =
    sql.Portable(
      "CREATE TABLE IF NOT EXISTS _schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )",
    )

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql.execute(driver, conn, query, [], decoder)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Get all applied migrations, sorted by version ascending.
pub fn get_applied(
  driver: sql.Driver(conn),
  conn: conn,
) -> Result(List(AppliedMigration), MigrationError) {
  let query =
    sql.Portable(
      "SELECT version, name, CAST(applied_at AS TEXT) AS applied_at
       FROM _schema_migrations
       ORDER BY version ASC",
    )

  let decoder = {
    use version <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use applied_at <- decode.field(2, decode.string)
    decode.success(AppliedMigration(version:, name:, applied_at:))
  }

  sql.execute(driver, conn, query, [], decoder)
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Record a migration as applied.
pub fn record(
  driver: sql.Driver(conn),
  conn: conn,
  version: Int,
  name: String,
) -> Result(Nil, MigrationError) {
  let query =
    sql.Portable(
      "INSERT INTO _schema_migrations (version, name) VALUES ($1, $2)",
    )

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql.execute(
    driver,
    conn,
    query,
    [sql.PInt(version), sql.PString(name)],
    decoder,
  )
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Remove a migration record (used during rollback).
pub fn remove(
  driver: sql.Driver(conn),
  conn: conn,
  version: Int,
) -> Result(Nil, MigrationError) {
  let query = sql.Portable("DELETE FROM _schema_migrations WHERE version = $1")

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql.execute(driver, conn, query, [sql.PInt(version)], decoder)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Get the highest applied migration version, or 0 if none.
pub fn current_version(
  driver: sql.Driver(conn),
  conn: conn,
) -> Result(Int, MigrationError) {
  let query =
    sql.Portable(
      "SELECT COALESCE(MAX(version), 0) AS version FROM _schema_migrations",
    )

  let decoder = {
    use version <- decode.field(0, decode.int)
    decode.success(version)
  }

  sql.execute(driver, conn, query, [], decoder)
  |> result.map(fn(rows) {
    case rows {
      [version] -> version
      _ -> 0
    }
  })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}
