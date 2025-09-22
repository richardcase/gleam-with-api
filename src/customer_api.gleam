import gleam/io
import gleam/result
import gleam/option.{Some, None}
import gleam/int
import customer
import customer_actor
import database

pub fn main() {
  io.println("🚀 Customer API - Gleam OTP Application")
  io.println("=====================================")
  io.println("")
  
  // Initialize the customer service
  case customer_actor.init() {
    Ok(service) -> {
      io.println("✅ Customer service initialized")
      io.println("✅ In-memory database ready")
      io.println("")
      
      // Demonstrate CRUD operations
      demo_crud_operations(service)
    }
    Error(error) -> {
      io.println("❌ Failed to initialize customer service:")
      io.debug(error)
    }
  }
}

fn demo_crud_operations(service: customer_actor.CustomerService) {
  io.println("📊 Demonstrating CRUD Operations")
  io.println("---------------------------------")
  
  // Create customers
  io.println("Creating customers...")
  let customer1 = customer.new("John Doe", "john@example.com")
  let customer2 = customer.new("Jane Smith", "jane@example.com")
  let customer3 = customer.create(None, "Bob Johnson", "bob@example.com", Some("555-1234"), Some("123 Main St"))
  
  case customer_actor.create_customer(service, customer1) {
    Ok(#(created1, service)) -> {
      io.println("✅ Created customer: " <> customer.to_string(created1))
      
      case customer_actor.create_customer(service, customer2) {
        Ok(#(created2, service)) -> {
          io.println("✅ Created customer: " <> customer.to_string(created2))
          
          case customer_actor.create_customer(service, customer3) {
            Ok(#(created3, service)) -> {
              io.println("✅ Created customer: " <> customer.to_string(created3))
              
              continue_demo(service, created1, created2, created3)
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

fn continue_demo(service: customer_actor.CustomerService, customer1: customer.Customer, customer2: customer.Customer, customer3: customer.Customer) {
  io.println("")
  io.println("📋 Listing all customers...")
  case customer_actor.list_customers(service) {
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
  io.println("🔍 Getting customer by ID...")
  case customer1.id {
    Some(id) -> {
      case customer_actor.get_customer(service, id) {
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
  io.println("✏️  Updating customer...")
  case customer2.id {
    Some(id) -> {
      let updated_customer = customer.update_phone(customer2, Some("555-9999"))
      case customer_actor.update_customer(service, id, updated_customer) {
        Ok(#(updated, service)) -> {
          io.println("✅ Updated customer: " <> customer.to_string(updated))
          
          final_demo(service, customer3)
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

fn final_demo(service: customer_actor.CustomerService, customer3: customer.Customer) {
  io.println("")
  io.println("🗑️  Deleting customer...")
  case customer3.id {
    Some(id) -> {
      case customer_actor.delete_customer(service, id) {
        Ok(service) -> {
          io.println("✅ Deleted customer with ID: " <> int.to_string(id))
          
          io.println("")
          io.println("📋 Final customer list:")
          case customer_actor.list_customers(service) {
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
  io.println("  • Customer data model with proper types")
  io.println("  • In-memory database with CRUD operations")
  io.println("  • Customer service acting as a simplified actor")
  io.println("  • Error handling and validation")
  io.println("")
  io.println("To add full OTP actors and REST API:")
  io.println("  • Add gleam_otp dependency for proper actors")
  io.println("  • Add wisp/mist for web framework")
  io.println("  • Add sqlight for SQLite persistence")
  io.println("  • Add gleam_json for JSON serialization")
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
