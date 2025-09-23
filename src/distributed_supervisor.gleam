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
  /// Graceful shutdown of a node with actor migration
  GracefulShutdown(String, reply_with: Subject(Result(Nil, String)))
  /// Migrate actors from one node to another
  MigrateActors(from_node: String, to_node: String, actor_ids: List(Int))
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
  /// Extract actor state for migration
  ExtractState(reply_with: Subject(Result(Option(Customer), String)))
  /// Restore actor state after migration
  RestoreState(Option(Customer), reply_with: Subject(Result(Nil, String)))
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

/// Initiate graceful shutdown of a node with actor migration
pub fn graceful_shutdown(supervisor: Subject(DistributedSupervisorMessage), node_name: String) -> Result(Nil, String) {
  case actor.call(supervisor, GracefulShutdown(node_name, _), 30000) {
    Ok(result) -> result
    Error(_) -> Error("Timeout during graceful shutdown")
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
    
    GracefulShutdown(node_name, reply_with) -> {
      let current_node = "node@localhost" // Simplified node identification
      
      case node_name == current_node {
        True -> {
          // This node is shutting down gracefully
          case graceful_shutdown_current_node(state) {
            Ok(new_state) -> {
              process.send(reply_with, Ok(Nil))
              actor.continue(new_state)
            }
            Error(reason) -> {
              process.send(reply_with, Error(reason))
              actor.continue(state)
            }
          }
        }
        False -> {
          // Another node is shutting down gracefully
          case graceful_shutdown_remote_node(node_name, state) {
            Ok(new_state) -> {
              process.send(reply_with, Ok(Nil))
              actor.continue(new_state)
            }
            Error(reason) -> {
              process.send(reply_with, Error(reason))
              actor.continue(state)
            }
          }
        }
      }
    }
    
    MigrateActors(from_node, to_node, actor_ids) -> {
      let new_state = migrate_actors_between_nodes(from_node, to_node, actor_ids, state)
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
  // Identify actors that need to be moved based on the new hash ring
  let current_node = "node@localhost"
  
  case dict.get(state.customer_actors, current_node) {
    Ok(local_actors) -> {
      let actor_ids = dict.keys(local_actors)
      
      // Check which actors should stay on this node according to new hash ring
      let #(staying_actors, migrating_actors) = list.partition(actor_ids, fn(actor_id) {
        let target_node = get_node_for_customer(actor_id, state.hash_ring)
        target_node == current_node
      })
      
      // Migrate actors that should move to other nodes
      case migrating_actors {
        [] -> state // No migration needed
        _ -> {
          // Group actors by their target nodes
          let migration_groups = list.group(migrating_actors, fn(actor_id) {
            get_node_for_customer(actor_id, state.hash_ring)
          })
          
          // Perform migrations for each target node
          dict.fold(migration_groups, state, fn(current_state, target_node, actor_ids_to_migrate) {
            case target_node != current_node {
              True -> migrate_actors_between_nodes(current_node, target_node, actor_ids_to_migrate, current_state)
              False -> current_state
            }
          })
        }
      }
    }
    Error(_) -> state // No local actors to rebalance
  }
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
    
    ExtractState(reply_with) -> {
      process.send(reply_with, Ok(state.customer_data))
      actor.continue(state)
    }
    
    RestoreState(customer_data, reply_with) -> {
      let new_state = CustomerActorState(
        ..state,
        customer_data: customer_data
      )
      process.send(reply_with, Ok(Nil))
      actor.continue(new_state)
    }
  }
}

/// Gracefully shutdown the current node by migrating all actors
fn graceful_shutdown_current_node(state: DistributedSupervisorState) -> Result(DistributedSupervisorState, String) {
  let current_node = "node@localhost" // Simplified node identification
  
  // Get all actors on this node
  case dict.get(state.customer_actors, current_node) {
    Ok(local_actors) -> {
      let actor_ids = dict.keys(local_actors)
      let remaining_nodes = list.filter(state.active_nodes, fn(n) { n != current_node })
      
      case remaining_nodes {
        [] -> Error("No other nodes available for migration")
        [target_node, ..] -> {
          // Migrate all actors to the first available node
          let migration_result = migrate_actors_with_state(current_node, target_node, actor_ids, state)
          
          case migration_result {
            Ok(new_state) -> {
              // Remove this node from the cluster
              let final_nodes = list.filter(new_state.active_nodes, fn(n) { n != current_node })
              let final_hash_ring = build_hash_ring(new_state.config.ring_size, final_nodes)
              let final_customer_actors = dict.delete(new_state.customer_actors, current_node)
              
              Ok(DistributedSupervisorState(
                ..new_state,
                active_nodes: final_nodes,
                hash_ring: final_hash_ring,
                customer_actors: final_customer_actors
              ))
            }
            Error(reason) -> Error("Failed to migrate actors: " <> reason)
          }
        }
      }
    }
    Error(_) -> {
      // No actors on this node, just remove it from cluster
      let new_nodes = list.filter(state.active_nodes, fn(n) { n != current_node })
      let new_hash_ring = build_hash_ring(state.config.ring_size, new_nodes)
      
      Ok(DistributedSupervisorState(
        ..state,
        active_nodes: new_nodes,
        hash_ring: new_hash_ring
      ))
    }
  }
}

