"use client";

/// "Add a screenshot": a picture of the payment from the player's banking
/// app, sent with it so the treasurer can match it without asking on
/// WhatsApp.
///
/// The picture is drawn again in the browser first — at most 1600 px, as a
/// JPEG under a megabyte — because a phone screenshot is several megabytes
/// and the API takes one. Optional, and never in the way of paying.

import { useId, useRef, useState } from "react";
import { readErr } from "@/lib/api";
import { UnreadablePicture, shrinkScreenshot } from "@/lib/payments";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

export function ScreenshotButton({
  done,
  upload,
  onUploaded,
  who,
}: {
  /// One is already attached: offer to send a different one.
  done: boolean;
  /// Sends the shrunk picture; throws the API's refusal.
  upload: (image: Blob) => Promise<void>;
  onUploaded?: () => void | Promise<void>;
  /// The first name of whoever checks it, for the help line; null for "the club".
  who: string | null;
}) {
  const t = useT();
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const chosen = async (file: File | undefined) => {
    if (!file) return;
    setBusy(true);
    setError(null);
    setSent(false);
    try {
      if (file.type && !file.type.startsWith("image/")) throw new UnreadablePicture();
      const image = await shrinkScreenshot(file);
      await upload(image);
      setSent(true);
      await onUploaded?.();
    } catch (e) {
      setError(e instanceof UnreadablePicture ? t("pw2.screenshot_unreadable") : readErr(e, t("le.that_did_not_work")));
    } finally {
      setBusy(false);
      // The same file chosen again is a fresh try.
      if (input.current) input.current.value = "";
    }
  };

  const attached = done || sent;
  return (
    <div className="pay-shot">
      {attached && (
        <p className="pay-shot-done" role="status">
          <Icon name="check" size={18} /> {t("pw2.screenshot_added")}
        </p>
      )}
      {!attached && (
        <p className="muted" id={`${id}-help`}>
          {who ? t("pw2.add_screenshot_help", { first: who }) : t("pw2.add_screenshot_help_club")}
        </p>
      )}
      <input
        ref={input}
        id={`${id}-file`}
        className="sr-only"
        type="file"
        accept="image/*"
        tabIndex={-1}
        aria-hidden="true"
        onChange={(e) => void chosen(e.target.files?.[0])}
      />
      <button
        className="btn"
        type="button"
        disabled={busy}
        aria-describedby={[attached ? "" : `${id}-help`, error ? `${id}-error` : ""].filter(Boolean).join(" ") || undefined}
        onClick={() => input.current?.click()}
      >
        <Icon name="camera" size={18} />{" "}
        {busy ? t("pw2.screenshot_sending") : attached ? t("pw2.screenshot_change") : t("pw2.add_screenshot")}
      </button>
      {error && (
        <p className="field-error" id={`${id}-error`} role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
