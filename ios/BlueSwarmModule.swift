import CoreBluetooth
import ExpoModulesCore

enum BlueSwarmEvent: String, Enumerable {
  case SERVER_CONNECTED = "serverConnected"
  case SERVER_DISCONNECTED = "serverDisconnected"
  case SERVER_WRITE_REQUEST = "serverWriteRequest"
  case CLIENT_DEVICE_DISCOVERED = "clientDeviceDiscovered"
  case CLIENT_CONNECTED = "clientConnected"
  case CLIENT_DISCONNECTED = "clientDisconnected"
  case CLIENT_NOTIFIED = "clientNotified"
}

public class BlueSwarmModule: Module {
  private var server: BlueSwarmServer? = nil
  private var client: BlueSwarmClient? = nil
  
  public func isConnecting(deviceID: String) -> Bool {
    return client?.isConnecting(deviceID: deviceID) == true
  }
  
  public func isConnected(deviceID: String) -> Bool {
    return server?.isConnected(deviceID: deviceID) == true || client?.isConnected(deviceID: deviceID) == true
  }
  
  public func definition() -> ModuleDefinition {
    Name("BlueSwarm")

    Events(
      "serverConnected",
      "serverDisconnected",
      "serverWriteRequest",
      "clientDeviceDiscovered",
      "clientConnected",
      "clientDisconnected",
      "clientNotified"
    )
    
    Property("isInitialized") { () -> Bool in
      return server != nil || client != nil
    }
    
    Property("isAdvertising") { () -> Bool in
      return server?.isAdvertising() ?? false
    }
    
    Property("isScanning") { () -> Bool in
      return client?.isScanning() ?? false
    }

    AsyncFunction("initializeServer") { (serviceUUID: String, characteristicUUID: String, promise: Promise) in
      let service = CBUUID(string: serviceUUID)
      let characteristic = CBUUID(string: characteristicUUID)
      if (server == nil) { server = BLESwarmServer(module: self, serviceUUID: service, characteristicUUID: characteristic, promise: promise) }
    }
    
    Function("closeServer") {
      server?.close()
      server = nil
    }
    
    AsyncFunction("initializeClient") { (serviceUUID: String, characteristicUUID: String, promise: Promise) in
      let service = CBUUID(string: serviceUUID)
      let characteristic = CBUUID(string: characteristicUUID)
      if (client == nil) { client = BLESwarmClient(module: self, serviceUUID: service, characteristicUUID: characteristic, promise: promise) }
    }
    
    Function("closeClient") {
      client?.close()
      client = nil
    }
    
    Function("isConnecting") { (deviceID: String) -> Bool in
      return isConnecting(deviceID: deviceID)
    }
    
    Function("isConnected") { (deviceID: String) -> Bool in
      return isConnected(deviceID: deviceID)
    }
    
    Function("startAdvertising") {
      server?.startAdvertising()
    }
    
    Function("stopAdvertising") {
      server?.stopAdvertising()
    }
    
    Function("cancelServerConnection") { (deviceID: String) in
      server?.disconnect(deviceID: deviceID)
    }
    
    AsyncFunction("notify") { (deviceID: String, data: Data, promise: Promise) in
      server?.notify(deviceID: deviceID, data: data, promise: promise)
    }
    
    Function("startScan") {
      client?.startScan()
    }
    
    Function("stopScan") {
      client?.stopScan()
    }
    
    Function("connect") { (deviceID: String) in
      client?.connect(deviceID: deviceID)
    }
    
    Function("disconnect") { (deviceID: String) in
      client?.disconnect(deviceID: deviceID)
    }
    
    AsyncFunction("write") { (deviceID: String, data: Data, promise: Promise) in
      client?.write(deviceID: deviceID, data: data, promise: promise)
    }
  }
}
