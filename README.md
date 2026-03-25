<p align="center">
  <img src="assets/logo.png" alt="Gorrión" width="400"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/gorrion"><img src="https://img.shields.io/hexpm/v/gorrion.svg?style=flat-square" alt="Hex.pm version"/></a>
  <a href="https://hex.pm/packages/gorrion"><img src="https://img.shields.io/hexpm/dt/gorrion.svg?style=flat-square" alt="Hex.pm downloads"/></a>
  <a href="https://hex.pm/packages/gorrion"><img src="http://img.shields.io/hexpm/l/gorrion.svg?style=flat" alt="License"/></a>
</p>

Ecto-like database migration library for Gleam + PostgreSQL.

Reads plain `.sql` files from a directory, tracks applied migrations in a `_schema_migrations` table, and supports forward migration and rollback.

## Installation

Add gorrion as a path dependency in your `gleam.toml`:

```toml
[dependencies]
gorrion = { path = "../gorrion" }
```

## Migration file convention

Place your SQL files in a `migrations/` directory (outside `src/` to avoid squirrel conflicts):

```
your_project/
  migrations/
    001_create_users.sql          # up migration (required)
    001_create_users_down.sql     # rollback (optional)
    002_add_email_to_users.sql
    003_create_orders.sql
    003_create_orders_down.sql
```

- **Up**: `{NNN}_{name}.sql` — the migration SQL to apply
- **Down**: `{NNN}_{name}_down.sql` — optional rollback SQL. If missing, rollback will only remove the tracking record without running any SQL.

The version number `NNN` can be any integer (e.g., `001`, `042`, `20240101`). Migrations are applied in version order.

## Usage

```gleam
import gorrion
import gorrion/types
import pog

pub fn main() {
  // ... set up your pog connection ...

  // Run all pending migrations
  case gorrion.migrate(db: db, migrations_dir: "migrations") {
    Ok(Nil) -> io.println("Done")
    Error(types.MigrationFailed(version:, name:, reason:)) ->
      io.println("Migration " <> int.to_string(version) <> " failed: " <> reason)
    Error(types.FileError(reason)) ->
      io.println("File error: " <> reason)
    Error(types.QueryError(reason)) ->
      io.println("Query error: " <> reason)
  }
}
```

## API

### `gorrion.migrate(db:, migrations_dir:)`

Runs all pending migrations in version order. Skips migrations already recorded in `_schema_migrations`.

### `gorrion.rollback(db:, migrations_dir:)`

Rolls back the most recently applied migration. Executes the `_down.sql` file if it exists, otherwise just removes the tracking record.

### `gorrion.rollback_to(db:, migrations_dir:, target_version:)`

Rolls back all migrations above `target_version` in reverse order.

### `gorrion.status(db:, migrations_dir:)`

Returns a `MigrationStatus` with lists of applied and pending migrations:

```gleam
case gorrion.status(db: db, migrations_dir: "migrations") {
  Ok(status) -> {
    io.println("Applied: " <> int.to_string(list.length(status.applied)))
    io.println("Pending: " <> int.to_string(list.length(status.pending)))
  }
  Error(_) -> io.println("Could not read status")
}
```

## Types

```gleam
// A migration loaded from disk
type Migration {
  Migration(version: Int, name: String, up: String, down: String)
}

// A migration that has been applied (from _schema_migrations)
type AppliedMigration {
  AppliedMigration(version: Int, name: String, applied_at: String)
}

// Status report
type MigrationStatus {
  MigrationStatus(applied: List(AppliedMigration), pending: List(Migration))
}

// Error types
type MigrationError {
  QueryError(String)
  MigrationFailed(version: Int, name: String, reason: String)
  RollbackFailed(version: Int, name: String, reason: String)
  NoMigrationsToRollback
  FileError(String)
}
```

## How it works

1. Scans the migrations directory for `*.sql` files (excluding `*_down.sql`)
2. Creates `_schema_migrations` table if it doesn't exist
3. Compares file versions against recorded versions
4. Applies pending migrations in order, recording each in `_schema_migrations`

The `_schema_migrations` table:

```sql
CREATE TABLE _schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```
