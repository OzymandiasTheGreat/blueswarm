package me.tomasrav.blueswarm

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import java.util.UUID

@SuppressLint("MissingPermission")
class BlueSwarmServer(private val module: BlueSwarmModule, private val serviceUUID: UUID, private val characteristicUUID: UUID) {
  private val manager: BluetoothManager
    get() = module.context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
  private val adapter: BluetoothAdapter
    get() = manager.adapter
  private val advertiser: BluetoothLeAdvertiser
    get() = adapter.bluetoothLeAdvertiser
  private val server: BluetoothGattServer by lazy {
    return@lazy manager.openGattServer(module.context, serverCallback)
  }
  private val service: BluetoothGattService by lazy {
    val service = BluetoothGattService(serviceUUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
    val characteristic = BluetoothGattCharacteristic(
        characteristicUUID,
        BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_INDICATE,
        BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE,
    )
    val descriptor = BluetoothGattDescriptor(
        UUID.fromString(CCCD_UUID),
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
    )
    characteristic.addDescriptor(descriptor)
    service.addCharacteristic(characteristic)
    return@lazy service
  }
  private val devices: HashMap<String, BluetoothDevice> = HashMap()
  private val mtu: HashMap<String, Int> = HashMap()
  private val promises: HashMap<String, Promise> = HashMap()
  private val preparedQueue: HashMap<String, MutableList<ByteArray>> = HashMap()
  private val notifyQueue: HashMap<String, MutableList<ByteArray>> = HashMap()
  var advertising = false

  private val advertisingCallback = object : AdvertiseCallback() {
    override fun onStartFailure(errorCode: Int) {
      advertising = false
      super.onStartFailure(errorCode)
    }

    override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
      advertising = true
      super.onStartSuccess(settingsInEffect)
    }
  }

  private val serverCallback = object : BluetoothGattServerCallback() {
    override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
      super.onConnectionStateChange(device, status, newState)
      if (status == BluetoothGatt.GATT_SUCCESS && device != null) {
        when (newState) {
          BluetoothGatt.STATE_CONNECTED -> {
            devices[device.address] = device
          }
          BluetoothGatt.STATE_DISCONNECTED -> {
            if (devices[device.address] != null) {
              devices.remove(device.address)
              mtu.remove(device.address)
              promises.remove(device.address)?.reject(CodedException("CONNECTION_CLOSED", "Connection is closed", null))
              preparedQueue.remove(device.address)?.clear()
              notifyQueue.remove(device.address)?.clear()
              module.sendEvent(BlueSwarmEvent.SERVER_DISCONNECT.value, mapOf("id" to device.address))
            }
          }
        }
      }
    }

