import gleeunit
import gleeunit/should
import gleam/list
import distributed_supervisor
import app_supervisor
import gleam/otp/actor

pub fn main() {
  gleeunit.main()
}

// Test distributed supervisor creation
pub fn distributed_supervisor_creation_test() {
  let config = distributed_supervisor.default_config()
  
  case distributed_supervisor.start(config) {
    Ok(supervisor) -> {
      // Test getting cluster status
      case actor.call(supervisor, distributed_supervisor.GetClusterStatus(_), 5000) {
        Ok(status) -> {
          status.current_node
          |> should.equal("node@localhost")
          
          status.active_nodes
          |> should.equal(["node@localhost"])
        }
        Error(_) -> panic as "Should be able to get cluster status"
      }
    }
    Error(reason) -> panic as "Should be able to start distributed supervisor"
  }
}

// Test app supervisor creation
pub fn app_supervisor_creation_test() {
  case app_supervisor.start_application() {
    Ok(app) -> {
      let dist_supervisor = app_supervisor.get_distributed_supervisor(app)
      
      // Test cluster status through app supervisor
      case actor.call(dist_supervisor, distributed_supervisor.GetClusterStatus(_), 5000) {
        Ok(status) -> {
          status.current_node
          |> should.equal("node@localhost")
        }
        Error(_) -> panic as "Should be able to get cluster status through app"
      }
    }
    Error(reason) -> panic as "Should be able to start application"
  }
}

// Test customer actor creation through distributed supervisor
pub fn distributed_customer_actor_test() {
  let config = distributed_supervisor.default_config()
  
  case distributed_supervisor.start(config) {
    Ok(supervisor) -> {
      // Start a customer actor
      case actor.call(supervisor, distributed_supervisor.StartCustomerActor(1, _), 5000) {
        Ok(Ok(customer_actor)) -> {
          // The actor should be created successfully
          should.be_true(True)
        }
        Ok(Error(reason)) -> panic as "Customer actor should start successfully"
        Error(_) -> panic as "Should not timeout"
      }
    }
    Error(reason) -> panic as "Should be able to start distributed supervisor"
  }
}

// Test graceful shutdown functionality
pub fn graceful_shutdown_test() {
  let config = distributed_supervisor.default_config()
  
  case distributed_supervisor.start(config) {
    Ok(supervisor) -> {
      // Start a customer actor first
      case actor.call(supervisor, distributed_supervisor.StartCustomerActor(1, _), 5000) {
        Ok(Ok(_customer_actor)) -> {
          // Test graceful shutdown
          case distributed_supervisor.graceful_shutdown(supervisor, "node@localhost") {
            Ok(_) -> {
              // Shutdown should complete successfully
              should.be_true(True)
            }
            Error(reason) -> panic as "Graceful shutdown should succeed"
          }
        }
        Ok(Error(reason)) -> panic as "Customer actor should start successfully"
        Error(_) -> panic as "Should not timeout"
      }
    }
    Error(reason) -> panic as "Should be able to start distributed supervisor"
  }
}

// Test actor migration during graceful shutdown
pub fn actor_migration_test() {
  let config = distributed_supervisor.DistributedConfig(
    nodes: ["node1@localhost", "node2@localhost"],
    ring_size: 256,
    max_retries: 3,
    discovery_interval: 5000
  )
  
  case distributed_supervisor.start(config) {
    Ok(supervisor) -> {
      // Simulate multiple nodes joining
      let _ = actor.call(supervisor, distributed_supervisor.NodeJoined("node2@localhost"), 5000)
      
      // Start multiple customer actors
      let _ = actor.call(supervisor, distributed_supervisor.StartCustomerActor(1, _), 5000)
      let _ = actor.call(supervisor, distributed_supervisor.StartCustomerActor(2, _), 5000)
      let _ = actor.call(supervisor, distributed_supervisor.StartCustomerActor(3, _), 5000)
      
      // Get initial cluster status
      case actor.call(supervisor, distributed_supervisor.GetClusterStatus(_), 5000) {
        Ok(initial_status) -> {
          initial_status.active_nodes
          |> list.length
          |> should.equal(2)
          
          // Test actor migration
          case actor.call(supervisor, distributed_supervisor.MigrateActors("node1@localhost", "node2@localhost", [1, 2]), 5000) {
            Ok(_) -> {
              // Migration should complete successfully
              should.be_true(True)
            }
            Error(_) -> panic as "Actor migration should succeed"
          }
        }
        Error(_) -> panic as "Should be able to get cluster status"
      }
    }
    Error(reason) -> panic as "Should be able to start distributed supervisor"
  }
}