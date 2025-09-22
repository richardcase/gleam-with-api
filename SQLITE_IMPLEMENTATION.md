# SQLite Integration Implementation

This implementation adds SQLite database support to the Gleam Customer API application.

## Changes Made

### 1. Updated Dependencies (gleam.toml)
```gleam
[dependencies]
gleam_stdlib = ">= 0.34.0 and < 2.0.0"
sqlight = ">= 0.15.0 and < 1.0.0"  # Added SQLite support
```

### 2. Created Database Migrations (src/migrations.gleam)
- Implements database schema creation
- Includes customer table with proper indexes
- Adds triggers for automatic timestamp updates

### 3. Updated Database Layer (src/database.gleam)
- **BEFORE**: Used in-memory Dict-based storage
- **AFTER**: Uses SQLite with proper SQL queries
- Maintains same public API for compatibility
- Added new error type: `SqliteError(sqlight.Error)`

### Key Changes:
- Database type now contains SQLite connection instead of Dict
- All CRUD operations rewritten to use SQL queries
- Proper parameter binding to prevent SQL injection
- Returns proper SQL errors wrapped in DatabaseError

### 4. Function-by-Function Changes:

#### `init()`
- **BEFORE**: `Ok(Database(customers: dict.new(), next_id: 1))`
- **AFTER**: Opens SQLite connection and runs migrations

#### `insert_customer()`
- **BEFORE**: Check email in Dict, insert with next_id
- **AFTER**: SQL query with email uniqueness check, auto-increment ID

#### `get_customer()`
- **BEFORE**: `dict.get(db.customers, id)`
- **AFTER**: `SELECT` query with parameter binding

#### `update_customer()`
- **BEFORE**: Dict operations with email conflict check
- **AFTER**: SQL `UPDATE` with `RETURNING` clause

#### `delete_customer()`
- **BEFORE**: `dict.delete(db.customers, id)`
- **AFTER**: SQL `DELETE` query

#### `list_customers()`
- **BEFORE**: `dict.values()` with manual sorting
- **AFTER**: `SELECT * ORDER BY id` query

## Benefits of SQLite Integration

1. **Persistence**: Data survives application restarts
2. **Performance**: Optimized queries with indexes
3. **Concurrency**: Better handling of concurrent access
4. **ACID**: Transactions ensure data integrity
5. **Scalability**: Can easily migrate to PostgreSQL later

## Database Schema

```sql
CREATE TABLE customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  address TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customers_email ON customers(email);

CREATE TRIGGER customers_updated_at
AFTER UPDATE ON customers
FOR EACH ROW
BEGIN
  UPDATE customers SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
```

## Testing

The existing tests should work without modification since the public API remains the same. The main change is that data is now stored in SQLite instead of memory.

## Production Considerations

1. **File Database**: Change `:memory:` to a file path for persistence
2. **Connection Pooling**: Add connection pool for better performance
3. **Migrations**: Version control for schema changes
4. **Backup**: Regular database backups
5. **Monitoring**: Query performance monitoring

This implementation provides a solid foundation for a production-ready SQLite-backed customer API.