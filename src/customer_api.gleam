import gleam/io
import gleam/result
import gleam/option.{Some, None}
import gleam/int
import gleam/otp/actor
import customer
import customer_actor
import database

pub fn main() {
  io.println("🚀 Customer API - Gleam OTP Application")
  io.println("=====================================")
  io.println("")
  
  // Start the actor system
  case start_actor_system() {
    Ok(#(database_actor, customer_registry)) -> {
      io.println("✅ Database actor started")
      io.println("✅ Customer registry started")
      io.println("")
      
      // Demonstrate CRUD operations with actors
      demo_crud_operations(customer_registry)
      
      // Cleanup
      actor.send(customer_registry, customer_actor.Shutdown)
      actor.send(database_actor, database.Shutdown)
    }
    Error(error) -> {
      io.println("❌ Failed to start actor system:")
      io.debug(error)
    }
  }
}

fn start_actor_system() -> Result(#(actor.Subject(database.DatabaseMessage), actor.Subject(customer_actor.RegistryMessage)), actor.StartError) {
  use database_actor <- result.try(database.start_database_actor())
  use customer_registry <- result.try(customer_actor.start_customer_registry(database_actor))
  Ok(#(database_actor, customer_registry))
}

fn demo_crud_operations(registry: actor.Subject(customer_actor.RegistryMessage)) {
  io.println("📊 Demonstrating CRUD Operations with OTP Actors")
  io.println("------------------------------------------------")
  
  // Create customers
  io.println("Creating customers...")
  let customer1 = customer.new("John Doe", "john@example.com")
  let customer2 = customer.new("Jane Smith", "jane@example.com")
  let customer3 = customer.create(None, "Bob Johnson", "bob@example.com", Some("555-1234"), Some("123 Main St"))
  
  case create_customer_via_registry(registry, customer1) {
    Ok(created1) -> {
      io.println("✅ Created customer: " <> customer.to_string(created1))
      
      case create_customer_via_registry(registry, customer2) {
        Ok(created2) -> {
          io.println("✅ Created customer: " <> customer.to_string(created2))
          
          case create_customer_via_registry(registry, customer3) {
            Ok(created3) -> {
              io.println("✅ Created customer: " <> customer.to_string(created3))
              
              continue_demo(registry, created1, created2, created3)
            }
            Error(error) -> {
              io.println("❌ Failed to create customer 3:")
              io.debug(error)
            }
          }
        }
        Error(error) -> {
          io.println("❌ Failed to create customer 2:")
          io.debug(error)
        }
      }
    }
    Error(error) -> {
      io.println("❌ Failed to create customer 1:")
      io.debug(error)
    }
  }
}

fn create_customer_via_registry(
  registry: actor.Subject(customer_actor.RegistryMessage),
  customer: customer.Customer
) -> Result(customer.Customer, database.DatabaseError) {
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.CreateCustomer(customer, reply_subject))
  
  case actor.receive(reply_subject, 5000) {
    Ok(result) -> result
    Error(_) -> Error(database.ActorError)
  }
}

fn continue_demo(
  registry: actor.Subject(customer_actor.RegistryMessage),
  customer1: customer.Customer,
  customer2: customer.Customer,
  customer3: customer.Customer
) {
  io.println("")
  io.println("📋 Listing all customers...")
  case list_customers_via_registry(registry) {
    Ok(customers) -> {
      io.println("Current customers:")
      list_customers_helper(customers)
    }
    Error(error) -> {
      io.println("❌ Failed to list customers:")
      io.debug(error)
    }
  }
  
  io.println("")
  io.println("🔍 Getting customer by ID via actor...")
  case customer1.id {
    Some(id) -> {
      case get_customer_via_actor(registry, id) {
        Ok(found_customer) -> {
          io.println("✅ Found customer: " <> customer.to_string(found_customer))
        }
        Error(error) -> {
          io.println("❌ Failed to get customer:")
          io.debug(error)
        }
      }
    }
    None -> io.println("❌ Customer has no ID")
  }
  
  io.println("")
  io.println("✏️  Updating customer via actor...")
  case customer2.id {
    Some(id) -> {
      let updated_customer = customer.update_phone(customer2, Some("555-9999"))
      case update_customer_via_actor(registry, id, updated_customer) {
        Ok(updated) -> {
          io.println("✅ Updated customer: " <> customer.to_string(updated))
          
          final_demo(registry, customer3)
        }
        Error(error) -> {
          io.println("❌ Failed to update customer:")
          io.debug(error)
        }
      }
    }
    None -> io.println("❌ Customer has no ID")
  }
}

