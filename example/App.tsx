import { StyleSheet, Text, View } from 'react-native';

import * as BlueSwarm from 'blueswarm';

export default function App() {
  return (
    <View style={styles.container}>
      <Text>{BlueSwarm.hello()}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
