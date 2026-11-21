"use client";

/// Share to WhatsApp (plan §5.1): the bill goes where the players are — the
/// club's WhatsApp group — as a message with a pay link that works without
/// signing in. Then, later, "Remind who hasn't paid" with the same link.
///
/// The messages are the server's own (`bill_message`, `reminder_message`),
/// so every app posts the same words. They go out through WhatsApp's own
/// `wa.me` address, or the phone's share sheet where there is one. Neither
/// carries bank details: the link does that, behind its own limits.
///
/// A group fee (`billId`) shares the same way. It has no "only look" call, so
/// its link is made on the first Share and refreshed from then on.

import { useCallback, useEffect, useRef, useState } from "react";
import { api, errCode, readErr } from "@/lib/api";
import { shortDate, type PayLinkShare } from "@/lib/payments";
import { whatsappUrl } from "@/lib/pay-link";
import { CopyButton } from "@/components/CopyButton";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

export function ShareBill({
  eventId,
  billId,
  refreshKey,
}: {
  /// A session's bill…
  eventId?: string;
  /// …or a group fee's.
  billId?: string;
  /// Changes whenever the bill does — a re-split, a payment ticked — so
  /// "still to pay" stays true.
  refreshKey: string;
}) {
  const t = useT();
  const base = billId ? `/bills/${billId}/link` : `/events/${eventId}/bill/link`;
  const [link, setLink] = useState<PayLinkShare | null>(null);
  const shown = useRef(false);
  const [none, setNone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /// Switched off here: not made again until somebody asks.
  const [off, setOff] = useState(false);
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [canShare, setCanShare] = useState(false);

  useEffect(() => setCanShare(typeof navigator !== "undefined" && typeof navigator.share === "function"), []);

  /// The bill's open link, if it has one. Opening the session only looks: a
  /// link is made the first time somebody taps Share (`makeAndShare`).
  const [noLink, setNoLink] = useState(false);
  const fetchLink = useCallback(async () => {
    try {
      // A group fee can only be asked by making (or reusing) its link: do
      // that only once somebody has shared it here.
      if (billId && !shown.current) {
        setNoLink(true);
        return;
      }
      const open = billId
        ? await api<PayLinkShare>("POST", base)
        : await api<PayLinkShare | null>("GET", base);
      setLink(open);
      setNoLink(!open);
      setError(null);
    } catch (e) {
      if (errCode(e) === "no_bill") setNone(true);
      else setError(readErr(e, t("pw2.link_not_made")));
    }
  }, [base, billId, t]);

  /// The first share: make the link (the same one each time after, until it
  /// is switched off or runs out), then open WhatsApp with the bill.
  const makeAndShare = async () => {
    setBusy(true);
    setError(null);
    try {
      const made = await api<PayLinkShare>("POST", base);
      shown.current = true;
      setLink(made);
      setNoLink(false);
      window.open(whatsappUrl(made.bill_message), "_blank", "noopener,noreferrer");
    } catch (e) {
      if (errCode(e) === "no_bill") setNone(true);
      else setError(readErr(e, t("pw2.link_not_made")));
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    if (!off) void fetchLink();
    // `refreshKey` is what makes this run again when the bill changes.
  }, [fetchLink, off, refreshKey]);

  if (none) return null;

  const switchOff = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", `${base}/disable`);
      shown.current = false;
      setOff(true);
      setLink(null);
      setAsking(false);
      setNotice(t("pw2.link_switched_off"));
    } catch (e) {
      setError(readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
    }
  };

  const shareSheet = async (text: string) => {
    try {
      await navigator.share({ text });
    } catch {
      /* closed without sending: nothing to say */
    }
  };

  return (
    <section className="share-bill" aria-labelledby={`share-${billId ?? eventId}`}>
      <h3 id={`share-${billId ?? eventId}`}>{t("pw2.share_title")}</h3>
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {off ? (
        <>
          <p className="muted">{t("pw2.link_off_help")}</p>
          <button
            className="btn"
            type="button"
            onClick={() => {
              setNotice(null);
              setOff(false);
            }}
          >
            {t("pw2.make_new_link")}
          </button>
        </>
      ) : noLink ? (
        <>
          <p className="muted">{t("pw2.share_help")}</p>
          <div className="share-actions">
            <button className="btn primary whatsapp" type="button" disabled={busy} onClick={() => void makeAndShare()}>
              <Icon name="chat" size={18} /> {t("pw2.share_bill")}
            </button>
          </div>
        </>
      ) : !link ? (
        !error && <div className="skeleton" style={{ height: 88 }} />
      ) : (
        <>
          <p className="muted">{t("pw2.share_help")}</p>
          <p className="share-who">
            {link.still_to_pay.length > 0
              ? t("pw2.still_to_pay", { names: link.still_to_pay.join(", ") })
              : t("pw2.everyone_paid")}
          </p>
          <div className="share-actions">
            <a
              className="btn primary whatsapp"
              href={whatsappUrl(link.bill_message)}
              target="_blank"
              rel="noopener noreferrer"
            >
              <Icon name="chat" size={18} /> {t("pw2.share_bill")}
            </a>
            {link.still_to_pay.length > 0 && (
              <a className="btn whatsapp" href={whatsappUrl(link.reminder_message)} target="_blank" rel="noopener noreferrer">
                <Icon name="send" size={18} /> {t("pw2.remind_unpaid")}
              </a>
            )}
            {canShare && (
              <button className="btn" type="button" onClick={() => void shareSheet(link.bill_message)}>
                <Icon name="share" size={18} /> {t("pw2.share_other_way")}
              </button>
            )}
            <CopyButton text={link.url} what={t("pw2.what_pay_link")} label={t("pw2.copy_link")} />
          </div>
          <p className="subtle">{t("pw2.link_until", { date: shortDate(link.expires_at) })}</p>

          {asking ? (
            <div className="confirm-box" role="group" aria-label={t("pw2.switch_off")}>
              <p>{t("pw2.switch_off_confirm")}</p>
              <div className="field-row">
                <button className="btn danger" type="button" disabled={busy} onClick={() => void switchOff()}>
                  {t("pw2.yes_switch_off")}
                </button>
                <button className="btn" type="button" disabled={busy} onClick={() => setAsking(false)}>
                  {t("pay.never_mind")}
                </button>
              </div>
            </div>
          ) : (
            <button
              className="btn ghost share-off"
              type="button"
              onClick={() => {
                setNotice(null);
                setAsking(true);
              }}
            >
              {t("pw2.switch_off")}
            </button>
          )}
        </>
      )}
    </section>
  );
}
