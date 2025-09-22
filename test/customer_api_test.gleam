import gleeunit
import gleeunit/should
import gleam/otp/actor
import customer
import customer_actor
import database
import gleam/option.{Some, None}

pub fn main() {
  gleeunit.main()
}

// Test customer creation
pub fn customer_creation_test() {
  let customer = customer.new("John Doe", "john@example.com")
  customer.name
  |> should.equal("John Doe")
  
  customer.email
  |> should.equal("john@example.com")
  
  customer.id
  |> should.equal(None)
}

// Test database actor operations
pub fn database_actor_test() {
  // Start database actor
  let assert Ok(database_actor) = database.start_database_actor()
  
  // Create a customer
  let customer = customer.new("Jane Smith", "jane@example.com")
  let reply_subject = actor.new_subject()
  actor.send(database_actor, database.InsertCustomer(customer, reply_subject))
  
  let assert Ok(Ok(created_customer)) = actor.receive(reply_subject, 5000)
  
  created_customer.name
  |> should.equal("Jane Smith")
  
  created_customer.email
  |> should.equal("jane@example.com")
  
  // Verify ID was assigned
  case created_customer.id {
    Some(id) -> {
      // Get customer by ID
      let get_reply_subject = actor.new_subject()
      actor.send(database_actor, database.GetCustomer(id, get_reply_subject))
      
      let assert Ok(Ok(found_customer)) = actor.receive(get_reply_subject, 5000)
      found_customer.name
      |> should.equal("Jane Smith")
    }
    None -> panic as "Customer should have been assigned an ID"
  }
  
  // Cleanup
  actor.send(database_actor, database.Shutdown)
}

// Test customer registry operations
pub fn customer_registry_test() {
  // Start actors
  let assert Ok(database_actor) = database.start_database_actor()
  let assert Ok(registry) = customer_actor.start_customer_registry(database_actor)
  
  // Create a customer via registry
  let customer = customer.new("Bob Johnson", "bob@example.com")
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.CreateCustomer(customer, reply_subject))
  
  let assert Ok(Ok(created_customer)) = actor.receive(reply_subject, 5000)
  
  created_customer.name
  |> should.equal("Bob Johnson")
  
  // Verify we can get the customer actor
  case created_customer.id {
    Some(id) -> {
      let actor_reply_subject = actor.new_subject()
      actor.send(registry, customer_actor.GetOrCreateCustomerActor(id, actor_reply_subject))
      
      let assert Ok(Ok(customer_actor_subject)) = actor.receive(actor_reply_subject, 5000)
      
      // Use the customer actor to get customer data
      let customer_reply_subject = actor.new_subject()
      actor.send(customer_actor_subject, customer_actor.GetCustomer(customer_reply_subject))
      
      let assert Ok(Ok(found_customer)) = actor.receive(customer_reply_subject, 5000)
      found_customer.name
      |> should.equal("Bob Johnson")
    }
    None -> panic as "Customer should have been assigned an ID"
  }
  
  // Cleanup
  actor.send(registry, customer_actor.Shutdown)
  actor.send(database_actor, database.Shutdown)
}

// Test list customers functionality
pub fn list_customers_test() {
  // Start actors
  let assert Ok(database_actor) = database.start_database_actor()
  let assert Ok(registry) = customer_actor.start_customer_registry(database_actor)
  
  // Create multiple customers
  let customer1 = customer.new("Alice", "alice@example.com")
  let customer2 = customer.new("Charlie", "charlie@example.com")
  
  let reply_subject1 = actor.new_subject()
  actor.send(registry, customer_actor.CreateCustomer(customer1, reply_subject1))
  let assert Ok(Ok(_)) = actor.receive(reply_subject1, 5000)
  
  let reply_subject2 = actor.new_subject()
  actor.send(registry, customer_actor.CreateCustomer(customer2, reply_subject2))
  let assert Ok(Ok(_)) = actor.receive(reply_subject2, 5000)
  
  // List all customers
  let list_reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.ListCustomers(list_reply_subject))
  
  let assert Ok(Ok(customers)) = actor.receive(list_reply_subject, 5000)
  
  // Should have 2 customers
  let customer_count = list_length(customers)
  customer_count
  |> should.equal(2)
  
  // Cleanup
  actor.send(registry, customer_actor.Shutdown)
  actor.send(database_actor, database.Shutdown)
}

// Helper function to count list length
fn list_length(list) {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
