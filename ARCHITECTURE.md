# Architecture Guide: Complete OTP Customer API

This document outlines how to expand the current demonstration into a full-featured OTP application with REST API and database persistence.

## Current Implementation (Demo)

The demo provides a solid foundation with:

- ✅ Type-safe customer data model
- ✅ In-memory database with CRUD operations
- ✅ Customer service layer
- ✅ Error handling and validation
- ✅ Unit tests

## Full Production Architecture

### 1. OTP Actor System

```gleam
// src/customer_actor.gleam (Enhanced)
import gleam/otp/actor
import gleam/otp/supervisor

pub type CustomerActor {
  CustomerActor(
    id: Int,
    customer_data: Customer,
    database: actor.Subject(DatabaseMessage)
  )
}

// Each customer gets its own actor for:
// - Concurrent access handling
// - State isolation
// - Fault tolerance
```

### 2. Supervisor Tree

```gleam
// src/app_supervisor.gleam
import gleam/otp/supervisor

pub fn start_application() {
  supervisor.start_spec(
    supervisor.Spec(
      argument: Nil,
      max_frequency: 5,
      frequency_period: 60,
      init: fn(_) {
        supervisor.Ready(
          children: [
            // Database connection pool
            database_supervisor_spec(),
            // Customer actor registry
            customer_registry_spec(),
            // Web server
            web_server_spec(),
          ],
          restart: supervisor.OneForOne
        )
      }
    )
  )
}
```

### 3. Database Layer with SQLite

```gleam
// src/database.gleam (Enhanced)
import sqlight
import gleam/otp/actor

pub type DatabaseActor {
  DatabaseActor(connection: sqlight.Connection)
}

pub type DatabaseMessage {
  InsertCustomer(Customer, reply_with: Subject(Result(Customer, DatabaseError)))
  GetCustomer(Int, reply_with: Subject(Result(Customer, DatabaseError)))
  UpdateCustomer(Int, Customer, reply_with: Subject(Result(Customer, DatabaseError)))
  DeleteCustomer(Int, reply_with: Subject(Result(Nil, DatabaseError)))
  ListCustomers(reply_with: Subject(Result(List(Customer), DatabaseError)))
}

// Connection pooling and prepared statements
```

### 4. REST API with Wisp

```gleam
// src/api.gleam
import wisp.{type Request, type Response}
import gleam/http.{Get, Post, Put, Delete}
import gleam/json

pub type Context {
  Context(
    customer_registry: actor.Subject(RegistryMessage),
    database: actor.Subject(DatabaseMessage)
  )
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)

  case wisp.path_segments(req) {
    ["api", "customers"] -> handle_customers_collection(req, ctx)
    ["api", "customers", id] -> handle_customer_item(req, ctx, id)
    ["health"] -> wisp.ok() |> wisp.string_response("OK")
    [] -> wisp.redirect("/api/customers")
    _ -> wisp.not_found()
  }
}
```

### 5. Customer Registry

```gleam
// src/customer_registry.gleam
import gleam/otp/actor
import gleam/dict.{type Dict}

pub type CustomerRegistry {
  CustomerRegistry(
    actors: Dict(Int, actor.Subject(CustomerActorMessage)),
    database: actor.Subject(DatabaseMessage)
  )
}

pub type RegistryMessage {
  GetOrCreateCustomerActor(Int, reply_with: Subject(actor.Subject(CustomerActorMessage)))
  RemoveCustomerActor(Int)
  ListActiveActors(reply_with: Subject(List(Int)))
}

// Manages lifecycle of customer actors
// Provides actor discovery and routing
```

## API Implementation Details

### 1. Endpoint Handlers

```gleam
// GET /api/customers
fn list_customers(ctx: Context) -> Response {
  case actor.call(ctx.database, ListCustomers(_), 5000) {
    Ok(customers) -> {
      let json = json.array(customers, customer.to_json)
      wisp.json_response(json, 200)
    }
    Error(error) -> handle_database_error(error)
  }
}

// POST /api/customers  
fn create_customer(req: Request, ctx: Context) -> Response {
  use json_data <- wisp.require_json(req)
  
  case customer.from_json(json_data) {
    Ok(customer_data) -> {
      case actor.call(ctx.database, InsertCustomer(customer_data, _), 5000) {
        Ok(created_customer) -> {
          // Start actor for new customer
          let _ = actor.call(
            ctx.customer_registry, 
            GetOrCreateCustomerActor(created_customer.id, _), 
            5000
          )
          
          wisp.json_response(customer.to_json(created_customer), 201)
        }
        Error(error) -> handle_database_error(error)
      }
    }
    Error(_) -> wisp.bad_request()
  }
}
```

