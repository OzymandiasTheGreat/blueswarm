package me.tomasrav.blueswarm

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import java.util.UUID

@SuppressLint("MissingPermission")
class BlueSwarmClient(private val module: BlueSwarmModule, private val serviceUUID: UUID, private val characteristicUUID: UUID) {
  private val manager: BluetoothManager
    get() = module.context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
  private val adapter: BluetoothAdapter
    get() = manager.adapter
  private val scanner: BluetoothLeScanner
    get() = adapter.bluetoothLeScanner
  private val discovered: MutableSet<String> = emptySet<String>().toMutableSet()
  private val devices: HashMap<String, BluetoothGatt> = HashMap()
  private val mtu: HashMap<String, Int> = HashMap()
  private val promises: HashMap<String, Promise> = HashMap()
  private val queue: HashMap<String, MutableList<ByteArray>> = HashMap()
  var scanning = false

  private val scanCallback = object : ScanCallback() {
    override fun onScanFailed(errorCode: Int) {
      scanning = false
      super.onScanFailed(errorCode)
    }

    override fun onScanResult(callbackType: Int, result: ScanResult?) {
      super.onScanResult(callbackType, result)
      scanning = true
      if (result == null || result.device.address == null) {
        return
      }
      val id = result.device.address
      if (!discovered.contains(id)) {
        discovered.add(id)
        result.device.connectGatt(module.context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
      }
    }
  }

  private val gattCallback = object : BluetoothGattCallback() {
    override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
      super.onConnectionStateChange(gatt, status, newState)
      if (status == BluetoothGatt.GATT_SUCCESS && gatt?.device != null) {
        val id = gatt.device.address
        when (newState) {
          BluetoothGatt.STATE_CONNECTED -> {
            gatt.requestMtu(517)
          }
          BluetoothGatt.STATE_DISCONNECTED -> {
            devices.remove(id)?.close()
            mtu.remove(id)
            promises.remove(id)?.reject(CodedException("CONNECTION_CLOSED", "Connection is closed", null))
            discovered.remove(id)
            queue.remove(id)?.clear()
            module.sendEvent(BlueSwarmEvent.CLIENT_DISCONNECT.value, mapOf( "id" to id ))
          }
        }
      }
    }

    override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
      super.onMtuChanged(gatt, mtu, status)
      if (status == BluetoothGatt.GATT_SUCCESS && gatt?.device != null) {
        val id = gatt.device.address
        this@BlueSwarmClient.mtu[id] = if (mtu >= 512) 512 else mtu - 3
        gatt.discoverServices()
      }
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
      super.onServicesDiscovered(gatt, status)
      if (status == BluetoothGatt.GATT_SUCCESS && gatt?.device != null) {
        val service = gatt.getService(serviceUUID) ?: return gatt.disconnect()
        val characteristic = service.getCharacteristic(characteristicUUID) ?: return gatt.disconnect()
        val descriptor = characteristic.getDescriptor(UUID.fromString(CCCD_UUID)) ?: return gatt.disconnect()
        gatt.setCharacteristicNotification(characteristic, true)
        gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
      }
    }

    override fun onDescriptorWrite(gatt: BluetoothGatt?, descriptor: BluetoothGattDescriptor?, status: Int) {
      super.onDescriptorWrite(gatt, descriptor, status)
      if (status == BluetoothGatt.GATT_SUCCESS && gatt?.device != null && descriptor?.uuid.toString() == CCCD_UUID) {
        val id = gatt.device.address
        devices[id] = gatt
        queue[id] = emptyList<ByteArray>().toMutableList()
        module.sendEvent(BlueSwarmEvent.CLIENT_CONNECTION.value, mapOf(
            "id" to id,
            "mtu" to (mtu[id] ?: MIN_MTU),
        ))
      }
    }

    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
      super.onCharacteristicChanged(gatt, characteristic, value)
      if (gatt.device == null || !characteristic.uuid.equals(characteristicUUID)) {
        return gatt.disconnect()
      }
      val id = gatt.device.address
      module.sendEvent(BlueSwarmEvent.CLIENT_DATA.value, mapOf(
        "id" to id,
        "data" to value.joinToString("") { "%02x".format(it) },
      ))
    }

    override fun onCharacteristicWrite(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
      super.onCharacteristicWrite(gatt, characteristic, status)
      if ( gatt?.device == null || characteristic?.uuid?.equals(characteristicUUID) != true) {
        gatt?.disconnect()
        return
      }
      val id = gatt.device.address
      if (status == BluetoothGatt.GATT_SUCCESS) {
        if (queue[id]?.isEmpty() == true) {
          promises.remove(id)?.resolve()
          return
        }
        val chunk = queue[id]?.firstOrNull()
        if (chunk != null) {
          val result = gatt.writeCharacteristic(characteristic, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
          if (result == BluetoothStatusCodes.SUCCESS) {
            queue[id]?.removeFirstOrNull()
          } else {
            queue[id]?.clear()
            promises.remove(id)?.reject(CodedException("WRITE_FAILED", "Write failed with status $result", null))
            return
          }
        }
      } else {
        promises.remove(id)?.reject(CodedException("WRITE_FAILED", "Write failed with status $status", null))
      }
    }
  }

  fun scan() {
    if (!scanning) {
      val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(serviceUUID)).build()
      val settings = ScanSettings.Builder()
          .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
          .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
          .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
          .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
          .setReportDelay(0)
          .build()
      scanner.startScan(listOf(filter), settings, scanCallback)
      scanning = true
    }
  }

  fun stop() {
    scanner.stopScan(scanCallback)
    scanning = false
  }

  fun disconnect(identifier: String) {
    devices[identifier]?.disconnect()
  }

  fun write(identifier: String, data: ByteArray, promise: Promise) {
    val gatt = devices[identifier] ?: return promise.reject(CodedException("DEVICE_NOT_FOUND", "No connected device with id $identifier", null))
    val characteristic = gatt.getService(serviceUUID)?.getCharacteristic(characteristicUUID) ?: run {
      gatt.disconnect()
      return promise.reject(CodedException("INVALID_DEVICE", "Device $identifier doesn't support writing", null))
    }
    val size = mtu[identifier] ?: MIN_MTU
    if (promises[identifier] != null) {
      return promise.reject(CodedException("UNRESOLVED_WRITE", "Previous write hasn't resolved yet", null))
    }
    promises[identifier] = promise
    if (data.size > size) {
      queue[identifier]?.addAll(data.iterator().asSequence().chunked(size).map { it.toByteArray() })
    } else {
      queue[identifier]?.add(data)
    }
    val chunk = queue[identifier]?.firstOrNull()!!
    val result = gatt.writeCharacteristic(characteristic, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
    if (result == BluetoothStatusCodes.SUCCESS) {
      queue[identifier]?.removeFirstOrNull()
      return
    }
    promises.remove(identifier)
    promise.reject(CodedException("WRITE_FAILED", "Write failed with status $result", null))
  }

  fun close() {
    stop()
    for (gatt in devices.values) {
      gatt.disconnect()
    }
    mtu.clear()
    for (promise in promises.values) {
      promise.reject(CodedException("SESSION_CLOSED", "Session is closed", null))
    }
    promises.clear()
    for (queue in this.queue.values) {
      queue.clear()
    }
    queue.clear()
  }
}
