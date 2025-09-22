import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/int
import gleam/dict.{type Dict}
import gleam/order
import gleam/otp/actor
import customer.{type Customer}

/// Database state type using in-memory storage
pub type Database {
  Database(customers: Dict(Int, Customer), next_id: Int)
}

/// Database errors
pub type DatabaseError {
  NotFound
  InvalidData
  EmailExists
  ActorError
}

/// Database actor messages
pub type DatabaseMessage {
  InsertCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  GetCustomer(Int, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  UpdateCustomer(Int, Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  DeleteCustomer(Int, reply_with: actor.Subject(Result(Nil, DatabaseError)))
  ListCustomers(reply_with: actor.Subject(Result(List(Customer), DatabaseError)))
  Shutdown
}

/// Start a database actor
pub fn start_database_actor() -> Result(actor.Subject(DatabaseMessage), actor.StartError) {
  let init_db = Database(customers: dict.new(), next_id: 1)
  actor.start(init_db, handle_database_message)
}

/// Handle database actor messages
fn handle_database_message(
  message: DatabaseMessage,
  state: Database,
) -> actor.Next(DatabaseMessage, Database) {
  case message {
    InsertCustomer(customer, reply_with) -> {
      let result = insert_customer(state, customer)
      case result {
        Ok(#(new_customer, new_state)) -> {
          actor.send(reply_with, Ok(new_customer))
          actor.continue(new_state)
        }
        Error(error) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
      }
    }
    
    GetCustomer(id, reply_with) -> {
      let result = get_customer(state, id)
      actor.send(reply_with, result)
      actor.continue(state)
    }
    
    UpdateCustomer(id, customer, reply_with) -> {
      let result = update_customer(state, id, customer)
      case result {
        Ok(#(updated_customer, new_state)) -> {
          actor.send(reply_with, Ok(updated_customer))
          actor.continue(new_state)
        }
        Error(error) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
      }
    }
    
    DeleteCustomer(id, reply_with) -> {
      let result = delete_customer(state, id)
      case result {
        Ok(new_state) -> {
          actor.send(reply_with, Ok(Nil))
          actor.continue(new_state)
        }
        Error(error) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
      }
    }
    
    ListCustomers(reply_with) -> {
      let result = list_customers(state)
      actor.send(reply_with, result)
      actor.continue(state)
    }
    
    Shutdown -> {
      actor.stop(actor.Normal)
    }
  }
}

/// Database state type using in-memory storage
pub type Database {
  Database(customers: Dict(Int, Customer), next_id: Int)
}

/// Database errors
pub type DatabaseError {
  NotFound
  InvalidData
  EmailExists
}

/// Initialize the database
pub fn init() -> Result(Database, DatabaseError) {
  Ok(Database(customers: dict.new(), next_id: 1))
}

/// Insert a new customer
pub fn insert_customer(db: Database, customer: Customer) -> Result(#(Customer, Database), DatabaseError) {
  // Check if email already exists
  let email_exists = dict.fold(db.customers, False, fn(acc, _id, existing_customer) {
    acc || existing_customer.email == customer.email
  })
  
  case email_exists {
    True -> Error(EmailExists)
    False -> {
      let new_customer = Customer(..customer, id: Some(db.next_id))
      let new_customers = dict.insert(db.customers, db.next_id, new_customer)
      let new_db = Database(customers: new_customers, next_id: db.next_id + 1)
      Ok(#(new_customer, new_db))
    }
  }
}

/// Get customer by ID
pub fn get_customer(db: Database, id: Int) -> Result(Customer, DatabaseError) {
  case dict.get(db.customers, id) {
    Ok(customer) -> Ok(customer)
    Error(_) -> Error(NotFound)
  }
}

/// Update customer
pub fn update_customer(db: Database, id: Int, customer: Customer) -> Result(#(Customer, Database), DatabaseError) {
  case dict.get(db.customers, id) {
    Ok(_existing) -> {
      // Check if email already exists for other customers
      let email_exists = dict.fold(db.customers, False, fn(acc, existing_id, existing_customer) {
        case existing_id == id {
          True -> acc  // Same customer, ignore
          False -> acc || existing_customer.email == customer.email
        }
      })
      
      case email_exists {
        True -> Error(EmailExists)
        False -> {
          let updated_customer = Customer(..customer, id: Some(id))
          let new_customers = dict.insert(db.customers, id, updated_customer)
          let new_db = Database(..db, customers: new_customers)
          Ok(#(updated_customer, new_db))
        }
      }
    }
    Error(_) -> Error(NotFound)
  }
}

/// Delete customer
pub fn delete_customer(db: Database, id: Int) -> Result(Database, DatabaseError) {
  case dict.get(db.customers, id) {
    Ok(_) -> {
      let new_customers = dict.delete(db.customers, id)
      let new_db = Database(..db, customers: new_customers)
      Ok(new_db)
    }
    Error(_) -> Error(NotFound)
  }
}

/// List all customers
pub fn list_customers(db: Database) -> Result(List(Customer), DatabaseError) {
  let customers = dict.values(db.customers)
  Ok(list.sort(customers, fn(a, b) {
    case a.id, b.id {
      Some(id_a), Some(id_b) -> int.compare(id_a, id_b)
      _, _ -> order.Eq
    }
  }))
}