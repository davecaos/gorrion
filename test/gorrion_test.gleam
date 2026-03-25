import gleam/list
import gleeunit
import gleeunit/should
import gorrion/loader
import gorrion/types
import simplifile

pub fn main() {
  gleeunit.main()
}

// -- Loader tests (no DB required) --

pub fn load_migrations_from_directory_test() {
  let dir = "test/fixtures/migrations_basic"
  let _ = setup_fixture_dir(dir)

  // Create two migration files
  let assert Ok(_) =
    simplifile.write(dir <> "/001_create_users.sql", "CREATE TABLE users (id SERIAL)")
  let assert Ok(_) =
    simplifile.write(dir <> "/002_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT")

  let assert Ok(migrations) = loader.load_migrations(dir)

  list.length(migrations) |> should.equal(2)

  let assert Ok(first) = list.first(migrations)
  first.version |> should.equal(1)
  first.name |> should.equal("create_users")
  first.up |> should.equal("CREATE TABLE users (id SERIAL)")
  first.down |> should.equal("")

  let assert Ok(second) = list.last(migrations)
  second.version |> should.equal(2)
  second.name |> should.equal("add_email")

  let _ = cleanup_fixture_dir(dir)
}

pub fn load_migrations_with_down_file_test() {
  let dir = "test/fixtures/migrations_down"
  let _ = setup_fixture_dir(dir)

  let assert Ok(_) =
    simplifile.write(dir <> "/001_create_users.sql", "CREATE TABLE users (id SERIAL)")
  let assert Ok(_) =
    simplifile.write(dir <> "/001_create_users_down.sql", "DROP TABLE users")

  let assert Ok(migrations) = loader.load_migrations(dir)

  list.length(migrations) |> should.equal(1)

  let assert Ok(first) = list.first(migrations)
  first.version |> should.equal(1)
  first.down |> should.equal("DROP TABLE users")

  let _ = cleanup_fixture_dir(dir)
}

pub fn load_migrations_ignores_down_files_test() {
  let dir = "test/fixtures/migrations_ignore"
  let _ = setup_fixture_dir(dir)

  let assert Ok(_) =
    simplifile.write(dir <> "/001_create_users.sql", "CREATE TABLE users (id SERIAL)")
  let assert Ok(_) =
    simplifile.write(dir <> "/001_create_users_down.sql", "DROP TABLE users")
  let assert Ok(_) =
    simplifile.write(dir <> "/002_add_email.sql", "ALTER TABLE users ADD COLUMN email TEXT")

  let assert Ok(migrations) = loader.load_migrations(dir)

  // Should only find 2 migrations (down files are not counted as separate migrations)
  list.length(migrations) |> should.equal(2)

  let _ = cleanup_fixture_dir(dir)
}

pub fn load_migrations_sorted_by_version_test() {
  let dir = "test/fixtures/migrations_sort"
  let _ = setup_fixture_dir(dir)

  let assert Ok(_) =
    simplifile.write(dir <> "/010_third.sql", "SELECT 3")
  let assert Ok(_) =
    simplifile.write(dir <> "/001_first.sql", "SELECT 1")
  let assert Ok(_) =
    simplifile.write(dir <> "/005_second.sql", "SELECT 2")

  let assert Ok(migrations) = loader.load_migrations(dir)

  let versions = list.map(migrations, fn(m) { m.version })
  versions |> should.equal([1, 5, 10])

  let _ = cleanup_fixture_dir(dir)
}

pub fn load_migrations_empty_directory_test() {
  let dir = "test/fixtures/migrations_empty"
  let _ = setup_fixture_dir(dir)

  let assert Ok(migrations) = loader.load_migrations(dir)
  list.length(migrations) |> should.equal(0)

  let _ = cleanup_fixture_dir(dir)
}

pub fn load_migrations_missing_directory_test() {
  let result = loader.load_migrations("test/fixtures/nonexistent_dir")

  case result {
    Error(types.FileError(_)) -> should.be_true(True)
    _ -> should.fail()
  }
}

fn setup_fixture_dir(dir: String) {
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
}

fn cleanup_fixture_dir(dir: String) {
  let _ = simplifile.delete(dir)
}
