/// Umpiring, as the API hands it over.
///
/// Club cricket umpires itself, and the person who does it every week has had
/// nothing to show for it. These are that record.

import { api } from "./api";

export type UmpireReview = {
  id: string;
  match_id: string;
  /// One to five.
  rating: number;
  comment: string | null;
  created_at: string;
  reviewer_name: string;
  reviewer_avatar_url: string | null;
  match_title: string;
  played_on: string | null;
};

export type UmpireProfile = {
  user_id: string;
  /// Whether they have said they will stand — not the same as having stood.
  umpires: boolean;
  note: string | null;
  matches: number;
  /// `null` until somebody reviews. Not 0, which reads as "rated, badly".
  rating_average: number | null;
  rating_count: number;
  /// How the ratings fall, one to five.
  rating_breakdown: [number, number, number, number, number];
  reviews: UmpireReview[];
};

export type MatchUmpire = {
  user_id: string;
  name: string;
  avatar_url: string | null;
  my_rating: number | null;
  my_comment: string | null;
};

export type AvailableUmpire = {
  user_id: string;
  name: string;
  avatar_url: string | null;
  note: string | null;
  matches: number;
  rating_average: number | null;
  rating_count: number;
};

/// A finished match whose umpiring this player has not had their say on.
export type PendingUmpireReview = {
  match_id: string;
  match_title: string;
  played_on: string | null;
  /// Only the umpires they have not already rated.
  umpires: MatchUmpire[];
};

export const myUmpiring = () => api<UmpireProfile>("GET", "/me/umpiring");

export const pendingUmpireReviews = () =>
  api<PendingUmpireReview[]>("GET", "/me/umpiring/pending");

export const umpiringOf = (userId: string) =>
  api<UmpireProfile>("GET", `/users/${userId}/umpiring`);

export const setUmpiring = (body: { umpires?: boolean; note?: string | null }) =>
  api<UmpireProfile>("PATCH", "/me/umpiring", body);

export const matchUmpires = (matchId: string) =>
  api<MatchUmpire[]>("GET", `/cricket/matches/${matchId}/umpires`);

export const reviewUmpire = (
  matchId: string,
  umpireId: string,
  body: { rating: number; comment?: string | null },
) => api<UmpireReview>("PUT", `/cricket/matches/${matchId}/umpires/${umpireId}/review`, body);

export const withdrawReview = (matchId: string, umpireId: string) =>
  api<{ withdrawn: boolean }>(
    "DELETE",
    `/cricket/matches/${matchId}/umpires/${umpireId}/review`,
  );

export const clubUmpires = (clubId: string) =>
  api<AvailableUmpire[]>("GET", `/clubs/${clubId}/umpires`);

/// "4.3 from 12" — or what to say instead when nobody has rated them yet.
export function ratingLabel(p: {
  rating_average: number | null;
  rating_count: number;
}): string {
  if (p.rating_average === null || p.rating_count === 0) return "No ratings yet";
  return `${p.rating_average.toFixed(1)} from ${p.rating_count} ${
    p.rating_count === 1 ? "review" : "reviews"
  }`;
}
