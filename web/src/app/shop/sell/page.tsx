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
  priceLine,
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
type Shelf = "on_sale" | "club_only" | "sold";

/// Which shelf a listing is on, in the words a seller would use.
function shelfOf(p: Product): Shelf {
  if (p.active === false || p.stock === 0) return "sold";
  return p.listed_publicly ? "on_sale" : "club_only";
}

const SHELVES: { key: Shelf; label: string; blurb: string }[] = [
  { key: "on_sale", label: "On sale", blurb: "Anybody in the app can see these and ask for them." },
  { key: "club_only", label: "Your club only", blurb: "Listed, but nobody outside your club can see them." },
  { key: "sold", label: "Sold or taken down", blurb: "Off the marketplace. You can put one back on sale." },
];

/// Everything this club has for sale, and how to put something new up.
///
/// Written for a club secretary who is not necessarily comfortable with
/// computers: the page says what will happen before it happens, every listing
/// says plainly which shelf it is on, and no button is a dead end.
export default function SellPage() {
  const authed = useRequireAuth();
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [products, setProducts] = useState<Product[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  /// The one just listed, so the page can say "that worked, now add photos"
  /// rather than dropping somebody back on a list to find it themselves.
  const [justListed, setJustListed] = useState<string | null>(null);

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
  const shelves = useMemo(() => {
    const out: Record<Shelf, Product[]> = { on_sale: [], club_only: [], sold: [] };
    for (const p of kit) out[shelfOf(p)].push(p);
    return out;
  }, [kit]);

  if (!authed) return <main id="main" />;

  const fresh = justListed ? kit.find((p) => p.id === justListed) : undefined;

  return (
    <main id="main" className="sell">
      <header className="sell-head">
        <div>
          <h1>Your listings</h1>
          <p className="muted">
            <Link href="/shop">← Shop</Link> · Kit your club is selling, new or second-hand.
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

      {/* Said once, at the top, before anybody has to guess. Four steps, no
          jargon, and it says plainly that no money moves through the app —
          which is the question a cautious person asks first. */}
      <section className="how">
        <h2>How selling works</h2>
        <ol>
          <li><strong>Put it up.</strong> Say what it is, what state it is in, and what you want for it.</li>
          <li><strong>Add photographs.</strong> Up to six. Nobody buys a bat they cannot see.</li>
          <li><strong>Somebody asks for it.</strong> You get a message, and it comes off the marketplace so nobody else asks for the same one.</li>
          <li><strong>They collect and pay you.</strong> Cash or transfer, directly to the club. No money goes through this app.</li>
        </ol>
      </section>

      {fresh && (
        <section className="panel done-panel">
          <h2><Icon name="check" size={18} /> &ldquo;{fresh.name}&rdquo; is up</h2>
          <p className="muted">
            {(fresh.photos?.length ?? 0) === 0
              ? "It has no photographs yet, and a listing without one is usually passed over. Add some below — it takes a moment."
              : "It is on the marketplace and anybody in the app can ask for it."}
          </p>
          <div className="done-actions">
            <Link className="btn" href={`/shop/item/${fresh.id}`}>See how buyers see it</Link>
            <button className="btn" onClick={() => setJustListed(null)}>Done</button>
          </div>
        </section>
      )}

      {!adding ? (
        <div className="sell-cta">
          <button className="btn primary" onClick={() => setAdding(true)} disabled={!clubId}>
            <Icon name="plus" size={16} /> List something for sale
          </button>
          <span className="muted">Takes a minute. You can change or remove it afterwards.</span>
        </div>
      ) : (
        <ListingForm
          clubId={clubId}
          onDone={(created) => {
            setAdding(false);
            setJustListed(created);
            load();
          }}
          onCancel={() => setAdding(false)}
        />
      )}

      {kit.length === 0 ? (
        <section className="panel">
          <h2>Nothing up yet</h2>
          <p className="muted">
            A set of pads the club has replaced is worth more to somebody else than it is in the
            cupboard. So is a bat you made.
          </p>
        </section>
      ) : (
        SHELVES.map(({ key, label, blurb }) => {
          const items = shelves[key];
          if (items.length === 0) return null;
          return (
            <section className="panel" key={key}>
              <div className="shelf-head">
                <h2>{label}</h2>
                <span className="tag grey">{items.length}</span>
              </div>
              <p className="muted">{blurb}</p>
              <ul className="sell-list">
                {items.map((p) => (
                  <Listing key={p.id} clubId={clubId} product={p} onChanged={load} />
                ))}
              </ul>
            </section>
          );
        })
      )}
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
  const [editing, setEditing] = useState(false);

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

  const shelf = shelfOf(product);
  const photos = product.photos?.length ?? 0;

  return (
    <li className={`sell-item${shelf === "sold" ? " sold" : ""}`}>
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
        </div>

        <p className="muted">
          {priceLine(product)} · {availability(product)}
          {product.size && ` · ${product.size}`}
          {product.brand && ` · ${product.brand}`}
        </p>

        {/* Says what is true of this one right now, in words rather than a
            colour somebody has to learn. */}
        <p className="sell-state">
          {shelf === "sold" && "Off the marketplace. Nobody can ask for it."}
          {shelf === "club_only" && "Only your own club can see this."}
          {shelf === "on_sale" && photos === 0 && (
            <span className="warn">
              <Icon name="help" size={14} /> No photographs — most people scroll past a listing
              without one.
            </span>
          )}
          {shelf === "on_sale" && photos > 0 && `On the marketplace with ${photos} photograph${photos === 1 ? "" : "s"}.`}
        </p>

        {error && <p className="error">{error}</p>}
        {shelf !== "sold" && <Photos clubId={clubId} product={product} onDone={onChanged} />}
        {editing && (
          <QuickEdit
            clubId={clubId}
            product={product}
            onDone={() => {
              setEditing(false);
              onChanged();
            }}
            onCancel={() => setEditing(false)}
          />
        )}
      </div>

      <div className="sell-actions">
        <Link className="btn" href={`/shop/item/${product.id}`}>View</Link>
        {!editing && shelf !== "sold" && (
          <button className="btn" onClick={() => setEditing(true)} disabled={busy}>
            Change price
          </button>
        )}
        {shelf === "sold" ? (
          // Never a dead end: something marked sold by mistake, or returned,
          // goes back up without being typed in again.
          <button
            className="btn"
            disabled={busy}
            onClick={() => act(() => updateListing(clubId, product.id, { active: true, stock: 1 }))}
          >
            Put back on sale
          </button>
        ) : (
          <button className="btn" disabled={busy} onClick={() => act(() => markSold(clubId, product.id))}>
            Mark as sold
          </button>
        )}
        {shelf !== "sold" && (
          <button
            className="btn"
            disabled={busy}
            onClick={() =>
              act(() => updateListing(clubId, product.id, { listed_publicly: !product.listed_publicly }))
            }
          >
            {product.listed_publicly ? "Hide from other clubs" : "Show to other clubs"}
          </button>
        )}
      </div>
    </li>
  );
}

/// Changing the price without retyping the listing — the commonest edit by
/// far, and the one that turns a listing nobody wanted into one somebody does.
function QuickEdit({
  clubId,
  product,
  onDone,
  onCancel,
}: {
  clubId: string;
  product: Product;
  onDone: () => void;
  onCancel: () => void;
}) {
  const [pounds, setPounds] = useState((product.price_cents / 100).toFixed(2));
  const [negotiable, setNegotiable] = useState(!!product.negotiable);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    const amount = Math.round(parseFloat(pounds) * 100);
    if (!Number.isFinite(amount) || amount < 0) return setError("That is not a price");
    setBusy(true);
    setError(null);
    try {
      await updateListing(clubId, product.id, { price_cents: amount, negotiable });
      onDone();
    } catch (err) {
      setError(readErr(err, "Could not change the price"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="quick-edit" onSubmit={save}>
      <div className="field field-price">
        <label htmlFor={`qe-${product.id}`}>New price</label>
        <div className="input-prefix">
          <span aria-hidden="true">£</span>
          <input
            id={`qe-${product.id}`}
            inputMode="decimal"
            value={pounds}
            onChange={(e) => setPounds(e.target.value)}
          />
        </div>
      </div>
      <label className="switch">
        <input type="checkbox" checked={negotiable} onChange={(e) => setNegotiable(e.target.checked)} />
        <span>Open to offers</span>
      </label>
      <button className="btn primary" disabled={busy}>{busy ? "Saving…" : "Save"}</button>
      <button type="button" className="btn" onClick={onCancel}>Cancel</button>
      {error && <p className="error">{error}</p>}
    </form>
  );
}

/// Photographs — several at once, and a way to take one back off.
///
/// A secretary standing in a clubhouse photographs a bat from four angles and
/// then wants all four up, not four trips through a file picker. Six is the
/// ceiling: the whole thing, the face, the toe, the grip, and two for whatever
/// is wrong with it.
function Photos({
  clubId,
  product,
  onDone,
}: {
  clubId: string;
  product: Product;
  onDone: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const photos = product.photos ?? [];
  const room = MAX_PHOTOS - photos.length;

  const add = async (files: FileList) => {
    // Sequential, not Promise.all: each upload reads the current photo list
    // and appends to it, so firing six at once would have five of them
    // appending to the same stale array and only one surviving.
    const chosen = Array.from(files).slice(0, room);
    setError(null);
    for (const [i, file] of chosen.entries()) {
      setBusy(`Adding ${i + 1} of ${chosen.length}…`);
      try {
        await upload<Product>(`/clubs/${clubId}/products/${product.id}/photo`, file);
      } catch (err) {
        setError(readErr(err, `Could not add ${file.name}`));
        break;
      }
    }
    setBusy(null);
    onDone();
  };

  const remove = async (url: string) => {
    setBusy("Removing…");
    setError(null);
    try {
      await updateListing(clubId, product.id, { photos: photos.filter((p) => p !== url) });
      onDone();
    } catch (err) {
      setError(readErr(err, "Could not remove that photograph"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="photos">
      {photos.length > 0 && (
        <ul className="photos-strip">
          {photos.map((url, i) => (
            <li key={url}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={url} alt={`Photograph ${i + 1}`} />
              {i === 0 && <span className="photos-first">Cover</span>}
              <button
                type="button"
                className="photos-remove"
                aria-label={`Remove photograph ${i + 1}`}
                disabled={busy !== null}
                onClick={() => remove(url)}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}

      {/* A button that cannot be pressed is worse than no button: it reads as
          a dead end. When the listing is full, say so instead. */}
      {room > 0 ? (
        <label className={`btn${busy ? " busy" : ""}`}>
          <Icon name="camera" size={16} />
          {busy ?? (photos.length === 0 ? "Add photographs" : `Add another (room for ${room})`)}
          <input
            type="file"
            accept="image/jpeg,image/png,image/webp"
            multiple
            className="sr-only"
            disabled={busy !== null}
            onChange={(e) => {
              if (e.target.files?.length) add(e.target.files);
              e.target.value = "";
            }}
          />
        </label>
      ) : (
        <small className="muted">
          All six photographs added — that is the most a listing can hold. Remove one with the ×
          if you want to swap it.
        </small>
      )}
      {photos.length > 0 && room > 0 && (
        <small className="muted">
          You can pick several at once. The first one is what buyers see in the list.
        </small>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}

const MAX_PHOTOS = 6;

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
  /// Hands back the id, so the page can say "that one is up" and point at it
  /// rather than leaving somebody to find it in a list.
  onDone: (createdId: string) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("equipment");
  const [condition, setCondition] = useState<ProductCondition>("used");
  const [pounds, setPounds] = useState("");
  const [negotiable, setNegotiable] = useState(true);
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
      const created = await createListing(clubId, {
        name: name.trim(),
        description: description.trim() || null,
        price_cents: amount,
        category,
        stock: stock === "" ? null : Number(stock),
        condition,
        condition_note: note.trim() || null,
        size: size.trim() || null,
        brand: brand.trim() || null,
        listed_publicly: publicly,
        collection_note: collection.trim() || null,
        negotiable,
      });
      onDone(created.id);
    } catch (err) {
      setError(readErr(err, "Could not list that"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="listing">
      <form className="listing-form" onSubmit={submit}>
        <section className="listing-group">
          <h2>What it is</h2>

          <div className="field">
            <label htmlFor="sl-name">Name</label>
            <input
              id="sl-name"
              required
              maxLength={160}
              placeholder="Gray-Nicolls Predator bat"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>

          <div className="field">
            <label htmlFor="sl-desc">Description</label>
            <textarea
              id="sl-desc"
              rows={4}
              placeholder="Kashmir willow, knocked in and used for one season by our 2nd XI. Good middle, no repairs. Replaced because we moved to English willow."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
            <small>What it is, how it played, why you are selling it.</small>
          </div>

          <div className="field field-narrow">
            <label htmlFor="sl-cat">Kind</label>
            <select id="sl-cat" value={category} onChange={(e) => setCategory(e.target.value)}>
              <option value="equipment">Bats, balls &amp; kit</option>
              <option value="merchandise">Shoes &amp; sportswear</option>
            </select>
            <small>Only kit is shown to other clubs.</small>
          </div>
        </section>

        <section className="listing-group">
          <h2>Condition and price</h2>

          <fieldset className="choice">
            <legend className="sr-only">Condition</legend>
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
                <span>{c.hint}</span>
              </label>
            ))}
          </fieldset>

          <div className="field-row">
            <div className="field field-price">
              <label htmlFor="sl-price">Price</label>
              <div className="input-prefix">
                <span aria-hidden="true">£</span>
                <input
                  id="sl-price"
                  required
                  inputMode="decimal"
                  placeholder="45.00"
                  value={pounds}
                  onChange={(e) => setPounds(e.target.value)}
                />
              </div>
            </div>
            <div className="field field-qty">
              <label htmlFor="sl-stock">How many</label>
              <input
                id="sl-stock"
                inputMode="numeric"
                value={stock}
                onChange={(e) => setStock(e.target.value)}
              />
              <small>Blank means made to order.</small>
            </div>
            <label className="switch listing-switch">
              <input
                type="checkbox"
                checked={negotiable}
                onChange={(e) => setNegotiable(e.target.checked)}
              />
              <span>Open to offers</span>
            </label>
          </div>
        </section>

        <section className="listing-group">
          <h2>The details that sell it</h2>

          <div className="field-row">
            <div className="field">
              <label htmlFor="sl-size">Size</label>
              <input id="sl-size" placeholder="Short Handle" value={size} onChange={(e) => setSize(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="sl-brand">Make</label>
              <input id="sl-brand" placeholder="Gray-Nicolls" value={brand} onChange={(e) => setBrand(e.target.value)} />
            </div>
          </div>

          <div className="field">
            <label htmlFor="sl-note">What state is it in?</label>
            <textarea
              id="sl-note"
              rows={2}
              maxLength={500}
              placeholder="Light wear on the toe, no cracks. Knocked in, used one season."
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
            <small>Be honest — it saves somebody a wasted journey.</small>
          </div>

          <div className="field">
            <label htmlFor="sl-collect">Collection</label>
            <input
              id="sl-collect"
              maxLength={300}
              placeholder="From the clubhouse any Tuesday evening"
              value={collection}
              onChange={(e) => setCollection(e.target.value)}
            />
          </div>

          <label className="switch">
            <input type="checkbox" checked={publicly} onChange={(e) => setPublicly(e.target.checked)} />
            <span>Show it to players at other clubs</span>
          </label>

        </section>

        {error && <p className="error">{error}</p>}

        <div className="listing-actions">
          <button className="btn primary" disabled={busy}>
            {busy ? "Listing…" : "List it"}
          </button>
          <button type="button" className="btn" onClick={onCancel}>
            Cancel
          </button>
        </div>
      </form>

      {/* The space to the right was empty. A preview earns it: the seller sees
          what a buyer sees, which is also the most persuasive argument for
          filling in the description and adding a photograph. */}
      <aside className="listing-preview" aria-label="How your listing will look">
        <p className="listing-preview-label">How buyers will see it</p>
        <div className="market-card">
          <span className="market-photo empty" aria-hidden="true">
            <Icon name="camera" size={22} />
            <small>Add photos once it is listed</small>
          </span>
          <div className="market-body">
            <div className="market-title">
              <strong>{name.trim() || "Your listing"}</strong>
              <span className={`tag ${condition === "used" ? "grey" : "gold"}`}>
                {condition === "used" ? "Used" : "New"}
              </span>
            </div>
            <p className="market-price">
              {pounds ? `£${pounds}` : "£0.00"}
              {negotiable && " or near offer"}
            </p>
            <p className="muted">
              {stock === "" ? "On request" : stock === "1" && condition === "used" ? "One only" : `${stock || 0} available`}
              {size && ` · ${size}`}
              {brand && ` · ${brand}`}
            </p>
            {note.trim() && <p className="market-note">{note}</p>}
            {collection.trim() && (
              <p className="muted market-collect">
                <Icon name="pin" size={13} /> {collection}
              </p>
            )}
          </div>
        </div>
        {!publicly && (
          <p className="muted listing-preview-note">
            Only your own club will see this while &ldquo;show to other clubs&rdquo; is off.
          </p>
        )}
      </aside>
    </div>
  );
}
