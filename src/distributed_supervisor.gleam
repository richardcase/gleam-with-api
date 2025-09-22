import gleam/otp/supervisor
import gleam/otp/actor
import gleam/result
import gleam/list
import gleam/dict.{type Dict}
import gleam/option.{type Option, Some, None}
import gleam/string
import gleam/int
import gleam/erlang/process.{type Subject}
import customer.{type Customer}

/// Configuration for distributed supervisor
pub type DistributedConfig {
  DistributedConfig(
    /// Nodes participating in the cluster
    nodes: List(String),
    /// Hash ring size for consistent hashing
    ring_size: Int,
    /// Maximum number of retries for failed operations
    max_retries: Int,
    /// Node discovery interval in milliseconds
    discovery_interval: Int
  )
}

/// State of the distributed supervisor
pub type DistributedSupervisorState {
  DistributedSupervisorState(
    /// Configuration
    config: DistributedConfig,
    /// Active nodes in the cluster
    active_nodes: List(String),
    /// Hash ring for customer distribution
    hash_ring: Dict(Int, String),
    /// Customer actor registry per node
    customer_actors: Dict(String, Dict(Int, Subject(CustomerActorMessage))),
    /// Local supervisor for this node's actors
    local_supervisor: Subject(supervisor.Message)
  )
}

/// Messages for the distributed supervisor
pub type DistributedSupervisorMessage {
  /// Start a customer actor on the appropriate node
  StartCustomerActor(Int, reply_with: Subject(Result(Subject(CustomerActorMessage), String)))
  /// Stop a customer actor
  StopCustomerActor(Int)
  /// Get customer actor by ID
  GetCustomerActor(Int, reply_with: Subject(Option(Subject(CustomerActorMessage))))
  /// Node joined the cluster
  NodeJoined(String)
  /// Node left the cluster
  NodeLeft(String)
  /// Rebalance actors after topology change
  Rebalance
  /// Get cluster status
  GetClusterStatus(reply_with: Subject(ClusterStatus))
}

/// Customer actor messages
pub type CustomerActorMessage {
  GetCustomer(reply_with: Subject(Result(Customer, String)))
  UpdateCustomer(Customer, reply_with: Subject(Result(Customer, String)))
  DeleteCustomer(reply_with: Subject(Result(Nil, String)))
}

/// Cluster status information
pub type ClusterStatus {
  ClusterStatus(
    current_node: String,
    active_nodes: List(String),
    customer_distribution: Dict(String, Int)
  )
}

/// Start the distributed supervisor
pub fn start(config: DistributedConfig) -> Result(Subject(DistributedSupervisorMessage), String) {
  let current_node = "node@localhost" // Simplified node identification
  
  let initial_state = DistributedSupervisorState(
    config: config,
    active_nodes: [current_node],
    hash_ring: build_hash_ring(config.ring_size, [current_node]),
    customer_actors: dict.new(),
    local_supervisor: process.new_subject() // Placeholder subject
  )
  
  case actor.start(initial_state, handle_message) {
    Ok(supervisor_actor) -> {
      // Start node discovery process
      start_node_discovery(supervisor_actor, config.discovery_interval)
      Ok(supervisor_actor)
    }
    Error(reason) -> Error("Failed to start distributed supervisor: " <> debug_to_string(reason))
  }
}

