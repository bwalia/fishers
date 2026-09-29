/// The cricket engine, in the browser.
///
/// `src/engine/` is generated from `backend/wasm` by
/// `scripts/build-engine-wasm.sh`, and behind it is the same Rust the API
/// replays with and both phones score with. Not a port of the Laws — the Laws.
///
/// It is loaded on demand, not with the page. It is a few hundred kilobytes and
/// only the scorer's screen needs it; a captain checking a fixture should not
/// pay for it.

type EngineModule = typeof import("@/engine/fishers_wasm");

let loading: Promise<EngineModule> | null = null;

/// Load the engine once and hand back the same instance after that.
export function engine(): Promise<EngineModule> {
  if (!loading) {
    loading = (async () => {
      const mod = await import("@/engine/fishers_wasm");
      // `--target web` hands back an initialiser that fetches the .wasm.
      await mod.default();
      return mod;
    })().catch((err) => {
      // A failed load must not be remembered as a failure for ever: a scorer
      // who was offline when the page opened should get the engine when they
      // are not.
      loading = null;
      throw err;
    });
  }
  return loading;
}

/// Rebuild a match from its whole log.
export async function replay(events: unknown[]): Promise<unknown> {
  const e = await engine();
  return JSON.parse(e.replay_match(JSON.stringify(events)));
}

/// Apply one event and hand back the new state.
///
/// Throws with the engine's own words — "nobody bowls two overs in a row", not
/// "failed" — which is the whole reason for having it here rather than finding
/// out when the network returns.
export async function apply(state: unknown, event: unknown): Promise<unknown> {
  const e = await engine();
  return JSON.parse(e.apply_event(JSON.stringify(state), JSON.stringify(event)));
}

/// Whether the engine would accept this, without keeping the result.
export async function wouldAccept(state: unknown, event: unknown): Promise<boolean> {
  const e = await engine();
  return e.would_accept(JSON.stringify(state), JSON.stringify(event));
}

/// The rules this build carries, for saying what a browser is running when it
/// disagrees with somebody.
export async function engineVersion(): Promise<string> {
  return (await engine()).engine_version();
}
