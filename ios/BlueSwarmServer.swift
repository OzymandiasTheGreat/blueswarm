import CoreBluetooth
import ExpoModulesCore

@objc(BlueSwarmServer)
class BlueSwarmServer: NSObject {
  private let module: BlueSwarmModule
  private let service: CBMutableService
  private let characteristic: CBMutableCharacteristic
  private let manager = CBPeripheralManager()
  private var initPromise: Promise?
  private var devices: [String: CBCentral] = [:]
  private var notifyQueue: [String: [Data]] = [:]
  private var notifyPromise: [String: Promise] = [:]

  init(module: BlueSwarmModule, serviceUUID: CBUUID, characteristicUUID: CBUUID, promise: Promise) {
    self.module = module
    initPromise = promise
    service = CBMutableService(type: serviceUUID, primary: true)
    characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.read, .write, .indicate], value: nil, permissions: [.readable, .writeable])
    service.characteristics = [characteristic]
    super.init()
    manager.delegate = self
  }
  
  var advertising: Bool {
    get { manager.state == .poweredOn && manager.isAdvertising }
  }
  
  func advertise() {
    if (!advertising) {
      manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid]])
    }
  }
  
  func stop() {
    if (advertising) {
      manager.stopAdvertising()
    }
  }
  
  func disconnect(identifier: String) {
    print("Attempted unsupported server disconnect for \(identifier)")
  }
  
  func notify(identifier: String, data: Data, promise: Promise) {
    guard let central = devices[identifier] else { return promise.reject("DEVICE_NOT_FOUND", "No connected server device with id \(identifier)") }
    if (notifyPromise[identifier] != nil) {
      return promise.reject("UNRESOLVED_WRITE", "Previous write hasn't resolved yet")
    }
    notifyPromise[identifier] = promise
    let mtu = central.maximumUpdateValueLength
    var chunks: [Data] = []
    for i in 0..<data.count where i % mtu == 0 {
      let end = data.count <= i + mtu ? data.count : i + mtu
      chunks.append(data.subdata(in: i..<end))
    }
    while !chunks.isEmpty {
      if (!manager.updateValue(chunks[0], for: characteristic, onSubscribedCentrals: [central])) {
        break
      } else {
        chunks.removeFirst()
      }
    }
    if !chunks.isEmpty {
      notifyQueue[identifier]?.append(contentsOf: chunks)
    }
  }
  
  func close() {
    stop()
    devices.removeAll()
    for promise in notifyPromise.values {
      promise.reject("SESSION_CLOSED", "Session is closed")
    }
    notifyPromise.removeAll()
    for var queue in notifyQueue.values {
      queue.removeAll()
    }
    notifyQueue.removeAll()
    initPromise?.reject("SESSION_CLOSED", "Session is closed")
    manager.removeAllServices()
  }
}

extension BlueSwarmServer: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if (peripheral.state == .poweredOn) {
      manager.add(service)
      initPromise?.resolve()
      initPromise = nil
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
      initPromise?.reject("BLUETOOTH_NOT_AVAILABLE", "Bluetooth not available. Reason: \(reason)")
      initPromise = nil
    }
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    if (!characteristic.uuid.isEqual(self.characteristic.uuid)) {
      return
    }
    let id = central.identifier.uuidString
    devices[id] = central
    notifyQueue[id] = []
    module.sendEvent(BlueSwarmEvent.SERVER_CONNECTION.rawValue, [
      "id": id,
      "mtu": central.maximumUpdateValueLength
    ])
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    if (!characteristic.uuid.isEqual(self.characteristic.uuid)) {
      return
    }
    let id = central.identifier.uuidString
    devices.removeValue(forKey: id)
    notifyQueue[id]?.removeAll()
    notifyQueue.removeValue(forKey: id)
    notifyPromise.removeValue(forKey: id)?.reject("CONNECTION_CLOSED", "Connection is closed")
    module.sendEvent(BlueSwarmEvent.SERVER_DISCONNECT.rawValue, ["id": id])
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      let id = request.central.identifier.uuidString
      let serviceUUID = request.characteristic.service?.uuid ?? service.uuid
      let characteristicUUID = request.characteristic.uuid
      if (serviceUUID.isEqual(service.uuid) && characteristicUUID.isEqual(characteristic.uuid)) {
        module.sendEvent(BlueSwarmEvent.SERVER_DATA.rawValue, [
          "id": id,
          "data": request.value
        ])
        manager.respond(to: request, withResult: .success)
      } else {
        manager.respond(to: request, withResult: .requestNotSupported)
      }
    }
  }
  
  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    for (id, _) in notifyQueue {
      guard let central = devices[id] else { continue }
      while (notifyQueue[id]?.count ?? 0 > 0) {
        let chunk = notifyQueue[id]!.first!
        if (peripheral.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])) {
          notifyQueue[id]?.removeFirst()
        } else {
          break
        }
      }
      if (notifyQueue[id]!.count == 0) {
        notifyPromise.removeValue(forKey: id)?.resolve()
      }
    }
  }
}
