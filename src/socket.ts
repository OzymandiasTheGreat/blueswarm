import b4a from "b4a"
import { Callback, Duplex } from "streamx"
import * as Module from "./native"

export class ClientSocket extends Duplex<Uint8Array, Uint8Array> {
  protected _id: string
  protected _mtu: number
  protected _buffer: Uint8Array | null = null
  protected _length: number = 0

  constructor(id: string, mtu: number) {
    super()
    this._id = id
    this._mtu = mtu
  }

  get id(): string {
    return this._id
  }

  get mtu(): number {
    return this._mtu
  }

  get client(): boolean {
    return true
  }

  get server(): boolean {
    return false
  }

  _push(buffer: Uint8Array): void {
    if (this._length && this._buffer) {
      this._buffer = b4a.concat([this._buffer, buffer])

      if (this._buffer.length === this._length) {
        this.push(this._buffer)
        this._buffer = null
        this._length = 0
      }
    } else {
      const length = b4a.readUInt32LE(buffer.slice(0, 4))
      const data = buffer.slice(4)

      if (data.length < length) {
        this._buffer = data
        this._length = length
      } else {
        this.push(data)
      }
    }
  }

  protected _destroy(callback: Callback): void {
    Module.clientDisconnect(this._id)
    callback(null)
  }

  protected _write(data: Uint8Array, callback: Callback): void {
    const length = b4a.allocUnsafe(4)
    b4a.writeUInt32LE(length, data.length)
    Module.clientWrite(this._id, b4a.concat([length, data]))
      .then(callback)
      .catch(callback)
  }
}

export class ServerSocket extends Duplex<Uint8Array, Uint8Array> {
  protected _id: string
  protected _mtu: number
  protected _buffer: Uint8Array | null = null
  protected _length: number = 0

  constructor(id: string, mtu: number) {
    super()
    this._id = id
    this._mtu = mtu
  }

  get id(): string {
    return this._id
  }

  get mtu(): number {
    return this._mtu
  }

  get client(): boolean {
    return false
  }

  get server(): boolean {
    return true
  }

  _push(buffer: Uint8Array): void {
    if (this._length && this._buffer) {
      this._buffer = b4a.concat([this._buffer, buffer])

      if (this._buffer.length === this._length) {
        this.push(this._buffer)
        this._buffer = null
        this._length = 0
      }
    } else {
      const length = b4a.readUInt32LE(buffer.slice(0, 4))
      const data = buffer.slice(4)

      if (data.length < length) {
        this._buffer = data
        this._length = length
      } else {
        this.push(data)
      }
    }
  }

  protected _destroy(callback: Callback): void {
    Module.serverDisconnect(this._id)
    callback(null)
  }

  protected _write(data: Uint8Array, callback: Callback): void {
    const length = b4a.allocUnsafe(4)
    b4a.writeUInt32LE(length, data.length)
    Module.serverNotify(this._id, b4a.concat([length, data]))
      .then(callback)
      .catch(callback)
  }
}
