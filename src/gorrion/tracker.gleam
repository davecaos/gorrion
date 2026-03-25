//// Manages the _schema_migrations tracking table.

import gleam/dynamic/decode
import gleam/result
import gleam/string
import gorrion/types.{
  type AppliedMigration, type MigrationError, AppliedMigration, QueryError,
}
import pog

/// Create the _schema_migrations table if it doesn't exist.
pub fn ensure_table(db: pog.Connection) -> Result(Nil, MigrationError) {
  let sql =
    "CREATE TABLE IF NOT EXISTS _schema_migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )"

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Get all applied migrations, sorted by version ascending.
pub fn get_applied(
  db: pog.Connection,
) -> Result(List(AppliedMigration), MigrationError) {
  let sql =
    "SELECT version, name, CAST(applied_at AS VARCHAR) as applied_at
     FROM _schema_migrations
     ORDER BY version ASC"

  let decoder = {
    use version <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use applied_at <- decode.field(2, decode.string)
    decode.success(AppliedMigration(version:, name:, applied_at:))
  }

  sql
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(response) { response.rows })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Record a migration as applied.
pub fn record(
  db: pog.Connection,
  version: Int,
  name: String,
) -> Result(Nil, MigrationError) {
  let sql =
    "INSERT INTO _schema_migrations (version, name) VALUES ($1, $2)"

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql
  |> pog.query
  |> pog.parameter(pog.int(version))
  |> pog.parameter(pog.text(name))
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Remove a migration record (used during rollback).
pub fn remove(
  db: pog.Connection,
  version: Int,
) -> Result(Nil, MigrationError) {
  let sql =
    "DELETE FROM _schema_migrations WHERE version = $1"

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  sql
  |> pog.query
  |> pog.parameter(pog.int(version))
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}

/// Get the highest applied migration version, or 0 if none.
pub fn current_version(db: pog.Connection) -> Result(Int, MigrationError) {
  let sql =
    "SELECT COALESCE(MAX(version), 0) as version FROM _schema_migrations"

  let decoder = {
    use version <- decode.field(0, decode.int)
    decode.success(version)
  }

  sql
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
  |> result.map(fn(response) {
    case response.rows {
      [version] -> version
      _ -> 0
    }
  })
  |> result.map_error(fn(e) { QueryError(string.inspect(e)) })
}
