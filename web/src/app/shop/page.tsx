"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  money,
  readErr,
  type Club,
  type Order,
  type OrderResponse,
  type PaymentIntent,
  type Product,
} from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Statuses that still owe the club money. `draft` never reaches this screen
/// but is listed for completeness against the server's enum.
const OWED = new Set(["draft", "placed"]);

const CATEGORY_LABEL: Record<string, string> = {
  equipment: "Kit & gear",
  merchandise: "Shoes & sportswear",
  kit_hire: "Hire",
  food: "Match day",
  drink: "Match day",
  other: "Other",
};

export default function ShopPage() {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState<string>("");
  const [products, setProducts] = useState<Product[]>([]);
  const [filter, setFilter] = useState<string>("all");
  const [error, setError] = useState<string | null>(null);
  /// product id → how many. Kept here rather than in storage: a basket that
  /// outlives the page would go stale against a club's stock.
  const [basket, setBasket] = useState<Record<string, number>>({});
  const [orders, setOrders] = useState<Order[]>([]);
  const [placing, setPlacing] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to browse the shop.");
      return;
    }
    (async () => {
      try {
        const c = await api<Club[]>("GET", "/clubs");
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
        // Somebody with no orders is not an error, so this never sets one.
        setOrders(await api<Order[]>("GET", "/orders/mine").catch(() => []));
      } catch (err) {
        setError(readErr(err, "Failed to load clubs"));
      }
    })();
  }, []);

  useEffect(() => {
    if (!clubId) return;
    (async () => {
      try {
        const p = await api<Product[]>("GET", `/clubs/${clubId}/products`);
        setProducts(p);
        setError(null);
      } catch (err) {
        setError(readErr(err, "Failed to load products"));
      }
    })();
  }, [clubId]);

  const visible = useMemo(() => {
    if (filter === "all") return products;
    return products.filter((p) => p.category === filter);
  }, [products, filter]);

  const lines = useMemo(
    () =>
      Object.entries(basket)
        .map(([id, quantity]) => ({ product: products.find((p) => p.id === id), quantity }))
        .filter((l): l is { product: Product; quantity: number } => !!l.product),
    [basket, products]
  );
  const total = lines.reduce((n, l) => n + l.product.price_cents * l.quantity, 0);
  const currency = lines[0]?.product.currency ?? "GBP";

  const order = async () => {
    setPlacing(true);
    setError(null);
    setNote(null);
    try {
      const placed = await api<OrderResponse>("POST", "/orders", {
        club_id: clubId,
        items: lines.map((l) => ({ product_id: l.product.id, quantity: l.quantity })),
      });
      setBasket({});
      setOrders((prev) => [placed.order, ...prev]);
      setNote("Ordered. The club has it.");
    } catch (err) {
      setError(readErr(err, "Could not place that order"));
    } finally {
      setPlacing(false);
    }
  };

  /// Open a payment against this order.
  ///
  /// Card capture is not wired up on either client yet — the API still returns
  /// a stub intent (`backend/payments/src/lib.rs`) — so this records that the
  /// money is on its way and leaves the club to confirm it. Saying "Paid"
  /// here would be a lie, and the club would be the one chasing it.
  const pay = async (o: Order) => {
    setError(null);
    setNote(null);
    try {
      const intent = await api<PaymentIntent>("POST", "/payments/intent", {
        order_id: o.id,
        amount_cents: o.total_amount_cents,
        currency: o.currency,
      });
      setNote(
        intent.status === "succeeded"
          ? "Paid — thank you."
          : `Payment opened for ${money(intent.amount_cents, intent.currency)}. Your club confirms it once it clears; you can still settle up at the ground.`
      );
    } catch (err) {
      setError(readErr(err, "Could not start that payment"));
    }
  };

  return (
    <main id="main">
      <section className="hero">
        <h1>Club shop</h1>
        <p>Cricket bats, balls, pads, shoes, clubwear and hire — browse by club.</p>
      </section>

      <div className="select-row">
        <label>
          Club{" "}
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Category{" "}
          <select value={filter} onChange={(e) => setFilter(e.target.value)}>
            <option value="all">All</option>
            <option value="equipment">Bats, balls &amp; kit</option>
            <option value="merchandise">Shoes &amp; sportswear</option>
            <option value="kit_hire">Hire</option>
            <option value="food">Food</option>
            <option value="drink">Drinks</option>
          </select>
        </label>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="grid cards">
        {visible.map((p) => (
          <article key={p.id} className="panel">
            <div className="tag">{CATEGORY_LABEL[p.category] ?? p.category}</div>
            <h2 style={{ marginTop: 8 }}>{p.name}</h2>
            {p.description && <p className="muted">{p.description}</p>}
            <div className="row" style={{ marginTop: 12 }}>
              <span className="price">{money(p.price_cents, p.currency)}</span>
              <span className="muted">
                {p.stock == null ? "On request" : `${p.stock} in stock`}
              </span>
            </div>
            <Stepper
              count={basket[p.id] ?? 0}
              soldOut={p.stock === 0}
              onChange={(n) => setBasket((b) => {
                const next = { ...b };
                if (n <= 0) delete next[p.id];
                else next[p.id] = n;
                return next;
              })}
            />
          </article>
        ))}
      </div>

      {!error && visible.length === 0 && (
        <p className="muted">No products in this category yet.</p>
      )}

      {lines.length > 0 && (
        <div className="panel basket">
          <div className="panel-head">
            <h2>Your basket</h2>
            <span className="tag">{money(total, currency)}</span>
          </div>
          <ul className="basket-lines">
            {lines.map(({ product, quantity }) => (
              <li key={product.id}>
                <span>{quantity} × {product.name}</span>
                <span className="num">{money(product.price_cents * quantity, product.currency)}</span>
              </li>
            ))}
          </ul>
          <div className="field-row" style={{ marginTop: "var(--s4)" }}>
            <button className="btn primary lg" type="button" disabled={placing} onClick={order}>
              {placing ? "Placing…" : `Order ${money(total, currency)}`}
            </button>
            <button className="btn" type="button" onClick={() => setBasket({})}>
              Empty it
            </button>
          </div>
          <p className="muted">
            The club sees the order straight away. You can pay now or at the ground.
          </p>
        </div>
      )}

      {note && <p className="notice">{note}</p>}

      {orders.length > 0 && (
        <div className="panel">
          <h2>What you have ordered</h2>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>When</th><th>Club</th><th className="n">Total</th><th>Status</th><th></th></tr>
              </thead>
              <tbody>
                {orders.map((o) => (
                  <tr key={o.id}>
                    <td className="num">
                      {new Date(o.created_at).toLocaleDateString("en-GB", {
                        day: "numeric", month: "short",
                      })}
                    </td>
                    <td>{clubs.find((c) => c.id === o.club_id)?.name ?? "—"}</td>
                    <td className="n num">{money(o.total_amount_cents, o.currency)}</td>
                    <td>
                      <span className={`tag ${o.status === "paid" ? "" : "grey"}`}>{o.status}</span>
                    </td>
                    <td className="n">
                      {OWED.has(o.status) && (
                        <button className="btn ghost sm" type="button" onClick={() => pay(o)}>
                          Pay now
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            Owe a match fee instead? Those are on the <Link href="/events">fixture</Link>.
          </p>
        </div>
      )}
    </main>
  );
}

/// How many of this one. A stepper rather than a number field: on a phone at a
/// ground, typing "2" into a spinner is three taps and a keyboard.
function Stepper({
  count,
  soldOut,
  onChange,
}: {
  count: number;
  soldOut: boolean;
  onChange: (n: number) => void;
}) {
  if (soldOut) return <p className="muted">Sold out</p>;
  if (count === 0) {
    return (
      <button className="btn sm" type="button" onClick={() => onChange(1)}>
        <Icon name="plus" size={14} /> Add
      </button>
    );
  }
  return (
    <div className="stepper">
      <button type="button" onClick={() => onChange(count - 1)} aria-label="One fewer">−</button>
      <span className="num" aria-live="polite">{count}</span>
      <button type="button" onClick={() => onChange(count + 1)} aria-label="One more">+</button>
    </div>
  );
}
