/// <reference types="node" />
declare module "streamx" {
  import EventEmitter from "events"

  type Callback = (err?: Error | null) => void
  type TransformCallback<T> = (error: Error | null, mappedData: T) => void

  interface Options<S> {
    highWaterMark?: number
    map?: <T>(data: Uint8Array) => T
    byteLength?: (data: Uint8Array) => number
    signal?: AbortSignal
    open?: (this: S, callback: Callback) => void
    destroy?: (this: S, callback: Callback) => void
    predestroy?: () => void
  }

  interface ReadableOptions<S> extends Options<S> {
    eagerOpen?: boolean
    read?: (this: S, callback: Callback) => void
  }

  interface WritableOptions<T = Uint8Array, S> extends Options<S> {
    write?: (this: S, data: T, callback: Callback) => void
    writev?: (this: S, batch: T[], callback: Callback) => void
    final?: (this: S, callback: Callback) => void
  }

  interface DuplexOptions<T, S> extends ReadableOptions<S>, WritableOptions<T, S> {}

  interface TransformOptions<I, O, S> extends DuplexOptions<I, S> {
    transform?: (this: S, data: Uint8Array, callback: TransformCallback<O>) => void
  }

  export class Readable<T = Uint8Array> extends EventEmitter<{
    readable: []
    data: [T]
    end: []
    close: []
    error: [Error]
    piping: [Writable<T>]
  }> {
    destroyed: boolean

    constructor(options?: ReadableOptions<Readable<T>>)
    push(data: T | null): boolean
    read(): T | null
    unshift(data: T): void
    destroy(error?: Error | null): void
    pause(): void
    resume(): void
    pipe(stream: Writable<T>): Writable<T>
    pipe<I>(stream: Duplex<I, T>): Duplex<I, T>
    pipe<I>(stream: Transform<I, T>): Transform<I, T>
    [Symbol.asyncIterator](): AsyncIterator<T>
    protected _open(callback: Callback): void
    protected _read(callback: Callback): void
    protected _destroy(callback: Callback): void
    protected _predestroy(): void
  }

  export class Writable<T = Uint8Array> extends EventEmitter<{
    finish: []
    close: []
    error: [Error]
    pipe: [Readable]
    drain: []
  }> {
    destroyed: boolean

    constructor(options?: WritableOptions<T, Writable<T>>)
    destroy(error?: Error | null): void
    write(data: T): boolean
    end(): void
    protected _open(callback: Callback): void
    protected _destroy(callback: Callback): void
    protected _predestroy(): void
    protected _write(data: T, callback: Callback): void
    protected _writev(batch: T[], callback: Callback): void
    protected _final(callback: Callback): void
  }

  export class Duplex<I = Uint8Array, O = Uint8Array> extends Readable<O> implements Writable<I> {
    constructor(options?: DuplexOptions<I, Duplex<I, O>>)
    write(data: I): boolean
    end(): void
    protected _write(data: I, callback: Callback): void
    protected _writev(batch: I[], callback: Callback): void
    protected _final(callback: Callback): void
  }

  export class Transform<I = Uint8Array, O = Uint8Array> extends Duplex<I, O> {
    constructor(options?: TransformOptions<I, O, Transform<I, O>>)
    protected _transform(data: I, callback: TransformCallback<O>): void
  }

  export function pipeline<I = any, O = any>(source: Readable<O>, ...args: [...Duplex<I, O>[], Writable<I>]): Writable<I>
  export function pipeline<I = any, O = any>(
    source: Readable<O>,
    ...args: [...Duplex<I, O>[], Writable<I>, (error?: Error | null) => void]
  ): Writable<I>
  export function pipelinePromise<I = any, O = any>(source: Readable<O>, ...args: [...Duplex<I, O>[], Writable<I>]): Promise<void>
}
