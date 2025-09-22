import gleam/result
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import customer.{type Customer}
import database.{type Database, type DatabaseError}
import distributed_supervisor.{type DistributedSupervisorMessage, StartCustomerActor, GetCustomerActor}

/// Customer service state containing the database and distributed supervisor
pub type CustomerService {
  CustomerService(
    database: Database,
    distributed_supervisor: Subject(DistributedSupervisorMessage)
  )
}

/// Initialize customer service with distributed supervisor
pub fn init_distributed(distributed_supervisor: Subject(DistributedSupervisorMessage)) -> Result(CustomerService, DatabaseError) {
  use db <- result.try(database.init())
  Ok(CustomerService(database: db, distributed_supervisor: distributed_supervisor))
}

/// Customer service state containing the database (legacy)
pub type LegacyCustomerService {
  LegacyCustomerService(database: Database)
}

/// Initialize customer service (legacy)
pub fn init() -> Result(LegacyCustomerService, DatabaseError) {
  use db <- result.try(database.init())
  Ok(LegacyCustomerService(database: db))
}

/// Create a customer using distributed approach
pub fn create_customer_distributed(
  service: CustomerService, 
  customer: Customer
) -> Result(#(Customer, CustomerService), DatabaseError) {
  use #(new_customer, new_db) <- result.try(
    database.insert_customer(service.database, customer)
  )
  
  // Start actor for the new customer using distributed supervisor
  case new_customer.id {
    Some(customer_id) -> {
      let _ = actor.call(service.distributed_supervisor, StartCustomerActor(customer_id, _), 5000)
      Ok(#(new_customer, CustomerService(database: new_db, distributed_supervisor: service.distributed_supervisor)))
    }
    None -> {
      Ok(#(new_customer, CustomerService(database: new_db, distributed_supervisor: service.distributed_supervisor)))
    }
  }
}

/// Create a customer
pub fn create_customer(
  service: LegacyCustomerService, 
  customer: Customer
) -> Result(#(Customer, LegacyCustomerService), DatabaseError) {
  use #(new_customer, new_db) <- result.try(
    database.insert_customer(service.database, customer)
  )
  Ok(#(new_customer, LegacyCustomerService(database: new_db)))
}

/// Get a customer by ID
pub fn get_customer(
  service: LegacyCustomerService, 
  id: Int
) -> Result(Customer, DatabaseError) {
  database.get_customer(service.database, id)
}

/// Update a customer
pub fn update_customer(
  service: LegacyCustomerService, 
  id: Int,
  customer: Customer
) -> Result(#(Customer, LegacyCustomerService), DatabaseError) {
  use #(updated_customer, new_db) <- result.try(
    database.update_customer(service.database, id, customer)
  )
  Ok(#(updated_customer, LegacyCustomerService(database: new_db)))
}

/// Delete a customer
pub fn delete_customer(
  service: LegacyCustomerService, 
  id: Int
) -> Result(LegacyCustomerService, DatabaseError) {
  use new_db <- result.try(database.delete_customer(service.database, id))
  Ok(LegacyCustomerService(database: new_db))
}

/// List all customers
pub fn list_customers(
  service: LegacyCustomerService
) -> Result(List(Customer), DatabaseError) {
  database.list_customers(service.database)
}