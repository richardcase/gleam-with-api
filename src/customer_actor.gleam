import gleam/result
import gleam/option.{type Option, Some, None}
import gleam/dict.{type Dict}
import gleam/otp/actor
import customer.{type Customer}
import database.{type DatabaseMessage, type DatabaseError}

/// Customer actor state
pub type CustomerActorState {
  CustomerActorState(
    id: Int,
    customer_data: Customer,
    database: actor.Subject(DatabaseMessage)
  )
}

/// Customer actor messages
pub type CustomerActorMessage {
  GetCustomer(reply_with: actor.Subject(Result(Customer, DatabaseError)))
  UpdateCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  DeleteCustomer(reply_with: actor.Subject(Result(Nil, DatabaseError)))
  Shutdown
}

/// Customer registry state
pub type CustomerRegistry {
  CustomerRegistry(
    actors: Dict(Int, actor.Subject(CustomerActorMessage)),
    database: actor.Subject(DatabaseMessage)
  )
}

/// Customer registry messages
pub type RegistryMessage {
  GetOrCreateCustomerActor(Int, reply_with: actor.Subject(Result(actor.Subject(CustomerActorMessage), DatabaseError)))
  RemoveCustomerActor(Int)
  ListActiveActors(reply_with: actor.Subject(List(Int)))
  CreateCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  ListCustomers(reply_with: actor.Subject(Result(List(Customer), DatabaseError)))
  Shutdown
}

/// Start customer registry actor
pub fn start_customer_registry(
  database: actor.Subject(DatabaseMessage)
) -> Result(actor.Subject(RegistryMessage), actor.StartError) {
  let init_registry = CustomerRegistry(
    actors: dict.new(),
    database: database
  )
  actor.start(init_registry, handle_registry_message)
}

/// Handle customer registry messages
fn handle_registry_message(
  message: RegistryMessage,
  state: CustomerRegistry,
) -> actor.Next(RegistryMessage, CustomerRegistry) {
  case message {
    GetOrCreateCustomerActor(id, reply_with) -> {
      case dict.get(state.actors, id) {
        Ok(existing_actor) -> {
          actor.send(reply_with, Ok(existing_actor))
          actor.continue(state)
        }
        Error(_) -> {
          // Need to get customer data from database first
          let reply_subject = actor.new_subject()
          actor.send(state.database, database.GetCustomer(id, reply_subject))
          
          case actor.receive(reply_subject, 5000) {
            Ok(Ok(customer_data)) -> {
              case start_customer_actor(id, customer_data, state.database) {
                Ok(customer_actor) -> {
                  let new_actors = dict.insert(state.actors, id, customer_actor)
                  let new_state = CustomerRegistry(..state, actors: new_actors)
                  actor.send(reply_with, Ok(customer_actor))
                  actor.continue(new_state)
                }
                Error(_) -> {
                  actor.send(reply_with, Error(database.ActorError))
                  actor.continue(state)
                }
              }
            }
            Ok(Error(error)) -> {
              actor.send(reply_with, Error(error))
              actor.continue(state)
            }
            Error(_) -> {
              actor.send(reply_with, Error(database.ActorError))
              actor.continue(state)
            }
          }
        }
      }
    }
    
    RemoveCustomerActor(id) -> {
      case dict.get(state.actors, id) {
        Ok(customer_actor) -> {
          actor.send(customer_actor, Shutdown)
          let new_actors = dict.delete(state.actors, id)
          let new_state = CustomerRegistry(..state, actors: new_actors)
          actor.continue(new_state)
        }
        Error(_) -> actor.continue(state)
      }
    }
    
    ListActiveActors(reply_with) -> {
      let active_ids = dict.keys(state.actors)
      actor.send(reply_with, active_ids)
      actor.continue(state)
    }
    
    CreateCustomer(customer, reply_with) -> {
      let reply_subject = actor.new_subject()
      actor.send(state.database, database.InsertCustomer(customer, reply_subject))
      
      case actor.receive(reply_subject, 5000) {
        Ok(Ok(created_customer)) -> {
          actor.send(reply_with, Ok(created_customer))
          actor.continue(state)
        }
        Ok(Error(error)) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(reply_with, Error(database.ActorError))
          actor.continue(state)
        }
      }
    }
    
    ListCustomers(reply_with) -> {
      let reply_subject = actor.new_subject()
      actor.send(state.database, database.ListCustomers(reply_subject))
      
      case actor.receive(reply_subject, 5000) {
        Ok(result) -> {
          actor.send(reply_with, result)
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(reply_with, Error(database.ActorError))
          actor.continue(state)
        }
      }
    }
    
    Shutdown -> {
      // Shutdown all customer actors first
      dict.fold(state.actors, Nil, fn(_, _id, customer_actor) {
        actor.send(customer_actor, Shutdown)
        Nil
      })
      actor.stop(actor.Normal)
    }
  }
}

/// Start a customer actor for a specific customer
fn start_customer_actor(
  id: Int,
  customer_data: Customer,
  database: actor.Subject(DatabaseMessage)
) -> Result(actor.Subject(CustomerActorMessage), actor.StartError) {
  let init_state = CustomerActorState(
    id: id,
    customer_data: customer_data,
    database: database
  )
  actor.start(init_state, handle_customer_message)
}

/// Handle customer actor messages
fn handle_customer_message(
  message: CustomerActorMessage,
  state: CustomerActorState,
) -> actor.Next(CustomerActorMessage, CustomerActorState) {
  case message {
    GetCustomer(reply_with) -> {
      actor.send(reply_with, Ok(state.customer_data))
      actor.continue(state)
    }
    
    UpdateCustomer(new_customer_data, reply_with) -> {
      let reply_subject = actor.new_subject()
      actor.send(state.database, database.UpdateCustomer(state.id, new_customer_data, reply_subject))
      
      case actor.receive(reply_subject, 5000) {
        Ok(Ok(updated_customer)) -> {
          let new_state = CustomerActorState(..state, customer_data: updated_customer)
          actor.send(reply_with, Ok(updated_customer))
          actor.continue(new_state)
        }
        Ok(Error(error)) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(reply_with, Error(database.ActorError))
          actor.continue(state)
        }
      }
    }
    
    DeleteCustomer(reply_with) -> {
      let reply_subject = actor.new_subject()
      actor.send(state.database, database.DeleteCustomer(state.id, reply_subject))
      
      case actor.receive(reply_subject, 5000) {
        Ok(Ok(_)) -> {
          actor.send(reply_with, Ok(Nil))
          actor.stop(actor.Normal)
        }
        Ok(Error(error)) -> {
          actor.send(reply_with, Error(error))
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(reply_with, Error(database.ActorError))
          actor.continue(state)
        }
      }
    }
    
    Shutdown -> {
      actor.stop(actor.Normal)
    }
  }
}