/// Handle messages for the distributed supervisor
fn handle_message(
  message: DistributedSupervisorMessage,
  state: DistributedSupervisorState
) -> actor.Next(DistributedSupervisorMessage, DistributedSupervisorState) {
  case message {
    StartCustomerActor(customer_id, reply_with) -> {
      let target_node = get_node_for_customer(customer_id, state.hash_ring)
      let current_node = "node@localhost" // Simplified node identification
      
      case target_node == current_node {
        True -> {
          // Start actor locally
          case start_local_customer_actor(customer_id, state) {
            Ok(#(actor_subject, new_state)) -> {
              process.send(reply_with, Ok(actor_subject))
              actor.continue(new_state)
            }
            Error(reason) -> {
              process.send(reply_with, Error(reason))
              actor.continue(state)
            }
          }
        }
        False -> {
          // Forward to appropriate node
          case forward_to_node(target_node, StartCustomerActor(customer_id, reply_with)) {
            Ok(_) -> actor.continue(state)
            Error(reason) -> {
              process.send(reply_with, Error(reason))
              actor.continue(state)
            }
          }
        }
      }
    }
    
    GetCustomerActor(customer_id, reply_with) -> {
      let target_node = get_node_for_customer(customer_id, state.hash_ring)
      
      case dict.get(state.customer_actors, target_node) {
        Ok(node_actors) -> {
          case dict.get(node_actors, customer_id) {
            Ok(actor_subject) -> {
              process.send(reply_with, Some(actor_subject))
            }
            Error(_) -> {
              process.send(reply_with, None)
            }
          }
        }
        Error(_) -> {
          process.send(reply_with, None)
        }
      }
      actor.continue(state)
    }
    
    NodeJoined(node_name) -> {
      let new_nodes = case list.contains(state.active_nodes, node_name) {
        True -> state.active_nodes
        False -> [node_name, ..state.active_nodes]
      }
      
      let new_hash_ring = build_hash_ring(state.config.ring_size, new_nodes)
      let new_state = DistributedSupervisorState(
        ..state,
        active_nodes: new_nodes,
        hash_ring: new_hash_ring
      )
      
      // Trigger rebalancing
      let self = process.new_subject() // Get current actor subject
      process.send(self, Rebalance)
      actor.continue(new_state)
    }
    
    NodeLeft(node_name) -> {
      let new_nodes = list.filter(state.active_nodes, fn(n) { n != node_name })
      let new_hash_ring = build_hash_ring(state.config.ring_size, new_nodes)
      
      // Remove actors for the departed node
      let new_customer_actors = dict.delete(state.customer_actors, node_name)
      
      let new_state = DistributedSupervisorState(
        ..state,
        active_nodes: new_nodes,
        hash_ring: new_hash_ring,
        customer_actors: new_customer_actors
      )
      
      // Trigger rebalancing to handle orphaned customers
      let self = process.new_subject() // Get current actor subject  
      process.send(self, Rebalance)
      actor.continue(new_state)
    }
    
    Rebalance -> {
      // Rebalance customer actors based on new hash ring
      let new_state = rebalance_actors(state)
      actor.continue(new_state)
    }
    
    GetClusterStatus(reply_with) -> {
      let current_node = "node@localhost" // Simplified node identification
      let customer_distribution = calculate_customer_distribution(state.customer_actors)
      
      let status = ClusterStatus(
        current_node: current_node,
        active_nodes: state.active_nodes,
        customer_distribution: customer_distribution
      )
      
      process.send(reply_with, status)
      actor.continue(state)
    }
    
    StopCustomerActor(customer_id) -> {
      let target_node = get_node_for_customer(customer_id, state.hash_ring)
      let current_node = "node@localhost" // Simplified node identification
      case target_node == current_node {
        True -> {
          let new_state = stop_local_customer_actor(customer_id, state)
          actor.continue(new_state)
        }
        False -> {
          let _ = forward_to_node(target_node, StopCustomerActor(customer_id))
          actor.continue(state)
        }
      }
    }
  }
}

/// Build a consistent hash ring for customer distribution
fn build_hash_ring(ring_size: Int, nodes: List(String)) -> Dict(Int, String) {
  let virtual_nodes_per_node = ring_size / list.length(nodes)
  
  list.fold(nodes, dict.new(), fn(ring, node) {
    list.fold(list.range(0, virtual_nodes_per_node - 1), ring, fn(ring, i) {
      let hash = hash_node_key(node <> ":" <> string.from_int(i))
      let position = hash % ring_size
      dict.insert(ring, position, node)
    })
  })
}

/// Get the node responsible for a customer based on consistent hashing
fn get_node_for_customer(customer_id: Int, hash_ring: Dict(Int, String)) -> String {
  let customer_hash = hash_customer_id(customer_id)
  let ring_keys = dict.keys(hash_ring) |> list.sort(int.compare)
  
  // Find the first ring position >= customer_hash
  case list.find(ring_keys, fn(key) { key >= customer_hash }) {
    Ok(key) -> {
      case dict.get(hash_ring, key) {
        Ok(node) -> node
        Error(_) -> "unknown"
      }
    }
    Error(_) -> {
      // Wrap around to the first node
      case list.first(ring_keys) {
        Ok(first_key) -> {
          case dict.get(hash_ring, first_key) {
            Ok(node) -> node
            Error(_) -> "unknown"
          }
        }
        Error(_) -> "unknown"
      }
    }
  }
}

