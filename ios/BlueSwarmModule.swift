import CoreBluetooth
import ExpoModulesCore

enum BlueSwarmEvent: String, Enumerable {
   case SERVER_CONNECTION = "server-connection"
   case SERVER_DISCONNECT = "server-disconnect"
   case SERVER_DATA = "server-data"
   case CLIENT_CONNECTION = "client-connection"
   case CLIENT_DISCONNECT = "client-disconnect"
   case CLIENT_DATA = "client-data"
}

public class BlueSwarmModule: Module {
  private var server: BlueSwarmServer? = nil
  private var client: BlueSwarmClient? = nil

  public func definition() -> ModuleDefinition {
    Name("BlueSwarm")
    
    Events(
      BlueSwarmEvent.SERVER_CONNECTION.rawValue,
      BlueSwarmEvent.SERVER_DISCONNECT.rawValue,
      BlueSwarmEvent.SERVER_DATA.rawValue,
      BlueSwarmEvent.CLIENT_CONNECTION.rawValue,
      BlueSwarmEvent.CLIENT_DISCONNECT.rawValue,
      BlueSwarmEvent.CLIENT_DATA.rawValue
    )
    
    AsyncFunction("initServer") { (serviceUUID: String, characteristicUUID: String, promise: Promise) in
      let service = CBUUID(string: serviceUUID)
      let characteristic = CBUUID(string: characteristicUUID)
      if (server == nil) { server = BlueSwarmServer(module: self, serviceUUID: service, characteristicUUID: characteristic, promise: promise) }
    }
    
    AsyncFunction("initClient") { (serviceUUID: String, characteristicUUID: String, promise: Promise) in
      let service = CBUUID(string: serviceUUID)
      let characteristic = CBUUID(string: characteristicUUID)
      if (client == nil) { client = BlueSwarmClient(module: self, serviceUUID: service, characteristicUUID: characteristic, promise: promise) }
    }
    
    Function("close") {
      server?.close()
      server = nil
      client?.close()
      client = nil
    }
    
    Function("isAdvertising") {
      return server?.advertising == true
    }
    
    Function("isScanning") {
      return client?.scanning == true
    }
    
    Function("serverAdvertise") {
      server?.advertise()
    }
    
    Function("serverStop") {
      server?.stop()
    }
    
    Function("serverDisconnect") { (identifier: String) in
      server?.disconnect(identifier: identifier)
    }
    
    AsyncFunction("serverNotify") { (identifier: String, data: Data, promise: Promise) in
      server?.notify(identifier: identifier, data: data, promise: promise)
    }
    
    Function("clientScan") {
      client?.scan()
    }
    
    Function("clientStop") {
      client?.stop()
    }
    
    Function("clientDisconnect") { (identifier: String) in
      client?.disconnect(identifier: identifier)
    }
    
    AsyncFunction("clientWrite") { (identifier: String, data: Data, promise: Promise) in
      client?.write(identifier: identifier, data: data, promise: promise)
    }
  }
}
