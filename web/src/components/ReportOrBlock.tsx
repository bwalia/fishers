"use client";

import { useState } from "react";
import { Sheet } from "@/components/Sheet";
import { useT } from "@/lib/i18n/provider";
import {
  blockUser,
  fileReport,
  type ReportReason,
  type ReportSubjectKind,
} from "@/lib/api";

/// Reporting something, and blocking whoever posted it.
///
/// One component for both because they are one decision in the person's head
/// — "I do not want this" — and because every place that shows somebody
/// else's words needs the same pair. `subjectKind`/`subjectId` are what is
/// being reported; `personId` is who posted it, and is absent where there is
/// nobody to block (a club, or the app's own messages).
export function ReportOrBlock({
  subjectKind,
  subjectId,
  personId,
  personName,
  onBlocked,
}: {
  subjectKind: ReportSubjectKind;
  subjectId: string;
  personId?: string | null;
  personName?: string | null;
  /// So the page can drop what it is showing rather than leave a block that
  /// only takes effect on the next load.
  onBlocked?: () => void;
}) {
  const t = useT();
  const [open, setOpen] = useState<"report" | "block" | null>(null);
  const [reason, setReason] = useState<ReportReason>("abuse");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);

  const reasons: [ReportReason, string][] = [
    ["abuse", t("mod.reason_abuse")],
    ["objectionable", t("mod.reason_objectionable")],
    ["spam", t("mod.reason_spam")],
    ["impersonation", t("mod.reason_impersonation")],
    ["privacy", t("mod.reason_privacy")],
    ["other", t("mod.reason_other")],
  ];

  async function send() {
    setBusy(true);
    setError("");
    try {
      await fileReport(subjectKind, subjectId, reason, note);
      setSent(true);
      setOpen(null);
    } catch {
      setError(t("mod.report_would_not_send"));
    } finally {
      setBusy(false);
    }
  }

  async function block() {
    if (!personId) return;
    setBusy(true);
    setError("");
    try {
      await blockUser(personId);
      setOpen(null);
      onBlocked?.();
    } catch {
      setError(t("mod.block_would_not_save"));
    } finally {
      setBusy(false);
    }
  }

  if (sent) return <span className="muted sm">{t("mod.reported")}</span>;

  return (
    <>
      <span className="report-tools">
        <button className="btn ghost sm" type="button" onClick={() => setOpen("report")}>
          {t("mod.report")}
        </button>
        {personId && (
          <button className="btn ghost sm" type="button" onClick={() => setOpen("block")}>
            {t("mod.block")}
          </button>
        )}
      </span>

      {open === "report" && (
        <Sheet title={t("mod.report_this")} onClose={() => setOpen(null)}>
          <fieldset className="field">
            <legend>{t("mod.what_is_wrong")}</legend>
            {reasons.map(([value, label]) => (
              <label key={value} className="report-reason">
                <input
                  type="radio"
                  name="report-reason"
                  value={value}
                  checked={reason === value}
                  onChange={() => setReason(value)}
                />
                <span>{label}</span>
              </label>
            ))}
          </fieldset>
          <label className="field">
            <span>{t("mod.anything_else")}</span>
            <textarea
              value={note}
              maxLength={2000}
              rows={3}
              onChange={(e) => setNote(e.target.value)}
            />
          </label>
          {error && <p className="error">{error}</p>}
          <button className="btn primary" type="button" disabled={busy} onClick={send}>
            {t("mod.send_report")}
          </button>
        </Sheet>
      )}

      {open === "block" && personId && (
        <Sheet
          title={personName ? t("mod.block_name", { name: personName }) : t("mod.block")}
          onClose={() => setOpen(null)}
        >
          <p>{t("mod.block_explains")}</p>
          {error && <p className="error">{error}</p>}
          <button className="btn primary" type="button" disabled={busy} onClick={block}>
            {t("mod.block")}
          </button>
        </Sheet>
      )}
    </>
  );
}
