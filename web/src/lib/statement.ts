/// Importing a bank statement (plan §12, step D): the treasurer picks the CSV
/// their bank exports, sees what each payment in it matches, and ticks the
/// lot off in one go. The shapes the API answers with, and the little worked
/// out here.
///
/// The statement holds the club's other banking too, so it lives only in the
/// page's memory: never in a URL, never logged, never kept in storage. The
/// server keeps nothing of it either, beyond a fingerprint of each line
/// applied.
///
/// Kept free of the API client and the dictionary so `npm test` can import it
/// directly; only types come from elsewhere, and those are erased.

import type { Payment } from "./payments";

/// `confirm` (ticks their "I've paid"), `record` (their reference, but they
/// hadn't said: recorded as paid), `check` (a person looks), `unknown`
/// (nobody's reference) or `already` (applied before).
export type StatementAction = string;

export type StatementLine = {
  /// Stable for this line of this statement: sent back to apply it.
  hash: string;
  row: number;
  date: string;
  amount_cents: number;
  /// What the bank wrote, for the treasurer to recognise it.
  text: string;
  action: StatementAction;
  /// Whose reference it carries.
  user_id: string | null;
  name: string | null;
  /// For `confirm`: the "I've paid"s it ticks — several when one transfer
  /// paid for several people.
  payment_ids: string[];
  /// For `check`: `different_amount` or `shared_name`.
  why: string | null;
};

export type StatementPreview = {
  currency: string;
  summary: { credits: number; confirm: number; record: number; check: number; unknown: number; already: number };
  lines: StatementLine[];
};

/// `POST /clubs/{id}/statement/apply`.
export type StatementApplied = { confirmed: number; recorded: number; skipped: number };

/// The codes `preview` and `apply` refuse a file with (422).
export const STATEMENT_ERRORS = ["empty_statement", "unknown_statement", "statement_too_long"] as const;

export type StatementGroups = {
  /// Ready to apply: ticked by default.
  ticked: StatementLine[];
  /// For a person to look at.
  look: StatementLine[];
  unknown: StatementLine[];
  already: StatementLine[];
};

export function groupLines(lines: StatementLine[]): StatementGroups {
  const out: StatementGroups = { ticked: [], look: [], unknown: [], already: [] };
  for (const l of lines) {
    if (l.action === "confirm" || l.action === "record") out.ticked.push(l);
    else if (l.action === "check") out.look.push(l);
    else if (l.action === "already") out.already.push(l);
    else out.unknown.push(l);
  }
  return out;
}

/// The reference a name becomes, as the server makes it
/// (`money::reference_base`): the last word with letters in it, letters only,
/// in capitals, at most 14 of them.
export function referenceBase(name: string): string {
  const words = name.split(/\s+/).filter(Boolean).reverse();
  for (const w of words) {
    const letters = w.replace(/[^A-Za-z]/g, "").toUpperCase();
    if (letters) return letters.slice(0, 14);
  }
  return "PLAYER";
}

/// Which shared surname a bank line carries — "SHARMA", when two members are
/// Sharmas and the number that tells them apart was left off — and how many
/// members share it. Null when the line names none of them.
export function sharedSurname(text: string, names: string[]): { surname: string; count: number } | null {
  const counts = new Map<string, number>();
  for (const n of names) {
    const base = referenceBase(n);
    counts.set(base, (counts.get(base) ?? 0) + 1);
  }
  const said = ` ${text.toUpperCase().replace(/[^A-Z0-9]+/g, " ").trim()} `;
  const hits = [...counts.entries()]
    .filter(([base, count]) => count > 1 && said.includes(` ${base} `))
    .sort((a, b) => b[0].length - a[0].length);
  return hits.length > 0 ? { surname: hits[0][0], count: hits[0][1] } : null;
}

/// What somebody said they sent by bank transfer and is still waiting to be
/// checked: their own "I've paid"s, and those they made for others (a
/// parent's for their juniors, which go out under the parent's reference).
/// Zero when there are none.
export function saidCents(
  toCheck: Pick<Payment, "user_id" | "created_by" | "method" | "amount_cents">[],
  userId: string,
): number {
  return toCheck
    .filter((p) => p.method === "transfer" && (p.created_by ?? p.user_id) === userId)
    .reduce((sum, p) => sum + p.amount_cents, 0);
}
