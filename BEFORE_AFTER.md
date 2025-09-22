# OTP Actor Implementation - Before vs After

This document shows the transformation from a simple service pattern to real OTP actors.

## Before: Simple Service Pattern

### customer_actor.gleam (Old)
```gleam
pub type CustomerService {
  CustomerService(database: Database)
}

pub fn init() -> Result(CustomerService, DatabaseError) {
  use db <- result.try(database.init())
  Ok(CustomerService(database: db))
}

pub fn create_customer(
  service: CustomerService, 
  customer: Customer
) -> Result(#(Customer, CustomerService), DatabaseError) {
  use #(new_customer, new_db) <- result.try(
    database.insert_customer(service.database, customer)
  )
  Ok(#(new_customer, CustomerService(database: new_db)))
}
```

### Problems with Service Pattern:
- No concurrency - single threaded access
- No fault tolerance - if service crashes, all state lost
- No isolation - all customers share same service instance
- Not scalable - can't distribute across nodes

## After: Real OTP Actors

### database.gleam (New)
```gleam
pub type DatabaseMessage {
  InsertCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  GetCustomer(Int, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  UpdateCustomer(Int, Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  DeleteCustomer(Int, reply_with: actor.Subject(Result(Nil, DatabaseError)))
  ListCustomers(reply_with: actor.Subject(Result(List(Customer), DatabaseError)))
  Shutdown
}

pub fn start_database_actor() -> Result(actor.Subject(DatabaseMessage), actor.StartError) {
  let init_db = Database(customers: dict.new(), next_id: 1)
  actor.start(init_db, handle_database_message)
}
```

### customer_actor.gleam (New)
```gleam
pub type CustomerRegistry {
  CustomerRegistry(
    actors: Dict(Int, actor.Subject(CustomerActorMessage)),
    database: actor.Subject(DatabaseMessage)
  )
}

pub type RegistryMessage {
  GetOrCreateCustomerActor(Int, reply_with: actor.Subject(Result(actor.Subject(CustomerActorMessage), DatabaseError)))
  CreateCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  ListCustomers(reply_with: actor.Subject(Result(List(Customer), DatabaseError)))
  Shutdown
}

pub type CustomerActorMessage {
  GetCustomer(reply_with: actor.Subject(Result(Customer, DatabaseError)))
  UpdateCustomer(Customer, reply_with: actor.Subject(Result(Customer, DatabaseError)))
  DeleteCustomer(reply_with: actor.Subject(Result(Nil, DatabaseError)))
  Shutdown
}
```

### Benefits of OTP Actor Pattern:
- **Concurrency**: Multiple customers can be accessed simultaneously
- **Fault Tolerance**: Individual customer actor crashes don't affect others
- **Isolation**: Each customer has its own actor and state
- **Scalability**: Can distribute actors across multiple nodes
- **Type Safety**: Message protocols ensure compile-time correctness
- **Supervision**: Actors can be supervised and restarted automatically

## Architecture Evolution

### Before (Service Pattern)
```
Main -> CustomerService -> Database (In-Memory Dict)
```

### After (Actor Pattern)
```
Main -> CustomerRegistry Actor
         ├── Customer Actor (ID: 1)
         ├── Customer Actor (ID: 2) 
         └── Customer Actor (ID: 3)
         
         Database Actor (Separate Concurrent Process)
```

## Message Flow Example

### Creating a Customer
1. Send `CreateCustomer` message to Registry
2. Registry sends `InsertCustomer` to Database Actor
3. Database Actor processes insertion and replies
4. Registry optionally creates Customer Actor for new customer
5. Response sent back to caller

### Getting a Customer
1. Send `GetOrCreateCustomerActor(id)` to Registry
2. Registry checks if Customer Actor exists for ID
3. If not, gets customer data from Database Actor
4. Registry creates new Customer Actor with data
5. Customer Actor Subject returned to caller
6. Caller can now send messages directly to Customer Actor

## Type Safety

All actor communication is type-safe at compile time:

```gleam
// This would be a compile error:
actor.send(database_actor, "invalid message")  // ❌

// This is correct:
actor.send(database_actor, InsertCustomer(customer, reply_subject))  // ✅
```

## Fault Tolerance

If a Customer Actor crashes:
- Only that specific customer is affected
- Registry can detect crash and restart actor
- Database Actor continues running unaffected
- Other Customer Actors continue running unaffected

This is the power of the Actor Model with OTP supervision!