import b4a from "b4a"
import { Subscription } from "expo-modules-core"
import ReadyResource from "ready-resource"
import * as Module from "./native"
import { ClientSocket, ServerSocket } from "./socket"

export type Socket = ClientSocket | ServerSocket

export default class BlueSwarm extends ReadyResource<{
  connection: [Socket]
  update: []
}> {
  protected _serviceUUID: string
  protected _characteristicUUID: string
  protected _subscriptions: Subscription[] = []
  protected _connections: Map<string, Socket> = new Map()

  constructor(serviceUUID: string, characteristicUUID: string) {
    super()
    this._serviceUUID = serviceUUID
    this._characteristicUUID = characteristicUUID
  }

  get serviceUUID(): string {
    return this._serviceUUID
  }

  get characteristicUUID(): string {
    return this._characteristicUUID
  }

  get connections(): Set<Socket> {
    return new Set(this._connections.values())
  }

  get advertising(): boolean {
    return Module.isAdvertising()
  }

  get scanning(): boolean {
    return Module.isScanning()
  }

  protected _ondisconnect(id: string): void {
    const socket = this._connections.get(id)

    if (socket) {
      this._connections.delete(id)
      socket.destroy()
      this.emit("update")
    }
  }

  protected async _open(): Promise<void> {
    this._subscriptions.push(
      Module.on(Module.Event.CLIENT_CONNECTION, ({ id, mtu }) => {
        const socket = new ClientSocket(id, mtu)
        this._connections.set(id, socket)
        this.emit("update")
        this.emit("connection", socket)
      })
    )
    this._subscriptions.push(
      Module.on(Module.Event.CLIENT_DISCONNECT, ({ id }) => {
        this._ondisconnect(id)
      })
    )
    this._subscriptions.push(
      Module.on(Module.Event.CLIENT_DATA, ({ id, data }) => {
        const socket = this._connections.get(id)
        if (socket) {
          socket._push(typeof data === "string" ? b4a.from(data, "hex") : data)
        }
      })
    )
    this._subscriptions.push(
      Module.on(Module.Event.SERVER_CONNECTION, ({ id, mtu }) => {
        const socket = new ServerSocket(id, mtu)
        this._connections.set(id, socket)
        this.emit("update")
        this.emit("connection", socket)
      })
    )
    this._subscriptions.push(
      Module.on(Module.Event.SERVER_DISCONNECT, ({ id }) => {
        this._ondisconnect(id)
      })
    )
    this._subscriptions.push(
      Module.on(Module.Event.SERVER_DATA, ({ id, data }) => {
        const socket = this._connections.get(id)
        if (socket) {
          socket._push(typeof data === "string" ? b4a.from(data, "hex") : data)
        }
      })
    )
    await Module.initialize(this._serviceUUID, this._characteristicUUID)
  }

  protected async _close(): Promise<void> {
    this.leave()
    for (const subscription of this._subscriptions) {
      subscription.remove()
    }
    for (const socket of this._connections.values()) {
      socket.push(null)
      socket.end()
    }
    Module.close()
  }

  join({ advertise = true, scan = true } = {}): void {
    if (advertise && !this.advertising) Module.serverAdvertise()
    if (scan && !this.scanning) Module.clientScan()
    if (!advertise && this.advertising) Module.serverStop()
    if (!scan && this.scanning) Module.clientStop()
  }

  leave(): void {
    Module.clientStop()
    Module.serverStop()
  }
}