/// Start a customer actor locally
fn start_local_customer_actor(
  customer_id: Int,
  state: DistributedSupervisorState
) -> Result(#(Subject(CustomerActorMessage), DistributedSupervisorState), String) {
  // Start a simple customer actor 
  case start_customer_actor(customer_id) {
    Ok(actor_subject) -> {
      let current_node = "node@localhost" // Simplified node identification
      let current_node_actors = case dict.get(state.customer_actors, current_node) {
        Ok(actors) -> actors
        Error(_) -> dict.new()
      }
      
      let updated_node_actors = dict.insert(current_node_actors, customer_id, actor_subject)
      let updated_customer_actors = dict.insert(state.customer_actors, current_node, updated_node_actors)
      
      let new_state = DistributedSupervisorState(
        ..state,
        customer_actors: updated_customer_actors
      )
      
      Ok(#(actor_subject, new_state))
    }
    Error(reason) -> Error("Failed to start customer actor: " <> reason)
  }
}

/// Stop a local customer actor
fn stop_local_customer_actor(
  customer_id: Int,
  state: DistributedSupervisorState
) -> DistributedSupervisorState {
  let current_node = "node@localhost" // Simplified node identification
  
  case dict.get(state.customer_actors, current_node) {
    Ok(node_actors) -> {
      let updated_node_actors = dict.delete(node_actors, customer_id)
      let updated_customer_actors = dict.insert(state.customer_actors, current_node, updated_node_actors)
      
      DistributedSupervisorState(
        ..state,
        customer_actors: updated_customer_actors
      )
    }
    Error(_) -> state
  }
}

/// Forward a message to another node
fn forward_to_node(
  target_node: String,
  message: DistributedSupervisorMessage
) -> Result(Nil, String) {
  // In a real implementation, this would use distributed Erlang messaging
  // For now, return an error indicating remote operations aren't implemented
  Error("Remote node communication not implemented for node: " <> target_node)
}

/// Start node discovery process
fn start_node_discovery(
  supervisor: Subject(DistributedSupervisorMessage),
  interval: Int
) -> Nil {
  // In a real implementation, this would periodically check for new nodes
  // and send NodeJoined/NodeLeft messages to the supervisor
  Nil
}

/// Rebalance customer actors after topology changes
fn rebalance_actors(state: DistributedSupervisorState) -> DistributedSupervisorState {
  // In a real implementation, this would migrate actors to maintain
  // proper distribution according to the hash ring
  state
}

/// Calculate customer distribution across nodes
fn calculate_customer_distribution(customer_actors: Dict(String, Dict(Int, Subject(CustomerActorMessage)))) -> Dict(String, Int) {
  dict.fold(customer_actors, dict.new(), fn(distribution, node, actors) {
    let count = dict.size(actors)
    dict.insert(distribution, node, count)
  })
}

/// Hash a node key for consistent hashing
fn hash_node_key(key: String) -> Int {
  // Simple hash function - in production, use a proper hash function
  string.to_utf_codepoints(key)
  |> list.fold(0, fn(acc, codepoint) { acc + string.utf_codepoint_to_int(codepoint) })
}

/// Hash a customer ID for consistent hashing
fn hash_customer_id(customer_id: Int) -> Int {
  // Simple hash function
  customer_id * 31 + 17
}

/// Start a customer actor
fn start_customer_actor(customer_id: Int) -> Result(Subject(CustomerActorMessage), String) {
  // Create initial customer actor state
  let initial_state = CustomerActorState(
    customer_id: customer_id,
    customer_data: None
  )
  
  case actor.start(initial_state, handle_customer_message) {
    Ok(actor_subject) -> Ok(actor_subject)
    Error(reason) -> Error("Failed to start customer actor: " <> debug_to_string(reason))
  }
}

/// Customer actor state
type CustomerActorState {
  CustomerActorState(
    customer_id: Int,
    customer_data: Option(Customer)
  )
}

/// Handle customer actor messages
fn handle_customer_message(
  message: CustomerActorMessage,
  state: CustomerActorState
) -> actor.Next(CustomerActorMessage, CustomerActorState) {
  case message {
    GetCustomer(reply_with) -> {
      case state.customer_data {
        Some(customer) -> {
          process.send(reply_with, Ok(customer))
        }
        None -> {
          process.send(reply_with, Error("Customer not found"))
        }
      }
      actor.continue(state)
    }
    
    UpdateCustomer(customer, reply_with) -> {
      let new_state = CustomerActorState(
        ..state,
        customer_data: Some(customer)
      )
      process.send(reply_with, Ok(customer))
      actor.continue(new_state)
    }
    
    DeleteCustomer(reply_with) -> {
      process.send(reply_with, Ok(Nil))
      actor.stop(process.Normal)
    }
  }
}

/// Default configuration for distributed supervisor
pub fn default_config() -> DistributedConfig {
  DistributedConfig(
    nodes: ["node@localhost"],
    ring_size: 256,
    max_retries: 3,
    discovery_interval: 5000
  )
}

/// Convert debug values to string
fn debug_to_string(value: a) -> String {
  // Simple conversion - in production use proper debugging
  "error"
}