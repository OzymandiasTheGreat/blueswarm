export enum BlueSwarmEvents {
  SERVER_CONNECTION = "server-connection",
  SERVER_DISCONNECT = "server-disconnect",
  SERVER_DATA = "server-data",
  CLIENT_CONNECTION = "client-connection",
  CLIENT_DISCONNECT = "client-disconnect",
  CLIENT_DATA = "client-data",
}

export interface BlueSwarmEvent {
  id: string
}

export interface BlueSwarmConnectionEvent extends BlueSwarmEvent {
  mtu: number
}

export interface BlueSwarmDataEvent extends BlueSwarmEvent {
  data: string | Uint8Array
}
