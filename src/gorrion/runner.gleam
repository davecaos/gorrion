//// Executes migration SQL within transactions.

import common_sql as sql
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/result
import gleam/string
import gorrion/tracker
import gorrion/types.{
  type Migration, type MigrationError, MigrationFailed, RollbackFailed,
}

/// Apply a single migration: execute the up SQL, then record it.
pub fn apply_migration(
  driver: sql.Driver(conn),
  conn: conn,
  migration: Migration,
) -> Result(Nil, MigrationError) {
  io.println(
    "  Applying migration "
    <> int.to_string(migration.version)
    <> ": "
    <> migration.name,
  )

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  // Execute the up SQL
  use _ <- result.try(
    sql.execute(driver, conn, sql.Sql(migration.up), [], decoder)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(e) {
      MigrationFailed(
        version: migration.version,
        name: migration.name,
        reason: string.inspect(e),
      )
    }),
  )

  // Record the migration as applied
  tracker.record(driver, conn, migration.version, migration.name)
}

/// Revert a single migration: execute the down SQL, then remove the record.
/// If no down SQL was provided (empty string), just removes the tracking record.
pub fn revert_migration(
  driver: sql.Driver(conn),
  conn: conn,
  migration: Migration,
) -> Result(Nil, MigrationError) {
  io.println(
    "  Rolling back migration "
    <> int.to_string(migration.version)
    <> ": "
    <> migration.name,
  )

  case migration.down {
    "" -> {
      io.println("    (no down migration — removing record only)")
      tracker.remove(driver, conn, migration.version)
    }
    down_sql -> {
      let decoder = decode.map(decode.dynamic, fn(_) { Nil })

      use _ <- result.try(
        sql.execute(driver, conn, sql.Sql(down_sql), [], decoder)
        |> result.map(fn(_) { Nil })
        |> result.map_error(fn(e) {
          RollbackFailed(
            version: migration.version,
            name: migration.name,
            reason: string.inspect(e),
          )
        }),
      )

      tracker.remove(driver, conn, migration.version)
    }
  }
}
