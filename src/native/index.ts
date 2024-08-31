import { NativeModulesProxy, EventEmitter, Subscription } from 'expo-modules-core'
import BlueSwarmModule from './module'
import { BlueSwarmEvent, BlueSwarmEvents, BlueSwarmConnectionEvent, BlueSwarmDataEvent } from './types'

export { BlueSwarmEvents as Event }

const emitter = new EventEmitter(BlueSwarmModule ?? NativeModulesProxy.BlueSwarm)

export function on(event: BlueSwarmEvents.SERVER_CONNECTION, listener: (payload: BlueSwarmConnectionEvent) => void): Subscription
export function on(event: BlueSwarmEvents.SERVER_DISCONNECT, listener: (payload: BlueSwarmEvent) => void): Subscription
export function on(event: BlueSwarmEvents.SERVER_DATA, listener: (payload: BlueSwarmDataEvent) => void): Subscription
export function on(event: BlueSwarmEvents.CLIENT_CONNECTION, listener: (payload: BlueSwarmConnectionEvent) => void): Subscription
export function on(event: BlueSwarmEvents.CLIENT_DISCONNECT, listener: (payload: BlueSwarmEvent) => void): Subscription
export function on(event: BlueSwarmEvents.CLIENT_DATA, listener: (payload: BlueSwarmDataEvent) => void): Subscription
export function on(event: BlueSwarmEvents, listener: (payload: BlueSwarmEvent & BlueSwarmConnectionEvent & BlueSwarmDataEvent) => void): Subscription {
  return emitter.addListener(event, listener)
}

export async function initialize(serviceUUID: string, characteristicUUID: string) {
  await Promise.all([
    BlueSwarmModule.initServer(serviceUUID, characteristicUUID),
    BlueSwarmModule.initClient(serviceUUID, characteristicUUID),
  ])
}

export function close() {
  BlueSwarmModule.close()
}

export function isAdvertising(): boolean {
  return BlueSwarmModule.isAdvertising()
}

export function isScanning(): boolean {
  return BlueSwarmModule.isScanning()
}

export function serverAdvertise() {
  BlueSwarmModule.serverAdvertise()
}

export function serverStop() {
  BlueSwarmModule.serverStop()
}

export function serverDisconnect(identifier: string) {
  BlueSwarmModule.serverDisconnect(identifier)
}

export async function serverNotify(identifier: string, data: Uint8Array) {
  return BlueSwarmModule.serverNotify(identifier, data)
}

export function clientScan() {
  BlueSwarmModule.clientScan()
}

export function clientStop() {
  BlueSwarmModule.clientStop()
}

export function clientConnect(identifier: string) {
  BlueSwarmModule.clientConnect(identifier)
}

export function clientDisconnect(identifier: string) {
  BlueSwarmModule.clientDisconnect(identifier)
}

export async function clientWrite(identifier: string, data: Uint8Array) {
  return BlueSwarmModule.clientWrite(identifier, data)
}
