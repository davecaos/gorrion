//// Loads migration SQL files from disk.
//// Convention: {NNN}_{name}.sql (up) / {NNN}_{name}_down.sql (optional rollback)

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gorrion/types.{type Migration, type MigrationError, FileError, Migration}
import simplifile

/// Load all migrations from .sql files in the given directory.
/// Scans for *.sql files (excluding *_down.sql), and optionally pairs
/// each with a *_down.sql companion. If no down file exists, down = "".
pub fn load_migrations(
  directory: String,
) -> Result(List(Migration), MigrationError) {
  case simplifile.read_directory(directory) {
    Error(e) ->
      Error(FileError(
        "Cannot read migrations directory '"
        <> directory
        <> "': "
        <> string.inspect(e),
      ))
    Ok(files) -> {
      let up_files =
        files
        |> list.filter(fn(f) {
          string.ends_with(f, ".sql")
          && !string.ends_with(f, "_down.sql")
        })
        |> list.sort(string.compare)

      up_files
      |> list.try_map(fn(f) { parse_migration(directory, f) })
      |> result.map(fn(migrations) {
        list.sort(migrations, fn(a, b) { int.compare(a.version, b.version) })
      })
    }
  }
}

fn parse_migration(
  directory: String,
  filename: String,
) -> Result(Migration, MigrationError) {
  let base = string.drop_end(filename, string.length(".sql"))
  let down_filename = base <> "_down.sql"

  case string.split_once(base, "_") {
    Error(_) ->
      Error(FileError("Invalid migration filename: " <> filename))
    Ok(#(version_str, name)) -> {
      case int.parse(version_str) {
        Error(_) ->
          Error(FileError(
            "Invalid version number in filename: " <> filename,
          ))
        Ok(version) -> {
          let up_path = directory <> "/" <> filename
          let down_path = directory <> "/" <> down_filename

          case simplifile.read(up_path) {
            Error(e) ->
              Error(FileError(
                "Cannot read " <> up_path <> ": " <> string.inspect(e),
              ))
            Ok(up_sql) -> {
              let down_sql = case simplifile.read(down_path) {
                Ok(sql) -> sql
                Error(_) -> ""
              }
              Ok(Migration(version:, name:, up: up_sql, down: down_sql))
            }
          }
        }
      }
    }
  }
}
