import gleeunit
import gleeunit/should
import customer
import customer_actor
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

// Test customer service operations
pub fn customer_service_test() {
  // Initialize service
  let assert Ok(service) = customer_actor.init()
  
  // Create a customer
  let customer = customer.new("Jane Smith", "jane@example.com")
  let assert Ok(#(created_customer, service)) = customer_actor.create_customer(service, customer)
  
  created_customer.name
  |> should.equal("Jane Smith")
  
  created_customer.email
  |> should.equal("jane@example.com")
  
  // Verify ID was assigned
  case created_customer.id {
    Some(id) -> {
      // Get customer by ID
      let assert Ok(found_customer) = customer_actor.get_customer(service, id)
      found_customer.name
      |> should.equal("Jane Smith")
    }
    None -> panic as "Customer should have been assigned an ID"
  }
}
