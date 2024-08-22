import { NativeModulesProxy, EventEmitter, Subscription } from 'expo-modules-core';

// Import the native module. On web, it will be resolved to BlueSwarm.web.ts
// and on native platforms to BlueSwarm.ts
import BlueSwarmModule from './BlueSwarmModule';
import BlueSwarmView from './BlueSwarmView';
import { ChangeEventPayload, BlueSwarmViewProps } from './BlueSwarm.types';

// Get the native constant value.
export const PI = BlueSwarmModule.PI;

export function hello(): string {
  return BlueSwarmModule.hello();
}

export async function setValueAsync(value: string) {
  return await BlueSwarmModule.setValueAsync(value);
}

const emitter = new EventEmitter(BlueSwarmModule ?? NativeModulesProxy.BlueSwarm);

export function addChangeListener(listener: (event: ChangeEventPayload) => void): Subscription {
  return emitter.addListener<ChangeEventPayload>('onChange', listener);
}

export { BlueSwarmView, BlueSwarmViewProps, ChangeEventPayload };
