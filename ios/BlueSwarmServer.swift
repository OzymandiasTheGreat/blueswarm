import CoreBluetooth
import ExpoModulesCore

@objc(BlueSwarmServer)
class BlueSwarmServer: NSObject {
  private let module: BlueSwarmModule
  private let service: CBMutableService
  private let characteristic: CBMutableCharacteristic
  private let manager = CBPeripheralManager()
  private var connectedDevices: [String: CBCentral] = [:]
  private var duplicateDevices: [String: CBCentral] = [:]
  private var notifyQueue: [String: [Data]] = [:]
  private var notifyPromise: [String: Promise] = [:]
  private let promise: Promise
  
  init(module: BlueSwarmModule, serviceUUID: CBUUID, characteristicUUID: CBUUID, promise: Promise) {
    self.module = module
    self.promise = promise
    service = CBMutableService(type: serviceUUID, primary: true)
    characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.read, .write, .indicate], value: nil, permissions: [.readable, .writeable])
    service.characteristics = [characteristic]
    super.init()
    manager.delegate = self
  }
  
  func isAdvertising() -> Bool {
    return manager.state == .poweredOn && manager.isAdvertising
  }
  
  func isConnected(deviceID: String) -> Bool {
    return connectedDevices[deviceID] != nil
  }
  
  func startAdvertising() {
    if (manager.state == .poweredOn && !manager.isAdvertising) {
      manager.add(service)
      manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid]])
    }
  }
  
  func stopAdvertising() {
    if (manager.isAdvertising) {
      manager.stopAdvertising()
    }
  }
  
  func disconnect(deviceID: String) {
    guard let central = connectedDevices.removeValue(forKey: deviceID) else { return }
    duplicateDevices[deviceID] = central
    notifyQueue[deviceID]?.removeAll()
    notifyQueue.removeValue(forKey: deviceID)
    notifyPromise[deviceID]?.reject(DestroyedError(client: false))
    notifyPromise.removeValue(forKey: deviceID)
    module.sendEvent(BLESwarmEvent.SERVER_DISCONNECTED.rawValue, ["device": deviceID])
  }
  
  func notify(deviceID: String, data: Data, promise: Promise) {
    guard let central = connectedDevices[deviceID] else { return promise.reject(WriteError(client: false)) }
    if (notifyPromise[deviceID] != nil) {
      return promise.reject(WriteError(client: false))
    }
    let mtu = central.maximumUpdateValueLength
    var chunks: [Data] = []
    for i in 0..<data.count where i % mtu == 0 {
      let end = data.count <= i + mtu ? data.count : i + mtu
      chunks.append(data.subdata(in: i..<end))
    }
    let isWriting = notifyQueue[deviceID]!.count > 0
    if (!isWriting) {
      for chunk in chunks {
        if (manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])) {
          chunks.removeFirst()
        } else {
          break
        }
      }
      if (chunks.count == 0) {
        return promise.resolve()
      }
    }
    notifyQueue[deviceID]!.append(contentsOf: chunks)
    notifyPromise[deviceID] = promise
  }
  
  func close() {
    stopAdvertising()
    manager.removeAllServices()
    duplicateDevices.removeAll()
    connectedDevices.removeAll()
  }
}

extension BlueSwarmServer: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if (peripheral.state == .poweredOn) {
      promise.resolve()
    } else {
      let reason: String
      switch (peripheral.state) {
      case .poweredOff: reason = ".poweredOff"
      case .resetting: reason = ".resetting"
      case .unauthorized: reason = ".unauthorized"
      case .unsupported: reason = ".unsupported"
      case .unknown: reason = ".unknown"
      default: reason = ".unexpected"
      }
      promise.reject("BLUETOOTH_NOT_AVAILABLE", "Bluetooth not available. Reason: \(reason)")
    }
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    if (!characteristic.uuid.isEqual(self.characteristic.uuid)) {
      return
    }
    let deviceID = central.identifier.uuidString
    if (module.isConnected(deviceID: deviceID) || module.isConnecting(deviceID: deviceID)) {
      duplicateDevices[deviceID] = central
      return
    }
    connectedDevices[deviceID] = central
    notifyQueue[deviceID] = []
    module.sendEvent(BLESwarmEvent.SERVER_CONNECTED.rawValue, [
      "device": deviceID,
      "mtu": central.maximumUpdateValueLength
    ])
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    if (!characteristic.uuid.isEqual(self.characteristic.uuid)) {
      return
    }
    let deviceID = central.identifier.uuidString
    if (duplicateDevices.removeValue(forKey: deviceID) != nil) {
      return
    }
    connectedDevices.removeValue(forKey: deviceID)
    notifyQueue[deviceID]?.removeAll()
    notifyQueue.removeValue(forKey: deviceID)
    notifyPromise[deviceID]?.reject(DestroyedError(client: false))
    notifyPromise.removeValue(forKey: deviceID)
    module.sendEvent(BLESwarmEvent.SERVER_DISCONNECTED.rawValue, ["device": deviceID])
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      let deviceID = request.central.identifier.uuidString
      let serviceUUID = request.characteristic.service?.uuid ?? service.uuid
      let characteristicUUID = request.characteristic.uuid
      if (duplicateDevices[deviceID] != nil) {
        manager.respond(to: request, withResult: .unlikelyError)
        continue
      }
      if (connectedDevices[deviceID] == nil) {
        manager.respond(to: request, withResult: .unlikelyError)
        continue
      }
      if (serviceUUID.isEqual(service.uuid) && characteristicUUID.isEqual(characteristic.uuid)) {
        module.sendEvent(BLESwarmEvent.SERVER_WRITE_REQUEST.rawValue, [
          "device": deviceID,
          "service": serviceUUID.uuidString,
          "characteristic": characteristicUUID.uuidString,
          "value": request.value
        ])
        manager.respond(to: request, withResult: .success)
      }
    }
  }
  
  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    for (deviceID, _) in notifyQueue {
      guard let central = connectedDevices[deviceID] else { continue }
      guard let promise = notifyPromise[deviceID] else { continue }
      while (notifyQueue[deviceID]?.count ?? 0 > 0) {
        let chunk = notifyQueue[deviceID]!.first!
        if (peripheral.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])) {
          notifyQueue[deviceID]?.removeFirst()
        } else {
          break
        }
      }
      if (notifyQueue[deviceID]!.count == 0) {
        promise.resolve()
        notifyPromise.removeValue(forKey: deviceID)
      }
    }
  }
}
