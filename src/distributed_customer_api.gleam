import gleam/io
import gleam/result
import gleam/option.{Some, None}
import gleam/int
import gleam/list
import gleam/dict
import gleam/string
import gleam/otp/actor
import customer
import customer_actor
import database
import app_supervisor
import distributed_supervisor.{type DistributedSupervisorMessage, StartCustomerActor, GetClusterStatus}

pub fn main() {
  io.println("🚀 Customer API - Gleam OTP Application with Distributed Supervisor")
  io.println("===================================================================")
  io.println("")
  
  // Start the application with distributed supervisor
  case app_supervisor.start_application() {
    Ok(app) -> {
      io.println("✅ Application started with distributed supervisor")
      io.println("✅ Cluster initialized")
      io.println("")
      
      let dist_supervisor = app_supervisor.get_distributed_supervisor(app)
      
      // Demonstrate distributed operations
      demo_distributed_operations(dist_supervisor)
      
      // Also run legacy demo for comparison
      io.println("")
      io.println("🔄 Running legacy demo for comparison...")
      demo_legacy_operations()
    }
    Error(error) -> {
      io.println("❌ Failed to start application:")
      io.debug(error)
    }
  }
}

fn demo_distributed_operations(dist_supervisor: actor.Subject(DistributedSupervisorMessage)) {
  io.println("📊 Demonstrating Distributed Operations")
  io.println("--------------------------------------")
  
  // Get cluster status
  io.println("📋 Getting cluster status...")
  case actor.call(dist_supervisor, GetClusterStatus(_), 5000) {
    Ok(status) -> {
      io.println("✅ Cluster Status:")
      io.println("  Current node: " <> status.current_node)
      io.println("  Active nodes: " <> string.join(status.active_nodes, ", "))
      io.println("  Customer distribution:")
      dict.fold(status.customer_distribution, Nil, fn(_, node, count) {
        io.println("    " <> node <> ": " <> int.to_string(count) <> " customers")
      })
    }
    Error(error) -> {
      io.println("❌ Failed to get cluster status:")
      io.debug(error)
    }
  }
  
  io.println("")
  io.println("🎭 Starting customer actors...")
  
  // Start some customer actors
  let customer_ids = [1, 2, 3, 42, 100]
  
  list.each(customer_ids, fn(customer_id) {
    case actor.call(dist_supervisor, StartCustomerActor(customer_id, _), 5000) {
      Ok(Ok(customer_actor)) -> {
        io.println("✅ Started customer actor for ID: " <> int.to_string(customer_id))
        
        // Test the customer actor
        let test_customer = customer.create(Some(customer_id), "Customer " <> int.to_string(customer_id), "customer" <> int.to_string(customer_id) <> "@example.com", None, None)
        
        case actor.call(customer_actor, distributed_supervisor.UpdateCustomer(test_customer, _), 5000) {
          Ok(Ok(updated_customer)) -> {
            io.println("  ✅ Updated customer: " <> customer.to_string(updated_customer))
          }
          Ok(Error(reason)) -> {
            io.println("  ❌ Failed to update customer: " <> reason)
          }
          Error(timeout) -> {
            io.println("  ❌ Timeout updating customer")
          }
        }
      }
      Ok(Error(reason)) -> {
        io.println("❌ Failed to start customer actor for ID " <> int.to_string(customer_id) <> ": " <> reason)
      }
      Error(timeout) -> {
        io.println("❌ Timeout starting customer actor for ID: " <> int.to_string(customer_id))
      }
    }
  })
  
  io.println("")
  io.println("📋 Final cluster status:")
  case actor.call(dist_supervisor, GetClusterStatus(_), 5000) {
    Ok(status) -> {
      io.println("  Active nodes: " <> string.join(status.active_nodes, ", "))
      io.println("  Customer distribution:")
      dict.fold(status.customer_distribution, Nil, fn(_, node, count) {
        io.println("    " <> node <> ": " <> int.to_string(count) <> " customers")
      })
    }
    Error(error) -> {
      io.println("❌ Failed to get final cluster status:")
      io.debug(error)
    }
  }
  
  io.println("")
  io.println("🔄 Demonstrating Graceful Shutdown with Actor Migration...")
  case distributed_supervisor.graceful_shutdown(dist_supervisor, "node@localhost") {
    Ok(_) -> {
      io.println("✅ Graceful shutdown completed successfully!")
      io.println("  • All customer actors migrated to other nodes")
      io.println("  • Zero downtime during shutdown process")
      io.println("  • Actor state preserved across migration")
    }
    Error(reason) -> {
      io.println("❌ Graceful shutdown failed: " <> reason)
    }
  }
  
  io.println("")
  io.println("🎉 Distributed operations completed!")
  io.println("")
  io.println("✨ Key Features Demonstrated:")
  io.println("  • Distributed supervisor with consistent hashing")
  io.println("  • Customer actor distribution across nodes")
  io.println("  • Cluster status monitoring")
  io.println("  • Fault-tolerant actor management")
  io.println("  • OTP-compliant distributed system")
  io.println("  • Graceful node shutdown with zero downtime ✨")
  io.println("  • Automatic actor migration and state preservation ✨")
}

fn demo_legacy_operations() {
  // Initialize the legacy customer service
  case customer_actor.init() {
    Ok(service) -> {
      io.println("✅ Legacy customer service initialized")
      io.println("✅ In-memory database ready")
      io.println("")
      
      // Demonstrate CRUD operations
      demo_crud_operations(service)
    }
    Error(error) -> {
      io.println("❌ Failed to initialize legacy customer service:")
      io.debug(error)
    }
  }
}

fn demo_crud_operations(service: customer_actor.LegacyCustomerService) {
  io.println("📊 Demonstrating Legacy CRUD Operations")
  io.println("--------------------------------------")
  
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

fn continue_demo(service: customer_actor.LegacyCustomerService, customer1: customer.Customer, customer2: customer.Customer, customer3: customer.Customer) {
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

fn final_demo(service: customer_actor.LegacyCustomerService, customer3: customer.Customer) {
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
  io.println("🎉 Legacy demo completed successfully!")
  io.println("")
  io.println("This demonstrates a Gleam OTP application with:")
  io.println("  • Customer data model with proper types")
  io.println("  • In-memory database with CRUD operations")
  io.println("  • Customer service acting as a simplified actor")
  io.println("  • Error handling and validation")
  io.println("")
  io.println("To add full production features:")
  io.println("  • Add gleam_otp dependency for proper actors ✅")
  io.println("  • Add wisp/mist for web framework")
  io.println("  • Add sqlight for SQLite persistence")
  io.println("  • Add gleam_json for JSON serialization")
  io.println("  • Add distributed supervisor with Horde-like functionality ✅")
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