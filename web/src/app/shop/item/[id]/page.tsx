"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Icon } from "@/components/Icon";
import { readErr, type MarketListing } from "@/lib/api";
import { useRequireAuth } from "@/lib/require-auth";
import { availability, enquire, marketItem, price, reserve } from "@/lib/shop";

const CATEGORY: Record<string, string> = {
  equipment: "Equipment",
  merchandise: "Merchandise",
};

/// One thing for sale, in full.
///
/// Two readers, one page. A buyer needs to know what it is, what state it is
/// in, where to collect it and who to ask — each of those labelled, because an
/// unlabelled paragraph under a price is not obviously the description, and
/// somebody who has never bought anything second-hand online should not have
/// to work it out.
///
/// The seller needs none of that. They wrote it. Showing them "Message the
/// seller" on their own advert is the app telling them it does not know who
/// they are, so they get their own view: how it is doing, and how to change it.
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
  if (error && !item)
    return (
      <main id="main" className="item">
        <p className="error">{error}</p>
        <Link className="btn" href="/shop">← Back to the shop</Link>
      </main>
    );
  if (!item)
    return (
      <main id="main" className="item">
        <div className="item-cols">
          <div className="skeleton" style={{ height: 380, borderRadius: "var(--radius)" }} />
          <div className="item-buybox">
            <div className="skeleton" style={{ height: 240 }} />
          </div>
        </div>
      </main>
    );

  const photos = item.photos ?? [];
  const sold = item.stock === 0;
  const mine = !!item.mine;

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
      <nav className="item-crumbs" aria-label="Breadcrumb">
        <Link href="/shop">
          <Icon name="arrowLeft" size={14} /> Kit for sale
        </Link>
        <span aria-hidden="true">/</span>
        <span>{CATEGORY[item.category] ?? item.category}</span>
      </nav>

      <div className="item-cols">
        <div className="item-gallery">
          <Slideshow photos={photos} title={item.name} />
        </div>

        <div className="item-buybox">
          <div className="item-tags">
            <span className="item-tag">{CATEGORY[item.category] ?? item.category}</span>
            {item.condition && (
              <span className={`item-tag ${item.condition === "used" ? "tag-used" : "tag-new"}`}>
                {item.condition === "used" ? "Second-hand" : "Brand new"}
              </span>
            )}
            {item.negotiable && !sold && <span className="item-tag tag-offer">Open to offers</span>}
          </div>

          <h1 className="item-name">{item.name}</h1>

          <p className="item-price">
            {price(item.price_cents, item.currency)}
            {item.negotiable && <span className="item-price-note">or near offer</span>}
          </p>

          <p className={`item-stock ${sold ? "gone" : ""}`}>
            <Icon name={sold ? "clock" : "check"} size={15} />
            {sold ? "Sold — no longer available" : availability(item)}
          </p>

          {mine ? (
            <OwnerPanel item={item} />
          ) : (
            <BuyerPanel
              item={item}
              sold={sold}
              reserved={reserved}
              reserving={reserving}
              asking={asking}
              onTake={take}
              onAsk={ask}
            />
          )}

          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
        </div>
      </div>

      {/* Everything worth reading, each piece under its own heading. The
          complaint this answers is a real one: a block of text under a price
          could be the description, the condition or the collection
          arrangements, and a buyer should not have to guess which. */}
      <div className="item-detail">
        <section className="item-block">
          <h2>Description</h2>
          {item.description ? (
            <p className="item-prose">{item.description}</p>
          ) : (
            <p className="muted">
              No description was written. {mine ? "Adding one helps it sell." : "Ask the seller if you need to know more."}
            </p>
          )}
        </section>

        <section className="item-block">
          <h2>Details</h2>
          <dl className="item-spec">
            <div>
              <dt>Category</dt>
              <dd>{CATEGORY[item.category] ?? item.category}</dd>
            </div>
            {item.condition && (
              <div>
                <dt>Condition</dt>
                <dd>{item.condition === "used" ? "Second-hand" : "Brand new"}</dd>
              </div>
            )}
            {item.brand && (
              <div>
                <dt>Make</dt>
                <dd>{item.brand}</dd>
              </div>
            )}
            {item.size && (
              <div>
                <dt>Size</dt>
                <dd>{item.size}</dd>
              </div>
            )}
            <div>
              <dt>How many</dt>
              <dd>{availability(item)}</dd>
            </div>
            {item.condition_note && (
              <div className="item-spec-wide">
                <dt>Wear and damage</dt>
                <dd>{item.condition_note}</dd>
              </div>
            )}
          </dl>
        </section>

        <section className="item-block">
          <h2>Where to collect it</h2>
          <p className="item-place">
            <Icon name="pin" size={16} />
            <span>
              <strong>{item.club_name}</strong>
              <br />
              {item.collection_note ?? "The seller has not said where yet — ask them before you travel."}
            </span>
          </p>
        </section>

        {!mine && (
          <section className="item-block item-how">
            <h2>How buying works</h2>
            <ol>
              <li>
                <strong>Ask anything you need to.</strong> Messages go to the seller here in the
                app. {item.negotiable && "The price is open to offers, so say what you would pay."}
              </li>
              <li>
                <strong>Reserve it.</strong> That holds it for you and tells the club — it does not
                charge you anything.
              </li>
              <li>
                <strong>Collect and pay in person.</strong> Cash or transfer, directly to the
                seller. No money goes through this app.
              </li>
            </ol>
          </section>
        )}
      </div>
    </main>
  );
}

