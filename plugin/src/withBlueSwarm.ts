import { ConfigPlugin, IOSConfig, createRunOncePlugin, withInfoPlist } from "@expo/config-plugins"

const pkg = require("../../package.json")

const PERIPHERAL_USAGE = "Allow $(PRODUCT_NAME) to connect to Bluetooth LE devices"

const withBLESwarm: ConfigPlugin<{ bluetoothPeripheralPermission?: string }> = (config, { bluetoothPeripheralPermission } = {}) => {
  config = withInfoPlist(config, (config) => {
    if (!Array.isArray(config.modResults.UIBackgroundModes)) {
      config.modResults.UIBackgroundModes = []
    }
    if (!config.modResults.UIBackgroundModes.includes("bluetooth-peripheral")) {
      config.modResults.UIBackgroundModes.push("bluetooth-peripheral")
    }
    if (!config.modResults.UIBackgroundModes.includes("bluetooth-central")) {
      config.modResults.UIBackgroundModes.push("bluetooth-central")
    }
    return config
  })

  IOSConfig.Permissions.createPermissionsPlugin({
    NSBluetoothAlwaysUsageDescription: PERIPHERAL_USAGE,
  })(config, {
    NSBluetoothAlwaysUsageDescription: bluetoothPeripheralPermission,
  })

  return config
}

export default createRunOncePlugin(withBLESwarm, pkg.name, pkg.version)
