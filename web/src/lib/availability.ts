/// Your calendar (`backend/domain/src/availability.rs`).
///
/// A standing signal, not an answer to a fixture: "I'm generally around on
/// Sundays" rather than "yes to this match". A captain reads both, and the
/// direct RSVP wins where they disagree.

export type AvailabilityStatus = "available" | "maybe" | "unavailable";

export type Availability = {
  id: string;
  user_id: string;
  /// `YYYY-MM-DD`, the server's own calendar day — never a timestamp, so it
  /// cannot slide across a date boundary in another timezone.
  date: string;
  status: AvailabilityStatus;
  note: string | null;
  recurrence_rule: string | null;
};

export const AVAILABILITY_LABEL: Record<AvailabilityStatus, string> = {
  available: "Available",
  maybe: "Maybe",
  unavailable: "Not available",
};

/// One tap moves a day on. Matches the phone exactly, so a player who sets
/// their calendar on the app and checks it on a laptop is not surprised.
export function nextStatus(current: AvailabilityStatus | undefined): AvailabilityStatus {
  if (!current) return "available";
  return current === "available" ? "maybe" : current === "maybe" ? "unavailable" : "available";
}

/// `YYYY-MM-DD` for a local date.
///
/// `toISOString()` would be wrong: it converts to UTC first, so the evening of
/// the 5th in London becomes the 5th, but the evening of the 5th in Sydney
/// becomes the 4th. The calendar day somebody tapped is the local one.
export function dayKey(date: Date): string {
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

/// The cells of a month grid, Monday first, padded so the 1st lands under the
/// right weekday. `null` is a leading or trailing blank.
export function monthGrid(month: Date): (Date | null)[] {
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  // getDay() is Sunday-first; British calendars start on Monday.
  const lead = (first.getDay() + 6) % 7;

  const cells: (Date | null)[] = Array(lead).fill(null);
  for (let d = 1; d <= days; d++) {
    cells.push(new Date(month.getFullYear(), month.getMonth(), d));
  }
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

/// Every date in the month falling on this weekday. 0 is Monday.
export function weekdaysIn(month: Date, weekday: number): Date[] {
  return monthGrid(month)
    .filter((d): d is Date => d !== null && (d.getDay() + 6) % 7 === weekday);
}

export const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
