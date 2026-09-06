"use client";

import { useEffect, useMemo, useState } from "react";
import { api, getAccessToken, money, type Club, type Product } from "@/lib/api";

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
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load clubs");
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
        setError(err instanceof Error ? err.message : "Failed to load products");
      }
    })();
  }, [clubId]);

  const visible = useMemo(() => {
    if (filter === "all") return products;
    if (filter === "sportswear") {
      return products.filter((p) =>
        ["merchandise"].includes(p.category) &&
        /shirt|polo|hoodie|cap|trousers|shoe|spike/i.test(p.name)
      );
    }
    return products.filter((p) => p.category === filter);
  }, [products, filter]);

  return (
    <main>
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
          </article>
        ))}
      </div>

      {!error && visible.length === 0 && (
        <p className="muted">No products in this category yet.</p>
      )}
    </main>
  );
}
