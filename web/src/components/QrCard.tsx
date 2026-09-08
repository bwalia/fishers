"use client";

import type { QrCode } from "@/lib/api";
import { copyText } from "@/lib/clipboard";

/// A club or team's code, as an opposition captain sees it at the ground.
///
/// The square is drawn by the API — a QR encoder is error-correction maths, not
/// a few lines — so this only has to show it, and the payload is printed
/// underneath for anyone whose camera will not cooperate.
export function QrCard({ qr }: { qr: QrCode }) {
  return (
    <div className="qr-card">
      <div className="panel-head">
        <div>
          <h3>{qr.name}</h3>
          <span className="tag grey">{qr.kind}</span>
        </div>
      </div>
      <div
        className="qr-image"
        // The API generates this from the payload; nothing user-supplied
        // reaches it.
        dangerouslySetInnerHTML={{ __html: qr.svg }}
      />
      <p className="subtle qr-payload">{qr.payload}</p>
      <button
        className="btn sm ghost"
        type="button"
        onClick={() => void copyText(qr.payload)}
      >
        Copy link
      </button>
    </div>
  );
}
