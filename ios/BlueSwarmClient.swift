import CoreBluetooth
import ExpoModulesCore

@objc(BlueSwarmClient)
class BlueSwarmClient: NSObject {
  private let module: BlueSwarmModule
  private let serviceUUID: CBUUID
  private let characteristicUUID: CBUUID
  private let manager = CBCentralManager()
  private var discoveredDevices: [String: CBPeripheral] = [:]
  private var connectingDevices: [String: CBPeripheral] = [:]
  private var connectedDevices: [String: CBPeripheral] = [:]
  private var writePromise: [String: Promise] = [:]
  private let promise: Promise

  init(module: BlueSwarmModule, serviceUUID: CBUUID, characteristicUUID: CBUUID, promise: Promise) {
    self.module = module
    self.serviceUUID = serviceUUID
    self.characteristicUUID = characteristicUUID
    self.promise = promise
    super.init()
    manager.delegate = self
  }

  func isScanning() -> Bool {
    return manager.state == .poweredOn && manager.isScanning
  }

  func isConnecting(deviceID: String) -> Bool {
    return connectingDevices[deviceID] != nil
  }

  func isConnected(deviceID: String) -> Bool {
    return connectedDevices[deviceID] != nil
  }

  func startScan() {
    if (!manager.isScanning) {
      manager.scanForPeripherals(withServices: [serviceUUID])
    }
  }

  func stopScan() {
    if (manager.isScanning) {
      manager.stopScan()
    }
  }

  func connect(deviceID: String) {
    if (module.isConnected(deviceID: deviceID) || module.isConnecting(deviceID: deviceID)) {
      return
    }
    guard let peripheral = discoveredDevices[deviceID] else {
      return
    }
    manager.connect(peripheral)
  }

  func disconnect(deviceID: String) {
    guard let peripheral = connectedDevices.removeValue(forKey: deviceID) ?? connectingDevices.removeValue(forKey: deviceID) else { return }
    if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
      if let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
        peripheral.setNotifyValue(false, for: characteristic)
      }
    }
    manager.cancelPeripheralConnection(peripheral)
  }

  func write(deviceID: String, data: Data, promise: Promise) {
    guard let peripheral = connectedDevices[deviceID] else { return }
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
    guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else { return }
    if (writePromise[deviceID] != nil) {
      return promise.reject(WriteError(client: true))
    }
    writePromise[deviceID] = promise
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
  }

  func close() {
    stopScan()
    for peripheral in connectingDevices.values {
      manager.cancelPeripheralConnection(peripheral)
    }
    for peripheral in connectedDevices.values {
      manager.cancelPeripheralConnection(peripheral)
    }
    discoveredDevices.removeAll()
  }
}

extension BlueSwarmClient: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if (central.state == .poweredOn) {
      promise.resolve()
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
      promise.reject("BLUETOOTH_NOT_AVAILABLE", "Bluetooth not available. Reason: \(reason)")
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    let deviceID = peripheral.identifier.uuidString
    if (module.isConnected(deviceID: deviceID) || module.isConnecting(deviceID: deviceID)) {
      return
    }
    discoveredDevices[deviceID] = peripheral
    module.sendEvent(BLESwarmEvent.CLIENT_DEVICE_DISCOVERED.rawValue, [
      "device": deviceID
    ])
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let deviceID = peripheral.identifier.uuidString
    if (module.isConnecting(deviceID: deviceID) || module.isConnected(deviceID: deviceID)) {
      manager.cancelPeripheralConnection(peripheral)
      return
    }
    connectingDevices[deviceID] = peripheral
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let deviceID = peripheral.identifier.uuidString
    discoveredDevices.removeValue(forKey: deviceID)
    connectingDevices.removeValue(forKey: deviceID)
    connectedDevices.removeValue(forKey: deviceID)
    writePromise[deviceID]?.reject(DestroyedError(client: true))
    writePromise.removeValue(forKey: deviceID)
    module.sendEvent(BLESwarmEvent.CLIENT_DISCONNECTED.rawValue, [
      "device": deviceID
    ])
  }
}

extension BlueSwarmClient: CBPeripheralDelegate {
  func cancelConnection(peripheral: CBPeripheral) {
    let deviceID = peripheral.identifier.uuidString
    manager.cancelPeripheralConnection(peripheral)
    discoveredDevices.removeValue(forKey: deviceID)
    connectingDevices.removeValue(forKey: deviceID)
    connectedDevices.removeValue(forKey: deviceID)
    writePromise[deviceID]?.reject(DestroyedError(client: true))
    writePromise.removeValue(forKey: deviceID)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let deviceID = peripheral.identifier.uuidString
    if (module.isConnected(deviceID: deviceID)) {
      return cancelConnection(peripheral: peripheral)
    }
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      return cancelConnection(peripheral: peripheral)
    }
    peripheral.discoverCharacteristics([characteristicUUID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    let deviceID = peripheral.identifier.uuidString
    if (module.isConnected(deviceID: deviceID)) {
      return cancelConnection(peripheral: peripheral)
    }
    guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else {
      return cancelConnection(peripheral: peripheral)
    }
    peripheral.setNotifyValue(true, for: characteristic)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    let deviceID = peripheral.identifier.uuidString
    if (module.isConnected(deviceID: deviceID)) {
      return cancelConnection(peripheral: peripheral)
    }
    if (characteristic.isNotifying) {
      connectedDevices[deviceID] = connectingDevices.removeValue(forKey: deviceID) ?? peripheral
      let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
      module.sendEvent(BLESwarmEvent.CLIENT_CONNECTED.rawValue, [
        "device": deviceID,
        "mtu": mtu,
      ])
    } else {
      cancelConnection(peripheral: peripheral)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil else { return }
    guard characteristic.uuid == characteristicUUID else { return }
    let value = characteristic.value ?? Data()
    module.sendEvent(BLESwarmEvent.CLIENT_NOTIFIED.rawValue, [
      "device": peripheral.identifier.uuidString,
      "service": characteristic.service!.uuid.uuidString,
      "characteristic": characteristic.uuid.uuidString,
      "value": value,
    ])
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let deviceID = peripheral.identifier.uuidString
    guard let promise = writePromise[deviceID] else { return }
    if let error {
      promise.reject(error)
    } else {
      promise.resolve()
    }
    writePromise.removeValue(forKey: deviceID)
  }
}
