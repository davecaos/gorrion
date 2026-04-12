//// Gorrion — Ecto-like driver-agnostic database migration library for Gleam.
////
//// Reads migration SQL from .sql files on disk, tracks applied migrations
//// in a `_schema_migrations` table, and supports forward migration and rollback.
////
//// Built on top of
//// [common_sql](https://hex.pm/packages/common_sql) and works with any
//// driver — SQLite, PostgreSQL, or any future driver package.
////
//// ## Usage
////
//// ```gleam
//// // Run all pending migrations
//// let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: "migrations")
////
//// // Roll back the most recent migration
//// let assert Ok(_) = gorrion.rollback(driver:, conn:, migrations_dir: "migrations")
////
//// // Check migration status
//// let assert Ok(status) = gorrion.status(driver:, conn:, migrations_dir: "migrations")
//// ```

import common_sql as sql
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/set
import gorrion/loader
import gorrion/runner
import gorrion/tracker
import gorrion/types.{
  type Migration, type MigrationError, type MigrationStatus, MigrationStatus,
  NoMigrationsToRollback,
}

/// Run all pending migrations in version order.
pub fn migrate(
  driver driver: sql.Driver(conn),
  conn conn: conn,
  migrations_dir dir: String,
) -> Result(Nil, MigrationError) {
  use migrations <- result.try(loader.load_migrations(dir))
  use #(pending, _applied) <- result.try(resolve(driver, conn, migrations))

  case pending {
    [] -> {
      io.println("No pending migrations")
      Ok(Nil)
    }
    _ -> {
      io.println(
        "Applying "
        <> int.to_string(list.length(pending))
        <> " pending migration(s)...",
      )
      list.try_fold(pending, Nil, fn(_, m) {
        runner.apply_migration(driver, conn, m)
      })
    }
  }
}

/// Roll back the most recently applied migration.
pub fn rollback(
  driver driver: sql.Driver(conn),
  conn conn: conn,
  migrations_dir dir: String,
) -> Result(Nil, MigrationError) {
  use migrations <- result.try(loader.load_migrations(dir))
  use #(_pending, applied) <- result.try(resolve(driver, conn, migrations))

  let applied_versions =
    applied
    |> list.map(fn(a) { a.version })
    |> set.from_list

  let latest =
    migrations
    |> list.filter(fn(m) { set.contains(applied_versions, m.version) })
    |> list.sort(fn(a, b) { int.compare(b.version, a.version) })
    |> list.first

  case latest {
    Error(_) -> Error(NoMigrationsToRollback)
    Ok(migration) -> {
      io.println("Rolling back 1 migration...")
      runner.revert_migration(driver, conn, migration)
    }
  }
}

/// Roll back all migrations down to (but not including) the target version.
pub fn rollback_to(
  driver driver: sql.Driver(conn),
  conn conn: conn,
  migrations_dir dir: String,
  target_version target: Int,
) -> Result(Nil, MigrationError) {
  use migrations <- result.try(loader.load_migrations(dir))
  use #(_pending, applied) <- result.try(resolve(driver, conn, migrations))

  let applied_versions =
    applied
    |> list.map(fn(a) { a.version })
    |> set.from_list

  let to_revert =
    migrations
    |> list.filter(fn(m) {
      set.contains(applied_versions, m.version) && m.version > target
    })
    |> list.sort(fn(a, b) { int.compare(b.version, a.version) })

  case to_revert {
    [] -> {
      io.println("No migrations to roll back")
      Ok(Nil)
    }
    _ -> {
      io.println(
        "Rolling back "
        <> int.to_string(list.length(to_revert))
        <> " migration(s)...",
      )
      list.try_fold(to_revert, Nil, fn(_, m) {
        runner.revert_migration(driver, conn, m)
      })
    }
  }
}

/// Get the current migration status: which are applied and which are pending.
pub fn status(
  driver driver: sql.Driver(conn),
  conn conn: conn,
  migrations_dir dir: String,
) -> Result(MigrationStatus, MigrationError) {
  use migrations <- result.try(loader.load_migrations(dir))
  use #(pending, applied) <- result.try(resolve(driver, conn, migrations))
  Ok(MigrationStatus(applied:, pending:))
}

/// Internal: ensure tracking table exists, get applied migrations,
/// and compute which migrations are pending.
fn resolve(
  driver: sql.Driver(conn),
  conn: conn,
  migrations: List(Migration),
) -> Result(#(List(Migration), List(types.AppliedMigration)), MigrationError) {
  use _ <- result.try(tracker.ensure_table(driver, conn))
  use applied <- result.try(tracker.get_applied(driver, conn))

  let applied_versions =
    applied
    |> list.map(fn(a) { a.version })
    |> set.from_list

  let pending =
    migrations
    |> list.filter(fn(m) { !set.contains(applied_versions, m.version) })
    |> list.sort(fn(a, b) { int.compare(a.version, b.version) })

  Ok(#(pending, applied))
}
