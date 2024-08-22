import * as React from 'react';

import { BlueSwarmViewProps } from './BlueSwarm.types';

export default function BlueSwarmView(props: BlueSwarmViewProps) {
  return (
    <div>
      <span>{props.name}</span>
    </div>
  );
}
