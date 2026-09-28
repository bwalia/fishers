"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Icon } from "@/components/Icon";
import { readErr, type MarketListing } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { availability, enquire, marketItem, priceLine, reserve } from "@/lib/shop";

/// One thing for sale, in full.
///
/// The page somebody lands on from a link: every photograph, the description,
/// what state it is in, and what happens next. No money changes hands here —
/// reserving tells the club, and the two of you settle it in person.
export default function ItemPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const authed = useRequireAuth();
  const router = useRouter();
  const [item, setItem] = useState<MarketListing | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reserving, setReserving] = useState(false);
  const [reserved, setReserved] = useState(false);
  const [asking, setAsking] = useState(false);

  const load = useCallback(async () => {
    try {
      setItem(await marketItem(id));
      setError(null);
    } catch (err) {
      setError(readErr(err, "That listing is not available"));
    }
  }, [id]);

  useEffect(() => {
    if (authed) load();
  }, [authed, load]);

  if (!authed) return <main id="main" />;
  if (error)
    return (
      <main id="main" className="item">
        <p className="error">{error}</p>
        <Link className="btn" href="/shop">← Back to the shop</Link>
      </main>
    );
  if (!item) return <main id="main" className="item"><div className="skeleton" style={{ height: 320 }} /></main>;

  const photos = item.photos ?? [];
  const sold = item.stock === 0;

  const take = async () => {
    setReserving(true);
    setError(null);
    try {
      await reserve(item.club_id, item.id);
      setReserved(true);
      load();
    } catch (err) {
      setError(readErr(err, "Could not reserve that"));
    } finally {
      setReserving(false);
    }
  };

  // Straight into the thread rather than a box on this page: the conversation
  // carries on there, and both of them already know where their messages live.
  const ask = async () => {
    setAsking(true);
    setError(null);
    try {
      const { conversation_id } = await enquire(item.id);
      router.push(`/chat/${conversation_id}`);
    } catch (err) {
      setError(readErr(err, "Could not start that conversation"));
      setAsking(false);
    }
  };

  return (
    <main id="main" className="item">
      <p className="muted">
        <Link href="/shop">← Kit for sale</Link>
      </p>

      <div className="item-cols">
        <Slideshow photos={photos} title={item.name} />

        <div className="item-facts">
          <div className="item-title">
            <h1>{item.name}</h1>
            {item.condition && (
              <span className={`tag ${item.condition === "used" ? "grey" : "gold"}`}>
                {item.condition === "used" ? "Used" : "New"}
              </span>
            )}
          </div>

          <p className="item-price">{priceLine(item)}</p>
          <p className="muted">{availability(item)}</p>

          <dl className="item-spec">
            {item.brand && (<><dt>Make</dt><dd>{item.brand}</dd></>)}
            {item.size && (<><dt>Size</dt><dd>{item.size}</dd></>)}
            {item.condition_note && (<><dt>Condition</dt><dd>{item.condition_note}</dd></>)}
            {item.collection_note && (<><dt>Collection</dt><dd>{item.collection_note}</dd></>)}
          </dl>

          {item.description && <p className="item-desc">{item.description}</p>}

          <div className="item-seller">
            <p className="item-seller-who">
              Sold by <strong>{item.seller_name ?? item.club_name}</strong>
              {item.seller_name && <span className="muted"> · {item.club_name}</span>}
            </p>
            <button className="btn item-ask" onClick={ask} disabled={asking}>
              <Icon name="chat" size={16} />
              {asking ? "Opening…" : item.negotiable ? "Message the seller or make an offer" : "Message the seller"}
            </button>
            {(item.seller_email || item.seller_phone) && (
              <p className="item-contact">
                Happy to be contacted directly:
                {item.seller_phone && (
                  <> <a href={`tel:${item.seller_phone}`}>{item.seller_phone}</a></>
                )}
                {item.seller_phone && item.seller_email && " ·"}
                {item.seller_email && (
                  <> <a href={`mailto:${item.seller_email}`}>{item.seller_email}</a></>
                )}
              </p>
            )}
          </div>

          {reserved ? (
            <div className="item-done">
              <Icon name="check" size={18} />
              <div>
                <strong>Reserved for you.</strong>
                <p className="muted">
                  The club has been told. Arrange collection with them and pay them directly —
                  nothing has been taken online.
                </p>
              </div>
            </div>
          ) : (
            <>
              <button className="btn primary item-take" onClick={take} disabled={reserving || sold}>
                {sold ? "Already gone" : reserving ? "Reserving…" : "Reserve it"}
              </button>
              <p className="muted">
                Nothing is paid online. Reserving tells the club you want it; you settle up when
                you collect.
              </p>
            </>
          )}
          {error && <p className="error">{error}</p>}
        </div>
      </div>
    </main>
  );
}

/// Every photograph, one at a time.
///
/// Arrows, the arrow keys, a swipe, and a count — a viewer that only responds
/// to a click on a thumbnail is one that half the people looking at a bat on a
/// phone never work out.
function Slideshow({ photos, title }: { photos: string[]; title: string }) {
  const [at, setAt] = useState(0);
  const touch = useRef<number | null>(null);

  const go = useCallback(
    (delta: number) => {
      // Wraps, because a gallery that stops at the end makes somebody drag
      // back through five pictures to see the first one again.
      setAt((i) => (i + delta + photos.length) % photos.length);
    },
    [photos.length],
  );

  useEffect(() => {
    if (photos.length < 2) return;
    const key = (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") go(-1);
      if (e.key === "ArrowRight") go(1);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [go, photos.length]);

  if (photos.length === 0) {
    return (
      <div className="item-shots">
        <div className="item-shot empty">
          <Icon name="camera" size={32} />
          <span className="muted">No photograph</span>
        </div>
      </div>
    );
  }

  return (
    <div className="item-shots">
      <div
        className="shot-stage"
        onTouchStart={(e) => {
          touch.current = e.touches[0].clientX;
        }}
        onTouchEnd={(e) => {
          if (touch.current === null) return;
          const moved = e.changedTouches[0].clientX - touch.current;
          // A threshold, so a tap that drifts two pixels is not a swipe.
          if (Math.abs(moved) > 40) go(moved < 0 ? 1 : -1);
          touch.current = null;
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="item-shot" src={photos[at]} alt={`${title} — photograph ${at + 1}`} />

        {photos.length > 1 && (
          <>
            <button type="button" className="shot-arrow prev" aria-label="Previous photograph" onClick={() => go(-1)}>
              <Icon name="arrowLeft" size={20} />
            </button>
            <button type="button" className="shot-arrow next" aria-label="Next photograph" onClick={() => go(1)}>
              <Icon name="arrowLeft" size={20} />
            </button>
            {/* Announced, because the picture changing is invisible to a
                screen reader otherwise. */}
            <p className="shot-count" aria-live="polite">
              {at + 1} of {photos.length}
            </p>
          </>
        )}
      </div>

      {photos.length > 1 && (
        <div className="item-thumbs" role="group" aria-label="Photographs">
          {photos.map((src, i) => (
            <button
              key={src}
              type="button"
              className={i === at ? "on" : undefined}
              aria-label={`Photograph ${i + 1} of ${photos.length}`}
              aria-current={i === at}
              onClick={() => setAt(i)}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={src} alt="" />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
