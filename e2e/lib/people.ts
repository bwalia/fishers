import { NAMESPACE } from "./env";

/// Everybody in the run, with fixed identities: the first run registers them,
/// every run after signs the same people back in. Change E2E_NAMESPACE for a
/// completely fresh set.
export type Person = {
  key: string;
  name: string;
  email: string;
  role: "secretary" | "player";
};

const at = (local: string) => `${NAMESPACE}.${local}@fishers-e2e.test`;
const suffix = NAMESPACE === "e2e" ? "" : ` ${NAMESPACE.toUpperCase()}`;

export type ClubSpec = { name: string; secretary: Person };

export const CLUB_ONE: ClubSpec = {
  name: `E2E Club One${suffix}`,
  secretary: { key: "club1", name: "Club One Captain", email: at("club1"), role: "secretary" },
};
export const CLUB_TWO: ClubSpec = {
  name: `E2E Club Two${suffix}`,
  secretary: { key: "club2", name: "Club Two Captain", email: at("club2"), role: "secretary" },
};

export const PLAYERS: Person[] = Array.from({ length: 22 }, (_, i) => {
  const n = String(i + 1).padStart(2, "0");
  return { key: `player${n}`, name: `E2E Player ${n}`, email: at(`player${n}`), role: "player" };
});

/// Players 1–11 play for Club One, 12–22 for Club Two.
export const HOME = PLAYERS.slice(0, 11);
export const AWAY = PLAYERS.slice(11, 22);
