import gleam/os
import gleam/result
import gleam/int
import gleam/string
import distributed_supervisor

/// Application configuration
pub type Config {
  Config(
    /// Whether to run in distributed mode
    distributed_mode: Bool,
    /// Database URL
    database_url: String,
    /// Server port
    port: Int,
    /// Log level
    log_level: String,
    /// Maximum database connections
    max_connections: Int,
    /// Distributed supervisor configuration
    distributed_config: distributed_supervisor.DistributedConfig
  )
}

/// Load configuration from environment variables
pub fn load_config() -> Config {
  let distributed_mode = case os.get_env("DISTRIBUTED_MODE") {
    Ok("true") -> True
    Ok("1") -> True
    _ -> False
  }
  
  let nodes = case os.get_env("CLUSTER_NODES") {
    Ok(nodes_str) -> string.split(nodes_str, ",")
    Error(_) -> ["node@localhost"]
  }
  
  let ring_size = case os.get_env("HASH_RING_SIZE") {
    Ok(size_str) -> case int.parse(size_str) {
      Ok(size) -> size
      Error(_) -> 256
    }
    Error(_) -> 256
  }
  
  let discovery_interval = case os.get_env("NODE_DISCOVERY_INTERVAL") {
    Ok(interval_str) -> case int.parse(interval_str) {
      Ok(interval) -> interval
      Error(_) -> 5000
    }
    Error(_) -> 5000
  }
  
  Config(
    distributed_mode: distributed_mode,
    database_url: os.get_env("DATABASE_URL") |> result.unwrap("./customers.db"),
    port: os.get_env("PORT") 
      |> result.unwrap("8080") 
      |> int.parse 
      |> result.unwrap(8080),
    log_level: os.get_env("LOG_LEVEL") |> result.unwrap("info"),
    max_connections: os.get_env("MAX_CONNECTIONS") 
      |> result.unwrap("100") 
      |> int.parse 
      |> result.unwrap(100),
    distributed_config: distributed_supervisor.DistributedConfig(
      nodes: nodes,
      ring_size: ring_size,
      max_retries: 3,
      discovery_interval: discovery_interval
    )
  )
}

/// Default configuration for development
pub fn default_config() -> Config {
  Config(
    distributed_mode: False,
    database_url: "./customers.db",
    port: 8080,
    log_level: "info",
    max_connections: 100,
    distributed_config: distributed_supervisor.default_config()
  )
}

/// Configuration for distributed development
pub fn distributed_dev_config() -> Config {
  Config(
    distributed_mode: True,
    database_url: "./customers.db",
    port: 8080,
    log_level: "debug",
    max_connections: 100,
    distributed_config: distributed_supervisor.DistributedConfig(
      nodes: ["node1@localhost", "node2@localhost", "node3@localhost"],
      ring_size: 256,
      max_retries: 3,
      discovery_interval: 3000
    )
  )
}