### 2. Error Handling

```gleam
fn handle_database_error(error: DatabaseError) -> Response {
  case error {
    database.NotFound -> {
      let json = json.object([
        #("error", json.string("Not Found")),
        #("message", json.string("Customer not found"))
      ])
      wisp.json_response(json, 404)
    }
    database.EmailExists -> {
      let json = json.object([
        #("error", json.string("Conflict")),
        #("message", json.string("Email already exists"))
      ])
      wisp.json_response(json, 409)
    }
    database.InvalidData -> wisp.bad_request()
    database.SqliteError(_) -> wisp.internal_server_error()
  }
}
```

### 3. JSON Serialization

```gleam
// Enhanced customer.gleam
import gleam/json
import gleam/dynamic

pub fn to_json(customer: Customer) -> json.Json {
  json.object([
    #("id", case customer.id {
      Some(id) -> json.int(id)
      None -> json.null()
    }),
    #("name", json.string(customer.name)),
    #("email", json.string(customer.email)),
    #("phone", json.nullable(json.string, customer.phone)),
    #("address", json.nullable(json.string, customer.address)),
    #("created_at", json.string(customer.created_at)),
    #("updated_at", json.string(customer.updated_at))
  ])
}

pub fn from_json(data: dynamic.Dynamic) -> Result(Customer, dynamic.DecodeErrors) {
  dynamic.decode5(
    Customer,
    dynamic.optional_field("id", dynamic.int),
    dynamic.field("name", dynamic.string),
    dynamic.field("email", dynamic.string),
    dynamic.optional_field("phone", dynamic.string),
    dynamic.optional_field("address", dynamic.string),
  )(data)
}
```

## Configuration and Deployment

### 1. Configuration

```gleam
// src/config.gleam
import gleam/os

pub type Config {
  Config(
    database_url: String,
    port: Int,
    log_level: String,
    max_connections: Int
  )
}

pub fn load_config() -> Config {
  Config(
    database_url: os.get_env("DATABASE_URL") |> result.unwrap("./customers.db"),
    port: os.get_env("PORT") |> result.unwrap("8080") |> int.parse |> result.unwrap(8080),
    log_level: os.get_env("LOG_LEVEL") |> result.unwrap("info"),
    max_connections: os.get_env("MAX_CONNECTIONS") |> result.unwrap("100") |> int.parse |> result.unwrap(100)
  )
}
```

### 2. Docker Deployment

```dockerfile
# Dockerfile
FROM ghcr.io/gleam-lang/gleam:v1.5.1-erlang-alpine

WORKDIR /app
COPY . .

RUN gleam deps download
RUN gleam build

EXPOSE 8080
CMD ["gleam", "run"]
```

### 3. Database Migrations

```gleam
// src/migrations.gleam
pub fn run_migrations(db: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  let migrations = [
    "CREATE TABLE IF NOT EXISTS customers (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       email TEXT NOT NULL UNIQUE,
       phone TEXT,
       address TEXT,
       created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
       updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
     )",
    "CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email)",
    "CREATE TRIGGER IF NOT EXISTS customers_updated_at
     AFTER UPDATE ON customers
     FOR EACH ROW
     BEGIN
       UPDATE customers SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
     END"
  ]
  
  list.try_each(migrations, fn(sql) {
    sqlight.exec(sql, db)
  })
}
```

## Testing Strategy

### 1. Unit Tests

```gleam
// test/customer_test.gleam
import gleeunit/should
import customer

pub fn customer_validation_test() {
  customer.new("", "invalid-email")
  |> customer.validate
  |> should.be_error
}

pub fn customer_json_serialization_test() {
  let customer = customer.new("John", "john@example.com")
  let json = customer.to_json(customer)
  let parsed = customer.from_json(json)
  
  parsed
  |> should.be_ok
  |> should.equal(customer)
}
```

### 2. Integration Tests

```gleam
// test/api_test.gleam
import gleeunit/should
import wisp/testing

pub fn create_customer_api_test() {
  let request = testing.post_json("/api/customers", [
    #("name", json.string("Jane Doe")),
    #("email", json.string("jane@example.com"))
  ])
  
  let response = handle_request(request, test_context())
  
  response.status
  |> should.equal(201)
}
```

## Performance Considerations

1. **Connection Pooling**: Use a pool of database connections
2. **Actor Lifecycle**: Implement customer actor hibernation for inactive customers
3. **Caching**: Add Redis for frequently accessed customer data
4. **Monitoring**: Implement health checks and metrics
5. **Rate Limiting**: Add request rate limiting per client

This architecture provides a robust, scalable foundation for a production customer management system using Gleam's strengths in type safety, concurrency, and fault tolerance.