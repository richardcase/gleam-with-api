import gleam/otp/supervisor
import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/result
import gleam/erlang/process.{type Subject}
import distributed_supervisor.{type DistributedSupervisorMessage}

/// Application supervisor that manages the distributed supervisor
pub type AppSupervisor {
  AppSupervisor(
    distributed_supervisor: Subject(DistributedSupervisorMessage)
  )
}

/// Start the application with distributed supervisor
pub fn start_application() -> Result(AppSupervisor, String) {
  // Create distributed supervisor configuration
  let config = distributed_supervisor.default_config()
  
  // Start the distributed supervisor
  case distributed_supervisor.start(config) {
    Ok(dist_supervisor) -> {
      Ok(AppSupervisor(distributed_supervisor: dist_supervisor))
    }
    Error(reason) -> Error("Failed to start application: " <> reason)
  }
}

/// Get the distributed supervisor
pub fn get_distributed_supervisor(app: AppSupervisor) -> Subject(DistributedSupervisorMessage) {
  app.distributed_supervisor
}

/// Start application with traditional OTP supervisor approach
pub fn start_with_supervisor() -> Result(Subject(supervisor.Message), String) {
  let supervisor_spec = supervisor.Spec(
    argument: Nil,
    max_frequency: 5,
    frequency_period: 60,
    init: fn(_) {
      supervisor.Ready(
        children: [
          // Distributed supervisor as a child
          supervisor.worker(fn() {
            distributed_supervisor.start(distributed_supervisor.default_config())
          })
        ],
        restart: supervisor.OneForOne
      )
    }
  )
  
  case supervisor.start(supervisor_spec) {
    Ok(supervisor_subject) -> Ok(supervisor_subject)
    Error(reason) -> Error("Failed to start supervisor: " <> result.unwrap(reason, "Unknown error"))
  }
}