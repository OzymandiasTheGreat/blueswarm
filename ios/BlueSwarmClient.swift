import CoreBluetooth
import ExpoModulesCore

@objc(BlueSwarmClient)
class BlueSwarmClient: NSObject {
  private let module: BlueSwarmModule
  private let serviceUUID: CBUUID
  private let characteristicUUID: CBUUID
  private let manager = CBCentralManager()
  private var initPromise: Promise?
  private var connecting: Set<CBPeripheral> = []
  private var devices: [String: CBPeripheral] = [:]
  private var writePromise: [String: Promise] = [:]

  init(module: BlueSwarmModule, serviceUUID: CBUUID, characteristicUUID: CBUUID, promise: Promise) {
    self.module = module
    initPromise = promise
    self.serviceUUID = serviceUUID
    self.characteristicUUID = characteristicUUID
     super.init()
    manager.delegate = self
  }
  
  var scanning: Bool {
    get { manager.state == .poweredOn && manager.isScanning }
  }

  func scan() {
    if (manager.state == .poweredOn && !scanning) {
      manager.scanForPeripherals(withServices: [serviceUUID])
    }
  }

  func stop() {
    if (scanning) {
      manager.stopScan()
    }
  }

  func disconnect(identifier: String) {
    guard let peripheral = devices.removeValue(forKey: identifier) else { return }
    if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
      if let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
        peripheral.setNotifyValue(false, for: characteristic)
      }
    }
    manager.cancelPeripheralConnection(peripheral)
  }

  func write(identifier: String, data: Data, promise: Promise) {
    guard let peripheral = devices[identifier] else { return promise.reject("DEVICE_NOT_FOUND", "No connected client device with id \(identifier)") }
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return promise.reject("INVALID_DEVICE", "Device \(identifier) doesn't support writing") }
    guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else { return promise.reject("INVALID_DEVICE", "Device \(identifier) doesn't support writing") }
    if (writePromise[identifier] != nil) {
      return promise.reject("UNRESOLVED_WRITE", "Previous write hasn't resolved yet")
    }
    writePromise[identifier] = promise
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
  }

  func close() {
    stop()
    for peripheral in devices.values {
      manager.cancelPeripheralConnection(peripheral)
    }
    for promise in writePromise.values {
      promise.reject("SESSION_CLOSED", "Session is closed")
    }
    initPromise?.reject("SESSION_CLOSED", "Session is closed")
  }
}

extension BlueSwarmClient: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn) {
      initPromise?.resolve()
      initPromise = nil
    } else {
      let reason: String
      switch (central.state) {
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

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    connecting.insert(peripheral)
    manager.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let id = peripheral.identifier.uuidString
    connecting.remove(peripheral)
    devices.removeValue(forKey: id)
    writePromise.removeValue(forKey: id)?.reject("CONNECTION_CLOSED", "Connection is closed")
    module.sendEvent(BlueSwarmEvent.CLIENT_DISCONNECT.rawValue, [
      "id": id
    ])
  }
}

extension BlueSwarmClient: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      return manager.cancelPeripheralConnection(peripheral)
    }
    peripheral.discoverCharacteristics([characteristicUUID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else {
      return manager.cancelPeripheralConnection(peripheral)
    }
    peripheral.setNotifyValue(true, for: characteristic)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    let id = peripheral.identifier.uuidString
    if (characteristic.isNotifying) {
      devices[id] = peripheral
      let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
      module.sendEvent(BlueSwarmEvent.CLIENT_CONNECTION.rawValue, [
        "id": id,
        "mtu": mtu,
      ])
    } else {
      manager.cancelPeripheralConnection(peripheral)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil else { return }
    guard characteristic.uuid == characteristicUUID else { return }
    let value = characteristic.value ?? Data()
    module.sendEvent(BlueSwarmEvent.CLIENT_DATA.rawValue, [
      "id": peripheral.identifier.uuidString,
      "data": value,
    ])
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let id = peripheral.identifier.uuidString
    if let error {
      writePromise.removeValue(forKey: id)?.reject(error)
    } else {
      writePromise.removeValue(forKey: id)?.resolve()
    }
  }
}
