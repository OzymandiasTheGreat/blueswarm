package me.tomasrav.blueswarm

import android.content.Context
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.types.Enumerable
import java.util.UUID

const val CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"
const val MIN_MTU = 20

enum class BlueSwarmEvent(val value: String): Enumerable {
  SERVER_CONNECTION("server-connection"),
  SERVER_DISCONNECT("server-disconnect"),
  SERVER_DATA("server-data"),
  CLIENT_CONNECTION("client-connection"),
  CLIENT_DISCONNECT("client-disconnect"),
  CLIENT_DATA("client-data"),
}

class BlueSwarmModule : Module() {
  val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()
  private var server: BlueSwarmServer? = null
  private var client: BlueSwarmClient? = null

  override fun definition() = ModuleDefinition {
    Name("BlueSwarm")

    Events(
      BlueSwarmEvent.SERVER_CONNECTION.value,
      BlueSwarmEvent.SERVER_DISCONNECT.value,
      BlueSwarmEvent.SERVER_DATA.value,
      BlueSwarmEvent.CLIENT_CONNECTION.value,
      BlueSwarmEvent.CLIENT_DISCONNECT.value,
      BlueSwarmEvent.CLIENT_DATA.value,
    )

    AsyncFunction("initServer") { service: String, characteristic: String, promise: Promise ->
      if (server == null) server = BlueSwarmServer(this@BlueSwarmModule, UUID.fromString(service), UUID.fromString(characteristic))
      promise.resolve()
    }

    AsyncFunction("initClient") { service: String, characteristic: String, promise: Promise ->
      if (client == null) client = BlueSwarmClient(this@BlueSwarmModule, UUID.fromString(service), UUID.fromString(characteristic))
      promise.resolve()
    }

    Function("close") {
      server?.close()
      server = null
      client?.close()
      client = null
      return@Function null
    }

    Function("isAdvertising") {
      return@Function server?.advertising == true
    }

    Function("isScanning") {
      return@Function client?.scanning == true
    }

    Function("serverAdvertise") {
      server?.advertise()
    }

    Function("serverStop") {
      server?.stop()
    }

    Function("serverDisconnect") { identifier: String ->
      server?.disconnect(identifier)
    }

    AsyncFunction("serverNotify") { identifier: String, data: ByteArray, promise: Promise ->
      server?.notify(identifier, data, promise)
    }

    Function("clientScan") {
      client?.scan()
    }

    Function("clientStop") {
      client?.stop()
    }

    Function("clientDisconnect") { identifier: String ->
      client?.disconnect(identifier)
    }

    AsyncFunction("clientWrite") { identifier: String, data: ByteArray, promise: Promise ->
      client?.write(identifier, data, promise)
    }
  }
}
