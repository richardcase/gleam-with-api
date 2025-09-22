import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/int
import gleam/string
import sqlight
import customer.{type Customer}
import migrations

/// Database state type using SQLite connection
pub type Database {
  Database(connection: sqlight.Connection)
}

/// Database errors
pub type DatabaseError {
  NotFound
  InvalidData
  EmailExists
  SqliteError(sqlight.Error)
}

/// Initialize the database with SQLite
pub fn init() -> Result(Database, DatabaseError) {
  case sqlight.open(":memory:") {
    Ok(connection) -> {
      case migrations.run_migrations(connection) {
        Ok(_) -> Ok(Database(connection: connection))
        Error(error) -> Error(SqliteError(error))
      }
    }
    Error(error) -> Error(SqliteError(error))
  }
}

/// Insert a new customer
pub fn insert_customer(db: Database, customer: Customer) -> Result(#(Customer, Database), DatabaseError) {
  // Check if email already exists
  let email_check_sql = "SELECT COUNT(*) FROM customers WHERE email = ?"
  case sqlight.query(email_check_sql, db.connection, [sqlight.text(customer.email)], int()) {
    Ok([count]) -> {
      case count > 0 {
        True -> Error(EmailExists)
        False -> {
          // Insert the customer
          let insert_sql = "INSERT INTO customers (name, email, phone, address) VALUES (?, ?, ?, ?) RETURNING id, name, email, phone, address"
          let phone_param = case customer.phone {
            Some(phone) -> sqlight.text(phone)
            None -> sqlight.null()
          }
          let address_param = case customer.address {
            Some(address) -> sqlight.text(address)
            None -> sqlight.null()
          }
          
          case sqlight.query(insert_sql, db.connection, [
            sqlight.text(customer.name),
            sqlight.text(customer.email),
            phone_param,
            address_param
          ], row_decoder()) {
            Ok([new_customer]) -> Ok(#(new_customer, db))
            Ok(_) -> Error(InvalidData)
            Error(error) -> Error(SqliteError(error))
          }
        }
      }
    }
    Ok(_) -> Error(InvalidData)
    Error(error) -> Error(SqliteError(error))
  }
}

/// Row decoder for customer records
fn row_decoder() -> sqlight.Decoder(Customer) {
  sqlight.decode5(
    fn(id, name, email, phone, address) {
      Customer(
        id: Some(id),
        name: name,
        email: email,
        phone: phone,
        address: address
      )
    },
    sqlight.int(),
    sqlight.text(),
    sqlight.text(),
    sqlight.optional(sqlight.text()),
    sqlight.optional(sqlight.text())
  )
}

/// Decoder for counting rows
fn int() -> sqlight.Decoder(Int) {
  sqlight.int()
}

/// Get customer by ID
pub fn get_customer(db: Database, id: Int) -> Result(Customer, DatabaseError) {
  let sql = "SELECT id, name, email, phone, address FROM customers WHERE id = ?"
  case sqlight.query(sql, db.connection, [sqlight.int(id)], row_decoder()) {
    Ok([customer]) -> Ok(customer)
    Ok([]) -> Error(NotFound)
    Ok(_) -> Error(InvalidData)
    Error(error) -> Error(SqliteError(error))
  }
}

/// Update customer
pub fn update_customer(db: Database, id: Int, customer: Customer) -> Result(#(Customer, Database), DatabaseError) {
  // First check if customer exists
  case get_customer(db, id) {
    Ok(_existing) -> {
      // Check if email already exists for other customers
      let email_check_sql = "SELECT COUNT(*) FROM customers WHERE email = ? AND id != ?"
      case sqlight.query(email_check_sql, db.connection, [sqlight.text(customer.email), sqlight.int(id)], int()) {
        Ok([count]) -> {
          case count > 0 {
            True -> Error(EmailExists)
            False -> {
              // Update the customer
              let update_sql = "UPDATE customers SET name = ?, email = ?, phone = ?, address = ? WHERE id = ? RETURNING id, name, email, phone, address"
              let phone_param = case customer.phone {
                Some(phone) -> sqlight.text(phone)
                None -> sqlight.null()
              }
              let address_param = case customer.address {
                Some(address) -> sqlight.text(address)
                None -> sqlight.null()
              }
              
              case sqlight.query(update_sql, db.connection, [
                sqlight.text(customer.name),
                sqlight.text(customer.email),
                phone_param,
                address_param,
                sqlight.int(id)
              ], row_decoder()) {
                Ok([updated_customer]) -> Ok(#(updated_customer, db))
                Ok(_) -> Error(InvalidData)
                Error(error) -> Error(SqliteError(error))
              }
            }
          }
        }
        Ok(_) -> Error(InvalidData)
        Error(error) -> Error(SqliteError(error))
      }
    }
    Error(error) -> Error(error)
  }
}

/// Delete customer
pub fn delete_customer(db: Database, id: Int) -> Result(Database, DatabaseError) {
  // First check if customer exists
  case get_customer(db, id) {
    Ok(_) -> {
      let delete_sql = "DELETE FROM customers WHERE id = ?"
      case sqlight.exec(delete_sql, db.connection, [sqlight.int(id)]) {
        Ok(_) -> Ok(db)
        Error(error) -> Error(SqliteError(error))
      }
    }
    Error(error) -> Error(error)
  }
}

/// List all customers
pub fn list_customers(db: Database) -> Result(List(Customer), DatabaseError) {
  let sql = "SELECT id, name, email, phone, address FROM customers ORDER BY id"
  case sqlight.query(sql, db.connection, [], row_decoder()) {
    Ok(customers) -> Ok(customers)
    Error(error) -> Error(SqliteError(error))
  }
}