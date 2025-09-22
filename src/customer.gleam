import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/int

/// Customer data type representing a customer entity
pub type Customer {
  Customer(
    id: Option(Int),
    name: String,
    email: String,
    phone: Option(String),
    address: Option(String),
  )
}

/// Create a new customer without an ID (for creation)
pub fn new(name: String, email: String) -> Customer {
  Customer(id: None, name: name, email: email, phone: None, address: None)
}

/// Create a customer with all fields
pub fn create(
  id: Option(Int),
  name: String,
  email: String,
  phone: Option(String),
  address: Option(String),
) -> Customer {
  Customer(id: id, name: name, email: email, phone: phone, address: address)
}

/// Convert customer to string representation (simplified JSON-like format)
pub fn to_string(customer: Customer) -> String {
  let id_str = case customer.id {
    Some(id) -> int.to_string(id)
    None -> "null"
  }
  let phone_str = case customer.phone {
    Some(phone) -> "\"" <> phone <> "\""
    None -> "null"
  }
  let address_str = case customer.address {
    Some(address) -> "\"" <> address <> "\""
    None -> "null"
  }
  
  "{\"id\":" <> id_str <> ",\"name\":\"" <> customer.name <> "\",\"email\":\"" <> customer.email <> "\",\"phone\":" <> phone_str <> ",\"address\":" <> address_str <> "}"
}

/// Update customer fields
pub fn update_name(customer: Customer, name: String) -> Customer {
  Customer(..customer, name: name)
}

pub fn update_email(customer: Customer, email: String) -> Customer {
  Customer(..customer, email: email)
}

pub fn update_phone(customer: Customer, phone: Option(String)) -> Customer {
  Customer(..customer, phone: phone)
}

pub fn update_address(customer: Customer, address: Option(String)) -> Customer {
  Customer(..customer, address: address)
}