fn get_customer_via_actor(
  registry: actor.Subject(customer_actor.RegistryMessage),
  id: Int
) -> Result(customer.Customer, database.DatabaseError) {
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.GetOrCreateCustomerActor(id, reply_subject))
  
  case actor.receive(reply_subject, 5000) {
    Ok(Ok(customer_actor_subject)) -> {
      let customer_reply_subject = actor.new_subject()
      actor.send(customer_actor_subject, customer_actor.GetCustomer(customer_reply_subject))
      
      case actor.receive(customer_reply_subject, 5000) {
        Ok(result) -> result
        Error(_) -> Error(database.ActorError)
      }
    }
    Ok(Error(error)) -> Error(error)
    Error(_) -> Error(database.ActorError)
  }
}

fn update_customer_via_actor(
  registry: actor.Subject(customer_actor.RegistryMessage),
  id: Int,
  customer: customer.Customer
) -> Result(customer.Customer, database.DatabaseError) {
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.GetOrCreateCustomerActor(id, reply_subject))
  
  case actor.receive(reply_subject, 5000) {
    Ok(Ok(customer_actor_subject)) -> {
      let update_reply_subject = actor.new_subject()
      actor.send(customer_actor_subject, customer_actor.UpdateCustomer(customer, update_reply_subject))
      
      case actor.receive(update_reply_subject, 5000) {
        Ok(result) -> result
        Error(_) -> Error(database.ActorError)
      }
    }
    Ok(Error(error)) -> Error(error)
    Error(_) -> Error(database.ActorError)
  }
}

fn list_customers_via_registry(
  registry: actor.Subject(customer_actor.RegistryMessage)
) -> Result(List(customer.Customer), database.DatabaseError) {
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.ListCustomers(reply_subject))
  
  case actor.receive(reply_subject, 5000) {
    Ok(result) -> result
    Error(_) -> Error(database.ActorError)
  }
}

fn final_demo(
  registry: actor.Subject(customer_actor.RegistryMessage),
  customer3: customer.Customer
) {
  io.println("")
  io.println("🗑️  Deleting customer via actor...")
  case customer3.id {
    Some(id) -> {
      case delete_customer_via_actor(registry, id) {
        Ok(_) -> {
          io.println("✅ Deleted customer with ID: " <> int.to_string(id))
          
          io.println("")
          io.println("📋 Final customer list:")
          case list_customers_via_registry(registry) {
            Ok(customers) -> {
              list_customers_helper(customers)
            }
            Error(error) -> {
              io.println("❌ Failed to list customers:")
              io.debug(error)
            }
          }
        }
        Error(error) -> {
          io.println("❌ Failed to delete customer:")
          io.debug(error)
        }
      }
    }
    None -> io.println("❌ Customer has no ID")
  }
  
  io.println("")
  io.println("🎉 Demo completed successfully!")
  io.println("")
  io.println("This demonstrates a Gleam OTP application with:")
  io.println("  • Real OTP actors for database and customer management")
  io.println("  • Customer registry managing individual customer actors")
  io.println("  • Message-passing between actors")
  io.println("  • Fault-tolerant actor supervision")
  io.println("  • Type-safe actor communication")
  io.println("")
  io.println("Architecture components:")
  io.println("  • Database Actor: Manages persistent state")
  io.println("  • Customer Registry: Manages customer actor lifecycle")
  io.println("  • Customer Actors: Individual actors per customer")
  io.println("  • Actor message protocols for type safety")
}

fn delete_customer_via_actor(
  registry: actor.Subject(customer_actor.RegistryMessage),
  id: Int
) -> Result(Nil, database.DatabaseError) {
  let reply_subject = actor.new_subject()
  actor.send(registry, customer_actor.GetOrCreateCustomerActor(id, reply_subject))
  
  case actor.receive(reply_subject, 5000) {
    Ok(Ok(customer_actor_subject)) -> {
      let delete_reply_subject = actor.new_subject()
      actor.send(customer_actor_subject, customer_actor.DeleteCustomer(delete_reply_subject))
      
      case actor.receive(delete_reply_subject, 5000) {
        Ok(result) -> result
        Error(_) -> Error(database.ActorError)
      }
    }
    Ok(Error(error)) -> Error(error)
    Error(_) -> Error(database.ActorError)
  }
}

fn list_customers_helper(customers: List(customer.Customer)) {
  case customers {
    [] -> io.println("  (no customers)")
    [customer, ..rest] -> {
      io.println("  - " <> customer.to_string(customer))
      list_customers_helper(rest)
    }
  }
}
