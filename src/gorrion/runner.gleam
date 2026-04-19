//// Executes migration SQL within transactions.

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/result
import gleam/string
import gorrion/tracker
import gorrion/types.{
  type Migration, type MigrationError, MigrationFailed, RollbackFailed,
}
import pog

/// Apply a single migration: execute the up SQL, then record it.
/// Both steps run inside the same database transaction so that a crash or
/// rollback between them can never leave the schema mutated without a
/// matching `_schema_migrations` row (or vice versa).
pub fn apply_migration(
  db: pog.Connection,
  migration: Migration,
) -> Result(Nil, MigrationError) {
  io.println(
    "  Applying migration "
    <> int.to_string(migration.version)
    <> ": "
    <> migration.name,
  )

  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  let tx_result =
    pog.transaction(db, fn(tx) {
      use _ <- result.try(
        migration.up
        |> pog.query
        |> pog.returning(decoder)
        |> pog.execute(tx)
        |> result.map(fn(_) { Nil })
        |> result.map_error(fn(e) {
          MigrationFailed(
            version: migration.version,
            name: migration.name,
            reason: string.inspect(e),
          )
        }),
      )

      tracker.record(tx, migration.version, migration.name)
    })

  case tx_result {
    Ok(Nil) -> Ok(Nil)
    Error(pog.TransactionRolledBack(migration_error)) -> Error(migration_error)
    Error(pog.TransactionQueryError(query_error)) ->
      Error(MigrationFailed(
        version: migration.version,
        name: migration.name,
        reason: string.inspect(query_error),
      ))
  }
}

/// Revert a single migration: execute the down SQL, then remove the record.
/// If no down SQL was provided (empty string), just removes the tracking record.
/// Both steps run inside the same transaction for the same atomicity reason
/// described on `apply_migration`.
pub fn revert_migration(
  db: pog.Connection,
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
      tracker.remove(db, migration.version)
    }
    down_sql -> {
      let decoder = decode.map(decode.dynamic, fn(_) { Nil })

      let tx_result =
        pog.transaction(db, fn(tx) {
          use _ <- result.try(
            down_sql
            |> pog.query
            |> pog.returning(decoder)
            |> pog.execute(tx)
            |> result.map(fn(_) { Nil })
            |> result.map_error(fn(e) {
              RollbackFailed(
                version: migration.version,
                name: migration.name,
                reason: string.inspect(e),
              )
            }),
          )

          tracker.remove(tx, migration.version)
        })

      case tx_result {
        Ok(Nil) -> Ok(Nil)
        Error(pog.TransactionRolledBack(migration_error)) ->
          Error(migration_error)
        Error(pog.TransactionQueryError(query_error)) ->
          Error(RollbackFailed(
            version: migration.version,
            name: migration.name,
            reason: string.inspect(query_error),
          ))
      }
    }
  }
}
