"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  api,
  money,
  readErr,
  type Club,
  type Order,
  type OrderResponse,
  type PaymentIntent,
  type Product,
  type ProductCondition,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useRequireAuth } from "@/lib/require-auth";
import { availability, marketplace, priceLine } from "@/lib/shop";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// Statuses that still owe the club money. `draft` never reaches this screen
/// but is listed for completeness against the server's enum.
const OWED = new Set(["draft", "placed"]);

const CATEGORY_LABEL: Record<string, Key> = {
  equipment: "lc.kit_gear",
  merchandise: "lc.shoes_sportswear",
  kit_hire: "sh.cat_hire",
  food: "lc.match_day",
  drink: "lc.match_day",
  other: "sh.cat_other",
};

export default function ShopPage() {
  const t = useT();
  const authed = useRequireAuth();
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
    if (!authed) return;
    (async () => {
      try {
        const c = await api<Club[]>("GET", "/clubs");
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
        // Somebody with no orders is not an error, so this never sets one.
        setOrders(await api<Order[]>("GET", "/orders/mine").catch(() => []));
      } catch (err) {
        setError(readErr(err, t("lc.failed_to_load_clubs")));
      }
    })();
  }, [authed, t]);

  useEffect(() => {
    if (!clubId) return;
    (async () => {
      try {
        const p = await api<Product[]>("GET", `/clubs/${clubId}/products`);
        setProducts(p);
        setError(null);
      } catch (err) {
        setError(readErr(err, t("lc.failed_to_load_products")));
      }
    })();
  }, [clubId, t]);

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
      setNote(t("lc.ordered_the_club_has_it"));
    } catch (err) {
      setError(readErr(err, t("lc.could_not_place_that_order")));
    } finally {
      setPlacing(false);
    }
  };

  /// Open a payment against this order.
  ///
  /// Card capture is not wired up on either client yet — the API still returns
  /// a stub intent (`backend/payments/src/lib.rs`) — so this records that the
  /// money is on its way and leaves the club to confirm it. Saying t("lc.paid")
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
          ? t("lc.paid_thank_you")
          : t("fin.payment_opened", { amount: money(intent.amount_cents, intent.currency) })
      );
    } catch (err) {
      setError(readErr(err, t("lc.could_not_start_that_payment")));
    }
  };

  if (!authed) return <main id="main" />;

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("sh.club_shop")}</h1>
        <p>{t("sh.cricket_bats_balls_pads_shoes_clubwear")}</p>
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
            <option value="all">{t("sh.all")}</option>
            <option value="equipment">{t("sh.bats_balls_and_kit")}</option>
            <option value="merchandise">{t("sh.shoes_and_sportswear")}</option>
            <option value="kit_hire">{t("sh.hire")}</option>
            <option value="food">{t("sh.food")}</option>
            <option value="drink">{t("sh.drinks")}</option>
          </select>
        </label>
      </div>

      {error && <p className="error">{error}</p>}

      <Marketplace />

      <h2 className="shop-section">{clubs.find((c) => c.id === clubId)?.name ?? t("lc.your_club")}</h2>

      <div className="grid cards">
        {visible.map((p) => (
          <article key={p.id} className="panel">
            <div className="tag">{t(CATEGORY_LABEL[p.category])}</div>
            <h2 style={{ marginTop: 8 }}>{p.name}</h2>
            {p.description && <p className="muted">{p.description}</p>}
            <div className="row" style={{ marginTop: 12 }}>
              <span className="price">{money(p.price_cents, p.currency)}</span>
              <span className="muted">
                {p.stock == null ? t("lc.on_request") : t("sh.n_in_stock", { n: p.stock })}
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
        <p className="muted">{t("sh.no_products_in_this_category_yet")}</p>
      )}

      {lines.length > 0 && (
        <div className="panel basket">
          <div className="panel-head">
            <h2>{t("sh.your_basket")}</h2>
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
              {placing ? t("lc.placing") : `Order ${money(total, currency)}`}
            </button>
            <button className="btn" type="button" onClick={() => setBasket({})}>
              {t("sh.empty_it")}
            </button>
          </div>
          <p className="muted">
            {t("sh.the_club_sees_the_order_straight_away")}
          </p>
        </div>
      )}

      {note && <p className="notice">{note}</p>}

      {orders.length > 0 && (
        <div className="panel">
          <h2>{t("sh.what_you_have_ordered")}</h2>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>{t("sh.when")}</th><th>{t("sh.club_label")}</th><th className="n">{t("sh.total")}</th><th>{t("sh.status")}</th><th></th></tr>
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
                          {t("sh.pay_now")}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            {t("sh.owe_a_match_fee_instead_those_are_on_t")} <Link href="/events">{t("sh.fixture")}</Link>.
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
  const t = useT();
  if (soldOut) return <p className="muted">{t("sh.sold_out")}</p>;
  if (count === 0) {
    return (
      <button className="btn sm" type="button" onClick={() => onChange(1)}>
        <Icon name="plus" size={14} /> Add
      </button>
    );
  }
  return (
    <div className="stepper">
      <button type="button" onClick={() => onChange(count - 1)} aria-label={t("sh.one_fewer")}>−</button>
      <span className="num" aria-live="polite">{count}</span>
      <button type="button" onClick={() => onChange(count + 1)} aria-label={t("sh.one_more")}>+</button>
    </div>
  );
}

/// Kit for sale, from every club.
///
/// The reason the shop is more than a tea urn: a club with a spare set of pads
/// has thirty members, and a club that makes its own bats has nobody else to
/// sell them to. Money is settled in person — this is an advert with a way to
/// say t("lc.i_want_it"), not a checkout.
function Marketplace() {
  const t = useT();
  const [items, setItems] = useState<Product[]>([]);
  const [condition, setCondition] = useState<"" | ProductCondition>("");
  const [q, setQ] = useState("");
  const [applied, setApplied] = useState("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    marketplace({ condition: condition || undefined, q: applied || undefined })
      // An empty marketplace is not an error, so this never shows one.
      .then(setItems)
      .catch(() => setItems([]))
      .finally(() => setLoaded(true));
  }, [condition, applied]);

  if (loaded && items.length === 0 && !applied && !condition) {
    return (
      <section className="panel">
        <h2>{t("sh.kit_for_sale")}</h2>
        <p className="muted">
          {t("sh.nothing_listed_yet_if_club")}{" "}
          <Link href="/shop/sell">{t("sh.put_it_up")}</Link>{" "}
          {t("sh.worth_more_than_in_cupboard")}
        </p>
      </section>
    );
  }

  return (
    <section className="market">
      <div className="market-head">
        <h2>{t("sh.kit_for_sale")}</h2>
        <Link className="btn" href="/shop/sell">
          <Icon name="plus" size={16} /> {t("sh.sell_kit")}
        </Link>
      </div>

      <form
        className="market-filters"
        onSubmit={(e) => {
          e.preventDefault();
          setApplied(q.trim());
        }}
      >
        <label className="sr-only" htmlFor="mk-q">{t("sh.search_kit")}</label>
        <input
          id="mk-q"
          value={q}
          placeholder={t("sh.bat_pads_gloves")}
          onChange={(e) => setQ(e.target.value)}
        />
        <div className="chips" role="group" aria-label={t("sh.condition")}>
          {([["", "All"], ["used", t("lc.used")], ["new", "New"]] as const).map(([v, label]) => (
            <button
              key={label}
              type="button"
              className={condition === v ? "chip on" : "chip"}
              aria-pressed={condition === v}
              onClick={() => setCondition(v)}
            >
              {label}
            </button>
          ))}
        </div>
      </form>

      {items.length === 0 ? (
        <p className="muted">{t("sh.nothing_matches_that")}</p>
      ) : (
        <ul className="market-grid">
          {items.map((p) => (
            <li key={p.id} className="market-card">
              <Link href={`/shop/item/${p.id}`} className="market-link">
              {p.photos?.[0] ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.photos[0]} alt="" className="market-photo" />
              ) : (
                <span className="market-photo empty" aria-hidden="true">
                  <Icon name="camera" size={22} />
                </span>
              )}
              <div className="market-body">
                <div className="market-title">
                  <strong>{p.name}</strong>
                  {p.condition && (
                    <span className={`tag ${p.condition === "used" ? "grey" : "gold"}`}>
                      {p.condition === "used" ? t("lc.used") : t("sh.new")}
                    </span>
                  )}
                </div>
                <p className="market-price">{priceLine(p, t)}</p>
                <p className="muted">
                  {availability(p, t)}
                  {p.size && ` · ${p.size}`}
                  {p.brand && ` · ${p.brand}`}
                </p>
                {p.condition_note && <p className="market-note">{p.condition_note}</p>}
                {p.collection_note && (
                  <p className="muted market-collect">
                    <Icon name="pin" size={13} /> {p.collection_note}
                  </p>
                )}
              </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
      <p className="muted market-foot">
        {t("sh.arrange_collection_and_pay_the_club_di")}
      </p>
    </section>
  );
}
