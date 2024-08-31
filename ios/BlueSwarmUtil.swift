import ExpoModulesCore

class DestroyedError: CodedError {
  let code: String
  let description: String

  init(client: Bool) {
    code = "ERROR_DESTROYED"
    description = "\(client ? "Client" : "Server") is destroyed"
  }
}

class WriteError: CodedError {
  let code: String
  let description: String
  
  init(client: Bool) {
    code = "ERROR_WRITE"
    description = "\(client ? "Client" : "Server") failed to write data"
  }
}
