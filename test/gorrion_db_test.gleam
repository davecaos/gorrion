// Integration tests — run against a real SQLite :memory: database.

import common_sql as sql
import common_sql_sqlite
import gleam/list
import gleeunit/should
import gorrion
import simplifile

fn setup_fixture_dir(dir: String) {
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
}

fn cleanup_fixture_dir(dir: String) {
  let _ = simplifile.delete(dir)
}

fn with_migration_dir(
  dir: String,
  files: List(#(String, String)),
  f: fn() -> a,
) -> a {
  let _ = setup_fixture_dir(dir)
  list.each(files, fn(entry) {
    let #(name, content) = entry
    let assert Ok(_) = simplifile.write(dir <> "/" <> name, content)
  })
  let result = f()
  let _ = cleanup_fixture_dir(dir)
  result
}

pub fn migrate_applies_all_pending_test() {
  let dir = "test/fixtures/db_migrate_all"
  let driver = common_sql_sqlite.driver()
  with_migration_dir(
    dir,
    [
      #(
        "001_create_users.sql",
        "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)",
      ),
      #("001_create_users_down.sql", "DROP TABLE users"),
      #("002_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT"),
      #("002_add_email_down.sql", "SELECT 1"),
    ],
    fn() {
      use conn <- sql.with_connection(driver, ":memory:")
      let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: dir)
      let assert Ok(s) = gorrion.status(driver:, conn:, migrations_dir: dir)
      list.length(s.applied) |> should.equal(2)
      list.length(s.pending) |> should.equal(0)
      Ok(Nil)
    },
  )
}

pub fn migrate_is_idempotent_test() {
  let dir = "test/fixtures/db_idempotent"
  let driver = common_sql_sqlite.driver()
  with_migration_dir(
    dir,
    [
      #("001_create_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY)"),
    ],
    fn() {
      use conn <- sql.with_connection(driver, ":memory:")
      let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: dir)
      // Second call should succeed finding no pending migrations
      let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: dir)
      let assert Ok(s) = gorrion.status(driver:, conn:, migrations_dir: dir)
      list.length(s.applied) |> should.equal(1)
      list.length(s.pending) |> should.equal(0)
      Ok(Nil)
    },
  )
}

pub fn rollback_reverts_last_migration_test() {
  let dir = "test/fixtures/db_rollback"
  let driver = common_sql_sqlite.driver()
  with_migration_dir(
    dir,
    [
      #("001_create_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY)"),
      #("001_create_users_down.sql", "DROP TABLE users"),
      #("002_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT"),
      #("002_add_email_down.sql", "SELECT 1"),
    ],
    fn() {
      use conn <- sql.with_connection(driver, ":memory:")
      let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: dir)
      let assert Ok(_) = gorrion.rollback(driver:, conn:, migrations_dir: dir)
      let assert Ok(s) = gorrion.status(driver:, conn:, migrations_dir: dir)
      list.length(s.applied) |> should.equal(1)
      list.length(s.pending) |> should.equal(1)
      // The remaining applied one should be version 1
      let assert Ok(applied) = list.first(s.applied)
      applied.version |> should.equal(1)
      Ok(Nil)
    },
  )
}

pub fn rollback_to_version_test() {
  let dir = "test/fixtures/db_rollback_to"
  let driver = common_sql_sqlite.driver()
  with_migration_dir(
    dir,
    [
      #("001_create_a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY)"),
      #("001_create_a_down.sql", "DROP TABLE a"),
      #("002_create_b.sql", "CREATE TABLE b (id INTEGER PRIMARY KEY)"),
      #("002_create_b_down.sql", "DROP TABLE b"),
      #("003_create_c.sql", "CREATE TABLE c (id INTEGER PRIMARY KEY)"),
      #("003_create_c_down.sql", "DROP TABLE c"),
    ],
    fn() {
      use conn <- sql.with_connection(driver, ":memory:")
      let assert Ok(_) = gorrion.migrate(driver:, conn:, migrations_dir: dir)
      // Rollback to version 1: should revert 3 and 2, leaving only 1
      let assert Ok(_) =
        gorrion.rollback_to(
          driver:,
          conn:,
          migrations_dir: dir,
          target_version: 1,
        )
      let assert Ok(s) = gorrion.status(driver:, conn:, migrations_dir: dir)
      list.length(s.applied) |> should.equal(1)
      list.length(s.pending) |> should.equal(2)
      let assert Ok(applied) = list.first(s.applied)
      applied.version |> should.equal(1)
      Ok(Nil)
    },
  )
}

pub fn status_shows_all_pending_on_fresh_db_test() {
  let dir = "test/fixtures/db_status_fresh"
  let driver = common_sql_sqlite.driver()
  with_migration_dir(
    dir,
    [
      #("001_create_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY)"),
      #("002_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT"),
    ],
    fn() {
      use conn <- sql.with_connection(driver, ":memory:")
      let assert Ok(s) = gorrion.status(driver:, conn:, migrations_dir: dir)
      list.length(s.applied) |> should.equal(0)
      list.length(s.pending) |> should.equal(2)
      Ok(Nil)
    },
  )
}
