"use client";

import { useState } from "react";
import { readErr } from "@/lib/api";
import { ANSWERS, answerFixture, type Answer } from "@/lib/fixtures";

/// "Can you play?" — Available, Maybe or Can't play, showing what you said and
/// letting you change it. Saved as you tap; put back if it does not save.
export function FixtureAnswer({
  eventId,
  answer,
  onAnswered,
  label = "Can you play?",
}: {
  eventId: string;
  answer: Answer | null;
  onAnswered: (answer: Answer | null) => void;
  label?: string;
}) {
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
      setError(readErr(err, "That did not save — try again"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fx-answer">
      <div className="fx-seg" role="radiogroup" aria-label={label}>
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
            {a.label}
          </button>
        ))}
      </div>
      {error && <p className="error fx-answer-error">{error}</p>}
    </div>
  );
}
