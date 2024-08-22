import { requireNativeViewManager } from 'expo-modules-core';
import * as React from 'react';

import { BlueSwarmViewProps } from './BlueSwarm.types';

const NativeView: React.ComponentType<BlueSwarmViewProps> =
  requireNativeViewManager('BlueSwarm');

export default function BlueSwarmView(props: BlueSwarmViewProps) {
  return <NativeView {...props} />;
}
