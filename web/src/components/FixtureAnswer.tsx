"use client";

import { useState } from "react";
import { readErr } from "@/lib/api";
import { ANSWERS, answerFixture, type Answer } from "@/lib/fixtures";
import { useT } from "@/lib/i18n/provider";

/// "Can you play?" — Available, Maybe or Can't play, showing what you said and
/// letting you change it. Saved as you tap; put back if it does not save.
export function FixtureAnswer({
  eventId,
  answer,
  onAnswered,
  label,
}: {
  eventId: string;
  answer: Answer | null;
  onAnswered: (answer: Answer | null) => void;
  /// Already-translated text for the group — callers name the fixture in it,
  /// so it carries a value and cannot be a bare key. Defaults to the plain
  /// question.
  label?: string;
}) {
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const choose = async (next: Answer) => {
    if (next === answer || busy) return;
    const before = answer;
    onAnswered(next);
    setBusy(true);
    setError(null);
    try {
      await answerFixture(eventId, next);
    } catch (err) {
      onAnswered(before);
      setError(readErr(err, t("le.that_did_not_save_try_again")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fx-answer">
      <div className="fx-seg" role="radiogroup" aria-label={label ?? t("le.can_you_play")}>
        {ANSWERS.map((a) => (
          <button
            key={a.value}
            type="button"
            role="radio"
            aria-checked={answer === a.value}
            className={`fx-seg-btn is-${a.value}${answer === a.value ? " on" : ""}`}
            disabled={busy}
            onClick={() => choose(a.value)}
          >
            {t(a.label)}
          </button>
        ))}
      </div>
      {error && <p className="error fx-answer-error">{error}</p>}
    </div>
  );
}
