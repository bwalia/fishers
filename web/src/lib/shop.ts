/// The shop, as a club uses it.
///
/// Two audiences with one set of listings: a club secretary selling last
/// season's pads or bats the club made itself, and any player in the app
/// looking for kit. Money is settled in person — a listing is an advert and a
/// reservation, not a checkout — because there is no Stripe Connect here and
/// an online payment for another club's bat would land in the platform's own
/// account.

import { api, type MarketListing, type Product, type ProductCondition } from "./api";

export const marketplace = (params: { condition?: ProductCondition; q?: string } = {}) => {
  const qs = new URLSearchParams();
  if (params.condition) qs.set("condition", params.condition);
  if (params.q) qs.set("q", params.q);
  const query = qs.toString();
  return api<Product[]>("GET", `/marketplace${query ? `?${query}` : ""}`);
};

export const clubProducts = (clubId: string) =>
  api<Product[]>("GET", `/clubs/${clubId}/products`);

/// One listing, in full — its own page, for anybody signed in.
export const marketItem = (id: string) => api<MarketListing>("GET", `/marketplace/${id}`);

/// Open a conversation with whoever is selling it.
///
/// The only way a message reaches somebody from another club: the listing is
/// the introduction. Asking twice returns the same thread rather than a second
/// one, so the button is safe to press again.
export const enquire = (productId: string) =>
  api<{ conversation_id: string; started: boolean }>(
    "POST",
    `/marketplace/${productId}/enquire`,
  );

/// Reserve it. No money changes hands here: the club is told, and the two of
/// you settle it in person.
export const reserve = (clubId: string, productId: string) =>
  api<{ order: { id: string } }>("POST", "/orders", {
    club_id: clubId,
    items: [{ product_id: productId, quantity: 1 }],
  });

export type NewListing = {
  name: string;
  description?: string | null;
  price_cents: number;
  category: string;
  stock?: number | null;
  condition?: ProductCondition | null;
  condition_note?: string | null;
  size?: string | null;
  brand?: string | null;
  listed_publicly?: boolean;
  collection_note?: string | null;
  negotiable?: boolean;
  show_contact?: boolean;
};

export const createListing = (clubId: string, body: NewListing) =>
  api<Product>("POST", `/clubs/${clubId}/products`, body);

export const updateListing = (
  clubId: string,
  productId: string,
  body: Partial<NewListing> & { active?: boolean; photos?: string[] },
) => api<Product>("PATCH", `/clubs/${clubId}/products/${productId}`, body);

/// Kit is sold in person, so "sold" is simply off the shelf. Kept rather than
/// deleted, because an order that already names it still has to read.
export const markSold = (clubId: string, productId: string) =>
  updateListing(clubId, productId, { active: false, stock: 0 });

/// "£45.00", or "£45.00 or nearest offer" when the seller will haggle. The
/// difference decides whether somebody asks at all.
export function priceLine(p: Product): string {
  const amount = price(p.price_cents, p.currency);
  return p.negotiable ? `${amount} or near offer` : amount;
}

/// "£45.00", in the currency it was listed in.
export function price(cents: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency.toUpperCase()}`;
  }
}

/// What to say about how many there are. A used bat is one of one, and "1 in
/// stock" reads like a warehouse; "on request" is for things made to order.
export function availability(p: Product): string {
  if (p.stock == null) return "On request";
  if (p.stock === 0) return "le.sold";
  if (p.stock === 1 && p.condition === "used") return "One only";
  return `${p.stock} available`;
}