/// What somebody who might buy it can do.
function BuyerPanel({
  item,
  sold,
  reserved,
  reserving,
  asking,
  onTake,
  onAsk,
}: {
  item: MarketListing;
  sold: boolean;
  reserved: boolean;
  reserving: boolean;
  asking: boolean;
  onTake: () => void;
  onAsk: () => void;
}) {
  if (reserved)
    return (
      <div className="item-done" role="status">
        <Icon name="check" size={18} />
        <div>
          <strong>Reserved for you.</strong>
          <p className="muted">
            The seller has been told. Arrange collection with them and pay them directly — nothing
            has been taken online.
          </p>
          <Link className="btn" href="/shop">Keep looking</Link>
        </div>
      </div>
    );

  return (
    <div className="item-actions">
      <button className="btn primary btn-lg" onClick={onTake} disabled={reserving || sold}>
        {sold ? "Already gone" : reserving ? "Reserving…" : "Reserve it"}
      </button>
      <button className="btn btn-lg" onClick={onAsk} disabled={asking}>
        <Icon name="chat" size={16} />
        {asking ? "Opening…" : item.negotiable ? "Make an offer" : "Ask a question"}
      </button>

      <p className="item-reassure">
        <Icon name="lock" size={14} />
        Nothing is paid online. Reserving tells the seller you want it; you settle up when you
        collect.
      </p>

      <div className="item-seller">
        <p className="item-seller-who">
          <span className="item-avatar" aria-hidden="true">
            {(item.seller_name ?? item.club_name).trim().charAt(0).toUpperCase()}
          </span>
          <span>
            <span className="muted">Sold by</span>
            <br />
            <strong>{item.seller_name ?? item.club_name}</strong>
            {item.seller_name && <span className="muted"> · {item.club_name}</span>}
          </span>
        </p>
        {(item.seller_email || item.seller_phone) && (
          <p className="item-contact">
            Happy to be contacted directly:
            {item.seller_phone && (
              <>
                {" "}
                <a href={`tel:${item.seller_phone}`}>{item.seller_phone}</a>
              </>
            )}
            {item.seller_phone && item.seller_email && " ·"}
            {item.seller_email && (
              <>
                {" "}
                <a href={`mailto:${item.seller_email}`}>{item.seller_email}</a>
              </>
            )}
          </p>
        )}
      </div>
    </div>
  );
}

/// The same listing, to the person selling it.
///
/// Not "Message the seller" and not "Reserve it" — they are the seller, and
/// reserving your own kit takes it off the marketplace and then notifies you
/// about yourself. What they actually want to know is whether it is getting
/// any interest, and how to change it.
function OwnerPanel({ item }: { item: MarketListing }) {
  const asked = item.enquiries ?? 0;
  const photos = item.photos?.length ?? 0;

  return (
    <div className="item-owner">
      <p className="item-owner-badge">
        <Icon name="check" size={15} /> This is your listing
      </p>
      <p className="muted">This is exactly how buyers see it.</p>

      <dl className="item-owner-stats">
        <div>
          <dt>People asking</dt>
          <dd>{asked}</dd>
        </div>
        <div>
          <dt>Photographs</dt>
          <dd>{photos}</dd>
        </div>
        <div>
          <dt>Visible to</dt>
          <dd>{item.listed_publicly ? "Every club" : "Your club only"}</dd>
        </div>
      </dl>

      <div className="item-actions">
        <Link className="btn primary btn-lg" href={`/shop/sell?item=${item.id}`}>
          Edit or mark as sold
        </Link>
        {asked > 0 ? (
          <Link className="btn btn-lg" href="/chat">
            <Icon name="chat" size={16} />
            Read {asked === 1 ? "the message" : `all ${asked} conversations`}
          </Link>
        ) : (
          <p className="item-reassure">
            <Icon name="chat" size={14} />
            Nobody has asked about it yet. Questions arrive in Chats.
          </p>
        )}
      </div>

      {photos === 0 && (
        <p className="item-nudge">
          It has no photographs. A listing without one is usually scrolled past — adding a couple is
          the single thing most likely to sell it.
        </p>
      )}
    </div>
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
              <img src={src} alt="" loading="lazy" />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
