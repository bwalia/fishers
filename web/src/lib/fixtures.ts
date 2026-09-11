/// Your fixtures with your answer to each (`GET /events/mine`,
/// `backend/db/src/repos/events.rs` MyFixture).
///
/// The fixtures list and the availability calendar both read this, so they
/// cannot disagree about whether you are playing.

import { api } from "@/lib/api";
import { dayKey } from "@/lib/availability";

export type Answer = "going" | "maybe" | "not_going";

export type MyFixture = {
  event_id: string;
  title: string;
  sport: string;
  event_subtype: string;
  status: string;
  start_at: string;
  end_at: string;
  club_id: string;
  club_name: string;
  opponent_club_id: string | null;
  opponent_club_name: string | null;
  venue_name: string | null;
  match_id: string | null;
  my_answer: Answer | null;
  fee_amount_cents: number | null;
  ticket_price_cents: number | null;
};

export const ANSWERS: { value: Answer; label: string; said: string }[] = [
  { value: "going", label: "Available", said: "You're available" },
  { value: "maybe", label: "Maybe", said: "You said maybe" },
  { value: "not_going", label: "Can't play", said: "You can't play" },
];

export function saidLabel(answer: Answer | null): string {
  return ANSWERS.find((a) => a.value === answer)?.said ?? "Not answered yet";
}

export function myFixtures(from: Date, to: Date): Promise<MyFixture[]> {
  const q = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  return api<MyFixture[]>("GET", `/events/mine?${q}`);
}

export function answerFixture(eventId: string, status: Answer): Promise<unknown> {
  return api("POST", `/events/${eventId}/rsvp`, { status });
}

/// Fixtures by the local calendar day they start on, in order.
export function byDay(fixtures: MyFixture[]): Map<string, MyFixture[]> {
  const days = new Map<string, MyFixture[]>();
  for (const f of fixtures) {
    const key = dayKey(new Date(f.start_at));
    days.set(key, [...(days.get(key) ?? []), f]);
  }
  return days;
}

/// Two fixtures you have said yes to that are on at the same time.
export function clashes(fixtures: MyFixture[]): Set<string> {
  const yes = fixtures.filter((f) => f.my_answer === "going");
  const out = new Set<string>();
  for (const a of yes)
    for (const b of yes)
      if (a !== b && Date.parse(a.start_at) < Date.parse(b.end_at) && Date.parse(b.start_at) < Date.parse(a.end_at))
        out.add(a.event_id);
  return out;
}

export function timeOf(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function dayTitle(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  const today = dayKey(new Date());
  const tomorrow = dayKey(new Date(Date.now() + 864e5));
  const long = date.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
  return key === today ? `Today · ${long}` : key === tomorrow ? `Tomorrow · ${long}` : long;
}
