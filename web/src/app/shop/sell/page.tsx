"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Icon } from "@/components/Icon";
import { api, readErr, upload, type Club, type Product, type ProductCondition } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import {
  availability,
  clubProducts,
  createListing,
  markSold,
  price,
  updateListing,
} from "@/lib/shop";

/// Where a club puts its kit up for sale.
///
/// Two things a club actually has: last season's pads now that the new ones
/// arrived, and — for the clubs that make their own — bats nobody outside the
/// club has ever seen. Both are the same listing with a different word on it.
///
/// Money is settled in person. A listing is an advert and a reservation, not a
/// checkout: there is no Stripe Connect here, so an online payment for another
/// club's bat would land in the platform's account and leave us owing them.
export default function SellPage() {
  const authed = useRequireAuth();
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [products, setProducts] = useState<Product[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (!authed) return;
    api<Club[]>("GET", "/clubs")
      .then((c) => {
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
      })
      .catch((err) => setError(readErr(err, "Could not load your clubs")));
  }, [authed]);

  const load = useCallback(async () => {
    if (!clubId) return;
    try {
      setProducts(await clubProducts(clubId));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this club's listings"));
    }
  }, [clubId]);

  useEffect(() => {
    load();
  }, [load]);

  const kit = useMemo(
    () => products.filter((p) => p.category === "equipment" || p.category === "merchandise"),
    [products],
  );

  if (!authed) return <main id="main" />;

  return (
    <main id="main" className="sell">
      <header className="sell-head">
        <div>
          <h1>Sell kit</h1>
          <p className="muted">
            <Link href="/shop">← Shop</Link> · Last season&apos;s pads, or bats you made
            yourself. Buyers arrange collection and pay you directly.
          </p>
        </div>
        {clubs.length > 1 && (
          <label className="sell-club">
            <span className="sr-only">Club</span>
            <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
              {clubs.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
        )}
      </header>

      {error && <p className="error">{error}</p>}

      {!adding ? (
        <button className="btn primary" onClick={() => setAdding(true)} disabled={!clubId}>
          <Icon name="plus" size={16} /> List something
        </button>
      ) : (
        <ListingForm
          clubId={clubId}
          onDone={() => {
            setAdding(false);
            load();
          }}
          onCancel={() => setAdding(false)}
        />
      )}

      <section className="panel">
        <h2>On sale now</h2>
        {kit.length === 0 ? (
          <p className="muted">
            Nothing listed yet. A set of pads the club has replaced is worth more to somebody
            else than it is in the cupboard.
          </p>
        ) : (
          <ul className="sell-list">
            {kit.map((p) => (
              <Listing key={p.id} clubId={clubId} product={p} onChanged={load} />
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

function Listing({
  clubId,
  product,
  onChanged,
}: {
  clubId: string;
  product: Product;
  onChanged: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onChanged();
    } catch (err) {
      setError(readErr(err, "That did not save"));
    } finally {
      setBusy(false);
    }
  };

  const sold = product.stock === 0;

  return (
    <li className={`sell-item${sold ? " sold" : ""}`}>
      {product.photos?.[0] ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={product.photos[0]} alt="" className="sell-thumb" />
      ) : (
        <span className="sell-thumb empty" aria-hidden="true">
          <Icon name="camera" size={20} />
        </span>
      )}

      <div className="sell-body">
        <div className="sell-title">
          <strong>{product.name}</strong>
          {product.condition && (
            <span className={`tag ${product.condition === "used" ? "grey" : "gold"}`}>
              {product.condition === "used" ? "Used" : "New"}
            </span>
          )}
          {!product.listed_publicly && (
            <span className="tag" title="Only your club can see this">Club only</span>
          )}
        </div>
        <p className="muted">
          {price(product.price_cents, product.currency)} · {availability(product)}
          {product.size && ` · ${product.size}`}
          {product.brand && ` · ${product.brand}`}
        </p>
        {product.condition_note && <p className="sell-note">{product.condition_note}</p>}
        {error && <p className="error">{error}</p>}
      </div>

      <div className="sell-actions">
        <PhotoButton clubId={clubId} product={product} onDone={onChanged} />
        {!sold && (
          <button className="btn" disabled={busy} onClick={() => act(() => markSold(clubId, product.id))}>
            Mark sold
          </button>
        )}
        <button
          className="btn"
          disabled={busy}
          onClick={() =>
            act(() =>
              updateListing(clubId, product.id, { listed_publicly: !product.listed_publicly }),
            )
          }
        >
          {product.listed_publicly ? "Hide from other clubs" : "Show to other clubs"}
        </button>
      </div>
    </li>
  );
}

/// Photographs, up to six. A second-hand bat with no picture does not sell.
function PhotoButton({
  clubId,
  product,
  onDone,
}: {
  clubId: string;
  product: Product;
  onDone: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const count = product.photos?.length ?? 0;

  // `upload`, not `api`: api() sets Content-Type: application/json, and a
  // multipart body needs the browser to set its own boundary. Sending JSON's
  // header with a FormData body produces a request the server cannot parse.
  const send = async (file: File) => {
    setBusy(true);
    try {
      await upload<Product>(`/clubs/${clubId}/products/${product.id}/photo`, file);
      onDone();
    } finally {
      setBusy(false);
    }
  };

  return (
    <label className={`btn${busy ? " busy" : ""}`}>
      <Icon name="camera" size={16} />
      {busy ? "Adding…" : count === 0 ? "Add a photo" : `Photos (${count})`}
      <input
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="sr-only"
        disabled={busy || count >= 6}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) send(f);
          e.target.value = "";
        }}
      />
    </label>
  );
}

const CONDITIONS: { value: ProductCondition; label: string; hint: string }[] = [
  { value: "used", label: "Used", hint: "The club has replaced it and this one still has life in it." },
  { value: "new", label: "New", hint: "Unused — bought in or made by the club." },
];

function ListingForm({
  clubId,
  onDone,
  onCancel,
}: {
  clubId: string;
  onDone: () => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const [condition, setCondition] = useState<ProductCondition>("used");
  const [pounds, setPounds] = useState("");
  const [stock, setStock] = useState("1");
  const [size, setSize] = useState("");
  const [brand, setBrand] = useState("");
  const [note, setNote] = useState("");
  const [collection, setCollection] = useState("");
  const [publicly, setPublicly] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amount = Math.round(parseFloat(pounds) * 100);
    if (!Number.isFinite(amount) || amount < 0) {
      return setError("Put a price in, even if it is 0 for a giveaway");
    }
    setBusy(true);
    setError(null);
    try {
      await createListing(clubId, {
        name: name.trim(),
        price_cents: amount,
        category: "equipment",
        stock: stock === "" ? null : Number(stock),
        condition,
        condition_note: note.trim() || null,
        size: size.trim() || null,
        brand: brand.trim() || null,
        listed_publicly: publicly,
        collection_note: collection.trim() || null,
      });
      onDone();
    } catch (err) {
      setError(readErr(err, "Could not list that"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="panel sell-form" onSubmit={submit}>
      <h2>List something</h2>

      <label htmlFor="sl-name">What is it</label>
      <input
        id="sl-name"
        required
        maxLength={160}
        placeholder="Gray-Nicolls Predator bat"
        value={name}
        onChange={(e) => setName(e.target.value)}
      />

      <fieldset className="sell-condition">
        <legend>Condition</legend>
        {CONDITIONS.map((c) => (
          <label key={c.value} className={condition === c.value ? "on" : undefined}>
            <input
              type="radio"
              name="condition"
              value={c.value}
              checked={condition === c.value}
              onChange={() => setCondition(c.value)}
            />
            <strong>{c.label}</strong>
            <span className="muted">{c.hint}</span>
          </label>
        ))}
      </fieldset>

      <div className="sell-row">
        <div>
          <label htmlFor="sl-price">Price</label>
          <input
            id="sl-price"
            required
            inputMode="decimal"
            placeholder="45.00"
            value={pounds}
            onChange={(e) => setPounds(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="sl-stock">How many</label>
          <input
            id="sl-stock"
            inputMode="numeric"
            value={stock}
            onChange={(e) => setStock(e.target.value)}
          />
          <small className="muted">One, for a single second-hand item. Blank means made to order.</small>
        </div>
      </div>

      <div className="sell-row">
        <div>
          <label htmlFor="sl-size">Size</label>
          <input
            id="sl-size"
            placeholder="Short Handle"
            value={size}
            onChange={(e) => setSize(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="sl-brand">Make</label>
          <input
            id="sl-brand"
            placeholder="Gray-Nicolls"
            value={brand}
            onChange={(e) => setBrand(e.target.value)}
          />
        </div>
      </div>

      <label htmlFor="sl-note">
        What state is it in? <span className="muted">Be honest — it saves a wasted journey.</span>
      </label>
      <textarea
        id="sl-note"
        rows={2}
        maxLength={500}
        placeholder="Light wear on the toe, no cracks. Knocked in, used one season."
        value={note}
        onChange={(e) => setNote(e.target.value)}
      />

      <label htmlFor="sl-collect">Collection</label>
      <input
        id="sl-collect"
        maxLength={300}
        placeholder="From the clubhouse any Tuesday evening"
        value={collection}
        onChange={(e) => setCollection(e.target.value)}
      />

      <label className="switch">
        <input type="checkbox" checked={publicly} onChange={(e) => setPublicly(e.target.checked)} />
        <span>Show it to players at other clubs</span>
      </label>

      {error && <p className="error">{error}</p>}
      <div className="sell-form-actions">
        <button className="btn primary" disabled={busy}>
          {busy ? "Listing…" : "List it"}
        </button>
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
      </div>
      <p className="muted">
        You can add photographs once it is listed. Nobody buys a bat they cannot see.
      </p>
    </form>
  );
}
