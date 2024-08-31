# blueswarm

Find and connect to nearby peers over Bluetooth LE.

## Usage

```typescript
import BlueSwarm from "blueswarm"

const swarm = new BlueSwarm(serviceUUID, characteristicUUID)

swarm.on("connection", (socket) => {
  // socket is a Duplex stream, pipe it somewhere
  socket.on("error", console.error)
})

await swarm.ready()

swarm.join({ advertise: true, scan: true })

// When you're done
await swarm.close()
```

## API

### `const swarm = new BlueSwarm(serviceUUID: string, characteristicUUID: string)`

Construct a new BlueSwarm instance. `serviceUUID` and `characteristicUUID` must be valid UUIDs formatted to string.

### `swarm.serviceUUID: string`

The service UUID used to discover peers and exchange data.

### `swarm.characteristicUUID: string`

The characteristic UUID used to exchange data.

### `swarm.connections: Set<Socket>`

A set of currently active connections.

### `swarm.advertising: boolean`

Whether the swarm is currently advertising.

### `swarm.scanning: boolean`

Whether the swarm is actively scanning for new devices.

### `await swarm.ready()`

Initialize the swarm. Must be called once on startup. The swarm won't initiate or accept connections until this resolves.

### `await swarm.close()`

Close all active connections and free up resources. The swarm cannot be used after calling this.

### `swarm.join({ advertise = true, scan = true })`

Join the swarm! Starts advertising this device as connectable and/or scanning for compatible devices to connect to.

### `swarm.leave()`

Stop scanning and advertising. This does not affect existing connections. It's a good idea to call this once you have a few connections to save battery life.

### `swarm.on("update", () => {})`

Emitted when internal state changes, e.g. connection/disconnect.

### `swarm.on("connection", (socket) => {})`

Emitted whenever swarm connects to a new device.

### `socket.client: boolean`

Whether this connection is in client mode.

### `socket.server: boolean`

Whether this connection is in server mode.
