import { mkdirSync, writeFileSync } from "node:fs";
import { BASE_URL, NAMESPACE } from "./env";
import type { Innings } from "./model";

/// What the run found, for the Slack message and the report: which accounts
/// were made or reused, the match, both innings, the result, and every check
/// in the Step 18 list. Written after each step, so a run that dies half way
/// still says how far it got.
export const summary = {
  base_url: BASE_URL,
  namespace: NAMESPACE,
  accounts: { created: [] as string[], reused: [] as string[] },
  clubs: {} as Record<string, { id: string; name: string; players: number }>,
  match: null as null | { id: string; url: string },
  toss: null as null | string,
  innings: [] as { team: string; score: string; overs: string; extras: number; top: string; best: string }[],
  result: null as null | string,
  checks: [] as { area: string; check: string; ok: boolean; detail?: string }[],
};

export function check(area: string, name: string, ok: boolean, detail?: string) {
  const existing = summary.checks.find((c) => c.area === area && c.check === name);
  if (existing) Object.assign(existing, { ok, detail });
  else summary.checks.push({ area, check: name, ok, detail });
}

export function inningsLine(team: string, inn: Innings) {
  const bat = [...inn.batters.values()].sort((a, b) => b.runs - a.runs)[0];
  const bowl = [...inn.bowlers.values()].sort((a, b) => b.wickets - a.wickets || a.runs - b.runs)[0];
  summary.innings.push({
    team,
    score: inn.scoreline.replace("/", "-"),
    overs: inn.overs,
    extras: inn.extras,
    top: bat ? `${bat.name} ${bat.runs}${bat.out ? "" : "*"} (${bat.balls})` : "",
    best: bowl ? `${bowl.name} ${bowl.wickets}-${bowl.runs}` : "",
  });
}

export function save() {
  mkdirSync("test-results", { recursive: true });
  writeFileSync("test-results/e2e-summary.json", JSON.stringify(summary, null, 2));
}
