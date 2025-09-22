import gleam/result
import gleam/option.{type Option}
import customer.{type Customer}
import database.{type Database, type DatabaseError}

/// Customer service state containing the database
pub type CustomerService {
  CustomerService(database: Database)
}

/// Initialize customer service
pub fn init() -> Result(CustomerService, DatabaseError) {
  use db <- result.try(database.init())
  Ok(CustomerService(database: db))
}

/// Create a customer
pub fn create_customer(
  service: CustomerService, 
  customer: Customer
) -> Result(#(Customer, CustomerService), DatabaseError) {
  use #(new_customer, new_db) <- result.try(
    database.insert_customer(service.database, customer)
  )
  Ok(#(new_customer, CustomerService(database: new_db)))
}

/// Get a customer by ID
pub fn get_customer(
  service: CustomerService, 
  id: Int
) -> Result(Customer, DatabaseError) {
  database.get_customer(service.database, id)
}

/// Update a customer
pub fn update_customer(
  service: CustomerService, 
  id: Int,
  customer: Customer
) -> Result(#(Customer, CustomerService), DatabaseError) {
  use #(updated_customer, new_db) <- result.try(
    database.update_customer(service.database, id, customer)
  )
  Ok(#(updated_customer, CustomerService(database: new_db)))
}

/// Delete a customer
pub fn delete_customer(
  service: CustomerService, 
  id: Int
) -> Result(CustomerService, DatabaseError) {
  use new_db <- result.try(database.delete_customer(service.database, id))
  Ok(CustomerService(database: new_db))
}

/// List all customers
pub fn list_customers(
  service: CustomerService
) -> Result(List(Customer), DatabaseError) {
  database.list_customers(service.database)
}