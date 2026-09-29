/* tslint:disable */
/* eslint-disable */

/**
 * Apply one event to a state and hand back the new one.
 */
export function apply_event(state_json: string, event_json: string): string;

/**
 * The version of the rules this build carries, so a browser can say what it is
 * running when it disagrees with somebody.
 */
export function engine_version(): string;

/**
 * Build a match from its whole event log.
 *
 * What the scorer's screen does on opening a match: the log is the lasting
 * record, and the state is only ever a fold over it.
 */
export function replay_match(events_json: string): string;

/**
 * Whether the engine would accept this event, without keeping the result.
 *
 * For disabling a button rather than letting somebody tap it and be told no.
 */
export function would_accept(state_json: string, event_json: string): boolean;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly apply_event: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly engine_version: () => [number, number];
    readonly replay_match: (a: number, b: number) => [number, number, number, number];
    readonly would_accept: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
