/// <reference types="node" />
declare module "ready-resource" {
  import EventEmitter from "events"

  export default class ReadyResource<T> extends EventEmitter<
    T & {
      ready: []
      close: []
    }
  > {
    opening: Promise<void> | null
    closing: Promise<void> | null
    opened: boolean
    closed: boolean

    protected async _open(): Promise<void>
    protected async _close(): Promise<void>
    async ready(): Promise<void>
    async close(): Promise<void>
  }
}