    override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
      super.onMtuChanged(device, mtu)
      if (device != null) {
        this@BlueSwarmServer.mtu[device.address] = if (mtu >= 512) 512 else mtu - 3
      }
    }

    override fun onDescriptorWriteRequest(device: BluetoothDevice?, requestId: Int, descriptor: BluetoothGattDescriptor?, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
      super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
      if (device == null || value == null || descriptor?.uuid.toString() != CCCD_UUID) {
        if (responseNeeded) {
          server.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
        }
        return server.cancelConnection(device)
      }
      if (value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)) {
        preparedQueue[device.address] = emptyList<ByteArray>().toMutableList()
        notifyQueue[device.address] = emptyList<ByteArray>().toMutableList()
        module.sendEvent(BlueSwarmEvent.SERVER_CONNECTION.value, mapOf(
            "id" to device.address,
            "mtu" to (mtu[device.address] ?: MIN_MTU),
        ))
      }
      if (responseNeeded) {
        server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
      }
    }

    override fun onCharacteristicWriteRequest(device: BluetoothDevice?, requestId: Int, characteristic: BluetoothGattCharacteristic?, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
      super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
      if (device == null || value == null || characteristic?.uuid?.equals(characteristicUUID) != true) {
        return server.cancelConnection(device)
      }
      if (preparedWrite) {
        preparedQueue[device.address]?.add(value)
      } else {
        module.sendEvent(BlueSwarmEvent.SERVER_DATA.value, mapOf(
            "id" to device.address,
            "data" to value.joinToString("") { "%02x".format(it) },
        ))
      }
      if (responseNeeded) {
        server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
      }
    }

    override fun onExecuteWrite(device: BluetoothDevice?, requestId: Int, execute: Boolean) {
      super.onExecuteWrite(device, requestId, execute)
      if (device != null && execute) {
        var value = ByteArray(0)
        val queue = preparedQueue[device.address] ?: return server.cancelConnection(device)
        for (chunk in queue) {
          value += chunk
        }
        preparedQueue[device.address]?.clear()
        module.sendEvent(BlueSwarmEvent.SERVER_DATA.value, mapOf(
            "id" to device.address,
            "data" to value.joinToString("") { "%02x".format(it) },
        ))
        server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
      } else {
        server.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
      }
    }

    override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
      super.onNotificationSent(device, status)
      if (device == null) {
        return
      }
      if (status == BluetoothGatt.GATT_SUCCESS) {
        val queue = notifyQueue[device.address] ?: return promises.remove(device.address)?.reject(CodedException("DATA_LOST", "Data has been lost", null)) ?: return
        if (queue.size > 0) {
          val characteristic = service.getCharacteristic(characteristicUUID)
          val result = server.notifyCharacteristicChanged(device, characteristic, true, queue.firstOrNull()!!)
          if (result == BluetoothStatusCodes.SUCCESS) {
            queue.removeFirstOrNull()
          } else {
            notifyQueue[device.address]?.clear()
            promises.remove(device.address)?.reject(CodedException("WRITE_FAILED", "Write failed with status $result", null))
            return
          }
        }
        if (queue.size == 0) {
          promises.remove(device.address)?.resolve()
        }
      } else {
        promises.remove(device.address)?.reject(CodedException("WRITE_FAILED", "Write failed with status $status", null))
      }
    }
  }

  fun advertise() {
    if (!advertising) {
      val settings = AdvertiseSettings.Builder()
          .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
          .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
          .setConnectable(true)
          .build()
      val data = AdvertiseData.Builder()
          .addServiceUuid(ParcelUuid(serviceUUID))
          .setIncludeDeviceName(true)
          .build()
      server.clearServices()
      server.addService(service)
      advertiser.startAdvertising(settings, data, advertisingCallback)
    }
  }

  fun stop() {
    if (adapter.isEnabled && advertising) {
      advertiser.stopAdvertising(advertisingCallback)
    }
    advertising = false
  }

  fun disconnect(identifier: String) {
    val device = devices[identifier] ?: return
    server.cancelConnection(device)
  }

  fun notify(identifier: String, data: ByteArray, promise: Promise) {
    val device = devices[identifier] ?: return promise.reject(CodedException("DEVICE_NOT_FOUND", "No connected device with id $identifier", null))
    val characteristic = service.getCharacteristic(characteristicUUID)
    val size = mtu[identifier] ?: MIN_MTU
    val queue = notifyQueue[identifier] ?: return promise.reject(CodedException("DEVICE_NOT_FOUND", "No connected device with id $identifier", null))
    if (promises[identifier] != null) {
      return promise.reject(CodedException("UNRESOLVED_WRITE", "Previous write hasn't resolved yet", null))
    }
    promises[identifier] = promise
    queue.addAll(data.iterator().asSequence().chunked(size).map { it.toByteArray() })
    val result = server.notifyCharacteristicChanged(device, characteristic, true, queue.firstOrNull()!!)
    if (result == BluetoothStatusCodes.SUCCESS) {
      queue.removeFirstOrNull()
    } else {
      promises.remove(identifier)?.reject(CodedException("WRITE_FAILED", "Write failed with status $result", null))
    }
  }

  fun close() {
    stop()
    for (device in devices.values) {
      server.cancelConnection(device)
    }
    devices.clear()
    mtu.clear()
    for (promise in promises.values) {
      promise.reject(CodedException("SESSION_CLOSED", "Session is closed", null))
    }
    promises.clear()
    for (queue in preparedQueue.values) {
      queue.clear()
    }
    preparedQueue.clear()
    for (queue in notifyQueue.values) {
      queue.clear()
    }
    notifyQueue.clear()
    server.clearServices()
    server.close()
  }
}