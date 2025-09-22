import sqlight
import gleam/list

/// Run database migrations to set up the schema
pub fn run_migrations(db: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  let migrations = [
    "CREATE TABLE IF NOT EXISTS customers (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       email TEXT NOT NULL UNIQUE,
       phone TEXT,
       address TEXT,
       created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
       updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
     )",
    "CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email)",
    "CREATE TRIGGER IF NOT EXISTS customers_updated_at
     AFTER UPDATE ON customers
     FOR EACH ROW
     BEGIN
       UPDATE customers SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
     END"
  ]
  
  list.try_each(migrations, fn(sql) {
    sqlight.exec(sql, db)
  })
}