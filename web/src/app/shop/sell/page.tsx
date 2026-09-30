"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

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

const SHELVES: { key: Shelf; label: Key; blurb: Key }[] = [
  { key: "on_sale", label: "lc.on_sale", blurb: "lc.anybody_in_the_app_can_see_these_and_a" },
  { key: "club_only", label: "lc.your_club_only", blurb: "lc.listed_but_nobody_outside_your_club_ca" },
  { key: "sold", label: "lc.sold_or_taken_down", blurb: "lc.off_the_marketplace_you_can_put_one_ba" },
];

/// Everything this club has for sale, and how to put something new up.
///
/// Written for a club secretary who is not necessarily comfortable with
/// computers: the page says what will happen before it happens, every listing
/// says plainly which shelf it is on, and no button is a dead end.
export default function SellPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [products, setProducts] = useState<Product[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  /// The one just listed, so the page can say "that worked, now add photos"
  /// rather than dropping somebody back on a list to find it themselves.
  const [justListed, setJustListed] = useState<string | null>(null);
  // "Edit or mark as sold" on a listing's own page arrives here with ?item=,
  // and should land on that listing rather than on a page of all of them.
  // Read from the URL in an effect rather than useSearchParams, which would
  // drag the whole page out of the static build for one optional string.
  const [focus, setFocus] = useState<string | null>(null);
  useEffect(() => {
    setFocus(new URLSearchParams(window.location.search).get("item"));
  }, []);

  useEffect(() => {
    if (!authed) return;
    api<Club[]>("GET", "/clubs")
      .then((c) => {
        setClubs(c);
        if (c[0]) setClubId(c[0].id);
      })
      .catch((err) => setError(readErr(err, t("lc.could_not_load_your_clubs"))));
  }, [authed, t]);

  const load = useCallback(async () => {
    if (!clubId) return;
    try {
      setProducts(await clubProducts(clubId));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("lc.could_not_load_this_club_s_listings")));
    }
  }, [clubId, t]);

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
          <h1>{t("sh.your_listings")}</h1>
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
        <h2>{t("sh.how_selling_works")}</h2>
        <ol>
          <li><strong>{t("sh.put_it_up_2")}</strong> {t("sh.say_what_it_is_what_state_it_is_in_and")}</li>
          <li><strong>{t("sh.add_photographs")}</strong> {t("sh.up_to_six_nobody_buys_a_bat_they_canno")}</li>
          <li><strong>{t("sh.people_ask_about_it")}</strong> {t("sh.questions_and_offers_arrive_in")} <Link href="/chat">Chats</Link>, one conversation per person, each named after the thing they are asking about.</li>
          <li><strong>{t("sh.somebody_takes_it")}</strong> {t("sh.it_comes_off_the_marketplace_so_nobody")}</li>
          <li><strong>{t("sh.they_collect_and_pay_you")}</strong> {t("sh.cash_or_transfer_directly_to_the_club")}</li>
        </ol>
      </section>

      {fresh && (
        <section className="panel done-panel">
          <h2><Icon name="check" size={18} /> &ldquo;{fresh.name}&rdquo; is up</h2>
          <p className="muted">
            {(fresh.photos?.length ?? 0) === 0
              ? t("lc.it_has_no_photographs_yet_and_a_listin")
              : t("lc.it_is_on_the_marketplace_and_anybody_i")}
          </p>
          <div className="done-actions">
            <Link className="btn" href={`/shop/item/${fresh.id}`}>{t("sh.see_how_buyers_see_it")}</Link>
            <button className="btn" onClick={() => setJustListed(null)}>Done</button>
          </div>
        </section>
      )}

      {!adding ? (
        <div className="sell-cta">
          <button className="btn primary" onClick={() => setAdding(true)} disabled={!clubId}>
            <Icon name="plus" size={16} /> {t("sh.list_something_for_sale")}
          </button>
          <span className="muted">{t("sh.takes_a_minute_you_can_change_or_remov")}</span>
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
          <h2>{t("sh.nothing_up_yet")}</h2>
          <p className="muted">
            {t("sh.a_set_of_pads_the_club_has_replaced_is")}
          </p>
        </section>
      ) : (
        SHELVES.map(({ key, label, blurb }) => {
          const items = shelves[key];
          if (items.length === 0) return null;
          return (
            <section className="panel" key={key}>
              <div className="shelf-head">
                <h2>{t(label)}</h2>
                <span className="tag grey">{items.length}</span>
              </div>
              <p className="muted">{t(blurb)}</p>
              <ul className="sell-list">
                {items.map((p) => (
                  <Listing
                    key={p.id}
                    clubId={clubId}
                    product={p}
                    focused={p.id === focus}
                    onChanged={load}
                  />
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
  focused,
  onChanged,
}: {
  clubId: string;
  product: Product;
  /// Arrived here from this listing's own page: open it and scroll to it.
  focused?: boolean;
  onChanged: () => void;
}) {
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const row = useRef<HTMLLIElement>(null);

  useEffect(() => {
    if (!focused) return;
    setEditing(true);
    row.current?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [focused]);

  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onChanged();
    } catch (err) {
      setError(readErr(err, t("lc.that_did_not_save")));
    } finally {
      setBusy(false);
    }
  };

  const shelf = shelfOf(product);
  const photos = product.photos?.length ?? 0;

  return (
    <li ref={row} className={`sell-item${shelf === "sold" ? " sold" : ""}${focused ? " focused" : ""}`}>
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
              {product.condition === "used" ? t("lc.used") : "New"}
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
          {shelf === "sold" && t("lc.off_the_marketplace_nobody_can_ask_for")}
          {shelf === "club_only" && t("lc.only_your_own_club_can_see_this")}
          {shelf === "on_sale" && photos === 0 && (
            <span className="warn">
              <Icon name="help" size={14} /> {t("sh.no_photographs_most_people_scroll_past")}
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
            {t("sh.change_price")}
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
            {t("sh.put_back_on_sale")}
          </button>
        ) : (
          <button className="btn" disabled={busy} onClick={() => act(() => markSold(clubId, product.id))}>
            {t("sh.mark_as_sold")}
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
            {product.listed_publicly ? t("lc.hide_from_other_clubs") : t("lc.show_to_other_clubs")}
          </button>
        )}
        {shelf !== "sold" && (
          // Changeable after the fact: somebody who put their number up and
          // regretted it should not have to take the whole listing down.
          <button
            className="btn"
            disabled={busy}
            onClick={() =>
              act(() => updateListing(clubId, product.id, { show_contact: !product.show_contact }))
            }
          >
            {product.show_contact ? t("lc.hide_my_phone_and_email") : t("lc.show_my_phone_and_email")}
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
  const t = useT();
  const [pounds, setPounds] = useState((product.price_cents / 100).toFixed(2));
  const [negotiable, setNegotiable] = useState(!!product.negotiable);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    const amount = Math.round(parseFloat(pounds) * 100);
    if (!Number.isFinite(amount) || amount < 0) return setError(t("lc.that_is_not_a_price"));
    setBusy(true);
    setError(null);
    try {
      await updateListing(clubId, product.id, { price_cents: amount, negotiable });
      onDone();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_change_the_price")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="quick-edit" onSubmit={save}>
      <div className="field field-price">
        <label htmlFor={`qe-${product.id}`}>{t("sh.new_price")}</label>
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
        <span>{t("sh.open_to_offers")}</span>
      </label>
      <button className="btn primary" disabled={busy}>{busy ? "Saving…" : t("lc.save")}</button>
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
  const t = useT();
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
    setBusy(t("lc.removing"));
    setError(null);
    try {
      await updateListing(clubId, product.id, { photos: photos.filter((p) => p !== url) });
      onDone();
    } catch (err) {
      setError(readErr(err, t("lc.could_not_remove_that_photograph")));
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
              {i === 0 && <span className="photos-first">{t("sh.cover")}</span>}
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
          {busy ?? (photos.length === 0 ? t("lc.add_photographs") : t("fin.add_another_room_for", { n: room }))}
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
          {t("sh.you_can_pick_several_at_once_the_first")}
        </small>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}

const MAX_PHOTOS = 6;

const CONDITIONS: { value: ProductCondition; label: Key; hint: Key }[] = [
  { value: "used", label: "lc.used", hint: "lc.the_club_has_replaced_it_and_this_one" },
  { value: "new", label: "sh.condition_new", hint: "lc.unused_bought_in_or_made_by_the_club" },
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
  const t = useT();
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
  const [showContact, setShowContact] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const amount = Math.round(parseFloat(pounds) * 100);
    if (!Number.isFinite(amount) || amount < 0) {
      return setError(t("lc.put_a_price_in_even_if_it_is_0_for_a_g"));
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
        show_contact: showContact,
      });
      onDone(created.id);
    } catch (err) {
      setError(readErr(err, t("lc.could_not_list_that")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="listing">
      <form className="listing-form" onSubmit={submit}>
        <section className="listing-group">
          <h2>{t("sh.what_it_is")}</h2>

          <div className="field">
            <label htmlFor="sl-name">Name</label>
            <input
              id="sl-name"
              required
              maxLength={160}
              placeholder={t("sh.gray_nicolls_predator_bat")}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>

          <div className="field">
            <label htmlFor="sl-desc">Description</label>
            <textarea
              id="sl-desc"
              rows={4}
              placeholder={t("sh.kashmir_willow_knocked_in_and_used_for")}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
            <small>{t("sh.what_it_is_how_it_played_why_you_are_s")}</small>
          </div>

          <div className="field field-narrow">
            <label htmlFor="sl-cat">Kind</label>
            <select id="sl-cat" value={category} onChange={(e) => setCategory(e.target.value)}>
              <option value="equipment">Bats, balls &amp; kit</option>
              <option value="merchandise">Shoes &amp; sportswear</option>
            </select>
            <small>{t("sh.only_kit_is_shown_to_other_clubs")}</small>
          </div>
        </section>

        <section className="listing-group">
          <h2>{t("sh.condition_and_price")}</h2>

          <fieldset className="choice">
            <legend className="sr-only">{t("sh.condition")}</legend>
            {CONDITIONS.map((c) => (
              <label key={c.value} className={condition === c.value ? "on" : undefined}>
                <input
                  type="radio"
                  name="condition"
                  value={c.value}
                  checked={condition === c.value}
                  onChange={() => setCondition(c.value)}
                />
                <strong>{t(c.label)}</strong>
                <span>{t(c.hint)}</span>
              </label>
            ))}
          </fieldset>

          <div className="field-row">
            <div className="field field-price">
              <label htmlFor="sl-price">{t("sh.price")}</label>
              <div className="input-prefix">
                <span aria-hidden="true">£</span>
                <input
                  id="sl-price"
                  required
                  inputMode="decimal"
                  placeholder={t("sh.45_00")}
                  value={pounds}
                  onChange={(e) => setPounds(e.target.value)}
                />
              </div>
            </div>
            <div className="field field-qty">
              <label htmlFor="sl-stock">{t("sh.how_many")}</label>
              <input
                id="sl-stock"
                inputMode="numeric"
                value={stock}
                onChange={(e) => setStock(e.target.value)}
              />
              <small>{t("sh.blank_means_made_to_order")}</small>
            </div>
            <label className="switch listing-switch">
              <input
                type="checkbox"
                checked={negotiable}
                onChange={(e) => setNegotiable(e.target.checked)}
              />
              <span>{t("sh.open_to_offers")}</span>
            </label>
          </div>
        </section>

        <section className="listing-group">
          <h2>{t("sh.the_details_that_sell_it")}</h2>

          <div className="field-row">
            <div className="field">
              <label htmlFor="sl-size">{t("sh.size")}</label>
              <input id="sl-size" placeholder={t("sh.short_handle")} value={size} onChange={(e) => setSize(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="sl-brand">{t("sh.make")}</label>
              <input id="sl-brand" placeholder={t("sh.gray_nicolls")} value={brand} onChange={(e) => setBrand(e.target.value)} />
            </div>
          </div>

          <div className="field">
            <label htmlFor="sl-note">{t("sh.what_state_is_it_in")}</label>
            <textarea
              id="sl-note"
              rows={2}
              maxLength={500}
              placeholder={t("sh.light_wear_on_the_toe_no_cracks_knocke")}
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
            <small>{t("sh.be_honest_it_saves_somebody_a_wasted_j")}</small>
          </div>

          <div className="field">
            <label htmlFor="sl-collect">{t("sh.collection")}</label>
            <input
              id="sl-collect"
              maxLength={300}
              placeholder={t("sh.from_the_clubhouse_any_tuesday_evening")}
              value={collection}
              onChange={(e) => setCollection(e.target.value)}
            />
          </div>

          <label className="switch">
            <input type="checkbox" checked={publicly} onChange={(e) => setPublicly(e.target.checked)} />
            <span>{t("sh.show_it_to_players_at_other_clubs")}</span>
          </label>

          <label className="switch">
            <input
              type="checkbox"
              checked={showContact}
              onChange={(e) => setShowContact(e.target.checked)}
            />
            <span>
              {t("sh.put_my_email_and_phone_number_on_the_l")}
              <small>
                {t("sh.off_by_default_buyers_can_always_messa")}
              </small>
            </span>
          </label>
        </section>

        {error && <p className="error">{error}</p>}

        <div className="listing-actions">
          <button className="btn primary" disabled={busy}>
            {busy ? t("lc.listing") : t("lc.list_it")}
          </button>
          <button type="button" className="btn" onClick={onCancel}>
            Cancel
          </button>
        </div>
      </form>

      {/* The space to the right was empty. A preview earns it: the seller sees
          what a buyer sees, which is also the most persuasive argument for
          filling in the description and adding a photograph. */}
      <aside className="listing-preview" aria-label={t("sh.how_your_listing_will_look")}>
        <p className="listing-preview-label">{t("sh.how_buyers_will_see_it")}</p>
        <div className="market-card">
          <span className="market-photo empty" aria-hidden="true">
            <Icon name="camera" size={22} />
            <small>{t("sh.add_photos_once_it_is_listed")}</small>
          </span>
          <div className="market-body">
            <div className="market-title">
              <strong>{name.trim() || t("lc.your_listing")}</strong>
              <span className={`tag ${condition === "used" ? "grey" : "gold"}`}>
                {condition === "used" ? t("lc.used") : "New"}
              </span>
            </div>
            <p className="market-price">
              {pounds ? `£${pounds}` : "£0.00"}
              {negotiable && " or near offer"}
            </p>
            <p className="muted">
              {stock === "" ? t("lc.on_request") : stock === "1" && condition === "used" ? t("lc.one_only") : `${stock || 0} available`}
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