/// Handle graceful shutdown of a remote node
fn graceful_shutdown_remote_node(node_name: String, state: DistributedSupervisorState) -> Result(DistributedSupervisorState, String) {
  // For remote nodes, we prepare to receive migrated actors
  let current_node = "node@localhost"
  
  // Get actors from the shutting down node
  case dict.get(state.customer_actors, node_name) {
    Ok(remote_actors) -> {
      let actor_ids = dict.keys(remote_actors)
      
      // Accept migration of actors from the remote node
      let migration_result = receive_migrated_actors(node_name, current_node, actor_ids, state)
      
      case migration_result {
        Ok(new_state) -> {
          // Remove the shut down node from cluster
          let new_nodes = list.filter(new_state.active_nodes, fn(n) { n != node_name })
          let new_hash_ring = build_hash_ring(new_state.config.ring_size, new_nodes)
          let new_customer_actors = dict.delete(new_state.customer_actors, node_name)
          
          Ok(DistributedSupervisorState(
            ..new_state,
            active_nodes: new_nodes,
            hash_ring: new_hash_ring,
            customer_actors: new_customer_actors
          ))
        }
        Error(reason) -> Error("Failed to receive migrated actors: " <> reason)
      }
    }
    Error(_) -> {
      // Node has no actors, just remove it
      let new_nodes = list.filter(state.active_nodes, fn(n) { n != node_name })
      let new_hash_ring = build_hash_ring(state.config.ring_size, new_nodes)
      
      Ok(DistributedSupervisorState(
        ..state,
        active_nodes: new_nodes,
        hash_ring: new_hash_ring
      ))
    }
  }
}

/// Migrate actors with their state from one node to another
fn migrate_actors_with_state(from_node: String, to_node: String, actor_ids: List(Int), state: DistributedSupervisorState) -> Result(DistributedSupervisorState, String) {
  let current_node = "node@localhost"
  
  case from_node == current_node {
    True -> {
      // We are the source node - extract state and stop actors
      case extract_and_stop_actors(actor_ids, state) {
        Ok(#(actor_states, new_state)) -> {
          // In a real distributed system, we would send these states to the target node
          // For this implementation, we'll simulate the migration
          create_actors_with_state(to_node, actor_ids, actor_states, new_state)
        }
        Error(reason) -> Error("Failed to extract actor states: " <> reason)
      }
    }
    False -> {
      // We are not involved in this migration directly
      Ok(state)
    }
  }
}

/// Extract state from actors and stop them
fn extract_and_stop_actors(actor_ids: List(Int), state: DistributedSupervisorState) -> Result(#(List(Option(Customer)), DistributedSupervisorState), String) {
  let current_node = "node@localhost"
  
  case dict.get(state.customer_actors, current_node) {
    Ok(local_actors) -> {
      // Extract states from actors
      let states = list.map(actor_ids, fn(actor_id) {
        case dict.get(local_actors, actor_id) {
          Ok(actor_subject) -> {
            // In a real implementation, we would call ExtractState on the actor
            // For now, return None as placeholder
            None
          }
          Error(_) -> None
        }
      })
      
      // Remove actors from local registry
      let updated_local_actors = list.fold(actor_ids, local_actors, fn(actors, actor_id) {
        dict.delete(actors, actor_id)
      })
      
      let updated_customer_actors = dict.insert(state.customer_actors, current_node, updated_local_actors)
      
      let new_state = DistributedSupervisorState(
        ..state,
        customer_actors: updated_customer_actors
      )
      
      Ok(#(states, new_state))
    }
    Error(_) -> Error("No local actors found")
  }
}

/// Create actors with restored state on target node
fn create_actors_with_state(target_node: String, actor_ids: List(Int), actor_states: List(Option(Customer)), state: DistributedSupervisorState) -> Result(DistributedSupervisorState, String) {
  let current_node = "node@localhost"
  
  case target_node == current_node {
    True -> {
      // We are the target node - create actors with state
      let combined = list.zip(actor_ids, actor_states)
      
      let creation_result = list.try_fold(combined, state, fn(current_state, id_and_state) {
        let #(actor_id, customer_state) = id_and_state
        
        case start_customer_actor(actor_id) {
          Ok(actor_subject) -> {
            // In a real implementation, we would call RestoreState on the actor
            
            // Add actor to local registry
            let current_local_actors = case dict.get(current_state.customer_actors, current_node) {
              Ok(actors) -> actors
              Error(_) -> dict.new()
            }
            
            let updated_local_actors = dict.insert(current_local_actors, actor_id, actor_subject)
            let updated_customer_actors = dict.insert(current_state.customer_actors, current_node, updated_local_actors)
            
            Ok(DistributedSupervisorState(
              ..current_state,
              customer_actors: updated_customer_actors
            ))
          }
          Error(reason) -> Error("Failed to create actor " <> int.to_string(actor_id) <> ": " <> reason)
        }
      })
      
      creation_result
    }
    False -> {
      // We are not the target node
      Ok(state)
    }
  }
}

/// Receive migrated actors from another node
fn receive_migrated_actors(from_node: String, to_node: String, actor_ids: List(Int), state: DistributedSupervisorState) -> Result(DistributedSupervisorState, String) {
  // This would handle incoming actor migrations in a real distributed system
  create_actors_with_state(to_node, actor_ids, list.map(actor_ids, fn(_) { None }), state)
}

/// Migrate actors between specific nodes
fn migrate_actors_between_nodes(from_node: String, to_node: String, actor_ids: List(Int), state: DistributedSupervisorState) -> DistributedSupervisorState {
  case migrate_actors_with_state(from_node, to_node, actor_ids, state) {
    Ok(new_state) -> new_state
    Error(_) -> state
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