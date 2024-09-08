import React, { useEffect, useState } from "react"
import { PermissionsAndroid, Platform, StyleSheet, Text, View } from "react-native"
import b4a from "b4a"
import BlueSwarm from "blueswarm"

const SERVICE_UUID = "566a83c7-f1f6-4a24-b017-190862c3ec7c"
const CHARACTERISTIC_UUID = "80fa307b-5422-444e-8937-d77d549ad3ff"

const PAYLOADS: Uint8Array[] = []
for (let i = 1; i <= 16; i++) {
  PAYLOADS.push(b4a.alloc(256 * i * 4, i * 4))
}

export default function App() {
  const [granted, setGranted] = useState(false)

  useEffect(() => {
    ;(async () => {
      if (Platform.OS === "android") {
        if (
          !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT)) ||
          !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.BLUETOOTH_SCAN)) ||
          !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.BLUETOOTH_ADVERTISE))
        ) {
          const res = await PermissionsAndroid.requestMultiple([
            PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT,
            PermissionsAndroid.PERMISSIONS.BLUETOOTH_SCAN,
            PermissionsAndroid.PERMISSIONS.BLUETOOTH_ADVERTISE,
          ])
          setGranted(
            res["android.permission.BLUETOOTH_CONNECT"] === PermissionsAndroid.RESULTS.GRANTED &&
              res["android.permission.BLUETOOTH_SCAN"] === PermissionsAndroid.RESULTS.GRANTED &&
              res["android.permission.BLUETOOTH_ADVERTISE"] === PermissionsAndroid.RESULTS.GRANTED,
          )
        } else {
          setGranted(true)
        }
      } else {
        setGranted(true)
      }
    })()
  }, [])

  useEffect(() => {
    let swarm: BlueSwarm | null = null
    if (granted) {
      swarm = new BlueSwarm(SERVICE_UUID, CHARACTERISTIC_UUID)
      swarm.on("connection", (socket) => {
        let index = 0
        socket.on("error", console.error)
        socket.on("data", (data) => {
          const payload = PAYLOADS[index++]
          console.log(`${Platform.OS} DATA ${data.length} valid ${payload ? b4a.equals(data, payload) : null} client ${socket.client}`)
        })
        for (const payload of PAYLOADS) {
          socket.write(payload)
        }
      })
      swarm.ready().then(() => swarm?.join())
    }
    return () => {
      swarm?.close()
    }
  }, [granted])

  return (
    <View style={styles.container}>
      <Text>Hello, World! 👋</Text>
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#fff",
    alignItems: "center",
    justifyContent: "center",
  },
})
