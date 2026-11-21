"use client";

/// "Import a bank statement" (plan §12, step D), on the club's Payments page
/// for its money admins. Pick the CSV the bank exports, then see:
///   - "Ticked off: 8" — payments that match a member, ticked to apply;
///   - "Needs a look: 2" — each with why, in words;
///   - "Not recognised: 5", folded away; "Already done: 3".
/// Then **Apply 8**.
///
/// The server reads the statement again when it applies, so this page only
/// chooses which of the server's matches to apply. The file's text stays in
/// this page's memory until then: never in a URL, never logged, never stored.

import { useEffect, useId, useRef, useState } from "react";
import { api, errCode, money, readErr } from "@/lib/api";
import { postText, type Payment } from "@/lib/payments";
import { shortDay } from "@/lib/passes";
import {
  groupLines,
  saidCents,
  sharedSurname,
  type StatementApplied,
  type StatementLine,
  type StatementPreview,
} from "@/lib/statement";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// A refusal of the file itself, in the reader's language rather than the
/// server's English.
const FILE_ERRORS: Record<string, Key> = {
  empty_statement: "pw4.statement_empty",
  unknown_statement: "pw4.statement_unknown",
  statement_too_long: "pw4.statement_too_long",
};

export function StatementImport({
  clubId,
  toCheck,
  onDone,
}: {
  clubId: string;
  /// The payments waiting to be checked, for "Said £6, sent £9".
  toCheck: Payment[];
  /// Applied: say so, and show the page as it is now.
  onDone: (said: string) => Promise<void>;
}) {
  const t = useT();
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  /// The statement as read from the file, kept only to send it again on
  /// Apply.
  const [csv, setCsv] = useState<string | null>(null);
  const [preview, setPreview] = useState<StatementPreview | null>(null);
  /// Lines left unticked, by hash: everything ready is ticked to start with.
  const [unticked, setUnticked] = useState<Set<string>>(new Set());
  /// Every member's name, for "Two members called SHARMA". Only fetched when
  /// a line needs it.
  const [names, setNames] = useState<string[] | null>(null);
  const [busy, setBusy] = useState<"reading" | "applying" | null>(null);
  const [error, setError] = useState<string | null>(null);

  const needsNames = !!preview?.lines.some((l) => l.why === "shared_name");
  useEffect(() => {
    if (!needsNames || names) return;
    api<{ name: string }[]>("GET", `/clubs/${clubId}/payments/members`)
      .then((m) => setNames(m.map((x) => x.name)))
      .catch(() => setNames([]));
  }, [needsNames, names, clubId]);

  const fileError = (e: unknown) => {
    const key = FILE_ERRORS[errCode(e) ?? ""];
    return key ? t(key) : readErr(e, t("le.that_did_not_work"));
  };

  const reset = () => {
    setCsv(null);
    setPreview(null);
    setUnticked(new Set());
    setError(null);
  };

  const chosen = async (file: File | undefined) => {
    if (!file) return;
    setBusy("reading");
    setError(null);
    setPreview(null);
    try {
      const text = await file.text();
      const p = await postText<StatementPreview>(`/clubs/${clubId}/statement/preview`, text);
      setCsv(text);
      setPreview(p);
      setUnticked(new Set());
    } catch (e) {
      setCsv(null);
      setError(fileError(e));
    } finally {
      setBusy(null);
      // The same file chosen again is a fresh look.
      if (input.current) input.current.value = "";
    }
  };

  const groups = preview ? groupLines(preview.lines) : null;
  const picked = groups ? groups.ticked.filter((l) => !unticked.has(l.hash)) : [];

  const apply = async () => {
    if (!csv || picked.length === 0) return;
    setBusy("applying");
    setError(null);
    try {
      const out = await api<StatementApplied>("POST", `/clubs/${clubId}/statement/apply`, {
        csv,
        lines: picked.map((l) => l.hash),
      });
      const said = [t("pw4.applied", { confirmed: out.confirmed, recorded: out.recorded })];
      if (out.skipped > 0) said.push(t("pw4.applied_skipped", { count: out.skipped, n: out.skipped }));
      reset();
      await onDone(said.join(" "));
    } catch (e) {
      setError(fileError(e));
    } finally {
      setBusy(null);
    }
  };

  const cur = preview?.currency ?? "GBP";
  const toggle = (hash: string) =>
    setUnticked((now) => {
      const next = new Set(now);
      if (next.has(hash)) next.delete(hash);
      else next.add(hash);
      return next;
    });

  /// Why a line needs a person, in words.
  const why = (l: StatementLine): string => {
    const sent = money(l.amount_cents, cur);
    if (l.why === "different_amount") {
      const said = l.user_id ? saidCents(toCheck, l.user_id) : 0;
      return said > 0
        ? t("pw4.why_different", { said: money(said, cur), sent })
        : t("pw4.why_different_unknown", { sent });
    }
    if (l.why === "shared_name") {
      const shared = names ? sharedSurname(l.text, names) : null;
      if (!shared) return t("pw4.why_shared");
      return shared.count === 2
        ? t("pw4.why_shared_two", { name: shared.surname })
        : t("pw4.why_shared_many", { name: shared.surname, count: shared.count });
    }
    return t("pw4.why_look");
  };

  const when = (l: StatementLine) => [shortDay(l.date), l.text].filter(Boolean).join(" · ");

  return (
    <section className="panel statement" id="statement" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{t("pw4.import_statement")}</h2>

      {!preview && (
        <>
          <p className="muted" id={`${id}-help`}>
            {t("pw4.import_help")}
          </p>
          <input
            ref={input}
            className="sr-only"
            type="file"
            accept=".csv,text/csv,text/plain"
            tabIndex={-1}
            aria-hidden="true"
            onChange={(e) => void chosen(e.target.files?.[0])}
          />
          <button
            className="btn primary lg"
            type="button"
            disabled={busy !== null}
            aria-describedby={[`${id}-help`, error ? `${id}-error` : ""].filter(Boolean).join(" ")}
            onClick={() => input.current?.click()}
          >
            {busy === "reading" ? t("pw4.reading_statement") : t("pw4.choose_statement")}
          </button>
          {error && (
            <p className="field-error" id={`${id}-error`} role="alert">
              {error}
            </p>
          )}
        </>
      )}

      {preview && groups && (
        <>
          <p className="muted">
            {preview.summary.credits === 0
              ? t("pw4.statement_no_money_in")
              : t("pw4.statement_money_in", { count: preview.summary.credits, n: preview.summary.credits })}
          </p>

          <h3 className="statement-h">{t("pw4.ticked_off", { n: groups.ticked.length })}</h3>
          {groups.ticked.length > 0 ? (
            <>
              <p className="muted">{t("pw4.ticked_off_help")}</p>
              <ul className="statement-lines">
                {groups.ticked.map((l) => (
                  <li key={l.hash}>
                    <label className="statement-line">
                      <input type="checkbox" checked={!unticked.has(l.hash)} onChange={() => toggle(l.hash)} />
                      <span className="statement-who">
                        <strong>{l.name}</strong>
                        <span className="muted">
                          {l.action === "record"
                            ? t("pw4.hadnt_said")
                            : l.payment_ids.length > 1
                              ? t("pw4.said_paid_for_n", { n: l.payment_ids.length })
                              : t("pw4.said_paid")}
                        </span>
                        <span className="subtle">{when(l)}</span>
                      </span>
                      <span className="num">{money(l.amount_cents, cur)}</span>
                    </label>
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <p className="muted">{t("pw4.nothing_to_tick")}</p>
          )}

          {groups.look.length > 0 && (
            <>
              <h3 className="statement-h">{t("pw4.needs_a_look", { n: groups.look.length })}</h3>
              <p className="muted">{t("pw4.needs_a_look_help")}</p>
              <ul className="statement-lines">
                {groups.look.map((l) => (
                  <li key={l.hash} className="statement-line">
                    <span className="statement-who">
                      {l.name && <strong>{l.name}</strong>}
                      <span className="pay-warn">{why(l)}</span>
                      <span className="subtle">{when(l)}</span>
                    </span>
                    <span className="num">{money(l.amount_cents, cur)}</span>
                  </li>
                ))}
              </ul>
            </>
          )}

          {groups.unknown.length > 0 && (
            <details className="statement-fold">
              <summary>{t("pw4.not_recognised", { n: groups.unknown.length })}</summary>
              <p className="muted">{t("pw4.not_recognised_help")}</p>
              <ul className="statement-lines">
                {groups.unknown.map((l) => (
                  <li key={l.hash} className="statement-line">
                    <span className="statement-who">
                      <span>{l.text || "—"}</span>
                      <span className="subtle">{shortDay(l.date)}</span>
                    </span>
                    <span className="num">{money(l.amount_cents, cur)}</span>
                  </li>
                ))}
              </ul>
            </details>
          )}

          {groups.already.length > 0 && (
            <p className="muted">{t("pw4.already_done", { n: groups.already.length })}</p>
          )}

          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <div className="field-row">
            {groups.ticked.length > 0 && (
              <button
                className="btn primary lg"
                type="button"
                disabled={busy !== null || picked.length === 0}
                onClick={() => void apply()}
              >
                {busy === "applying" ? t("pay.sending") : t("pw4.apply_n", { n: picked.length })}
              </button>
            )}
            <button className="btn" type="button" disabled={busy !== null} onClick={reset}>
              {groups.ticked.length > 0 ? t("pay.never_mind") : t("pw4.choose_another")}
            </button>
          </div>
        </>
      )}
    </section>
  );
}
