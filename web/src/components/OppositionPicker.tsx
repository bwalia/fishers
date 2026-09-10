"use client";

import { useEffect, useRef, useState } from "react";
import { api, type OpponentIdentity } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { isSecureContextAvailable } from "@/lib/clipboard";

/// Three ways to name the other side, because a ground is not a laboratory:
/// scan their code, paste the link they sent, or search for them by name. A
/// club that is not in Fishers at all is typed in and stays a plain name.
export function OppositionPicker({
  onPick,
}: {
  onPick: (identity: OpponentIdentity | null, name: string) => void;
}) {
  const [tab, setTab] = useState<"scan" | "code" | "search">("search");
  const [code, setCode] = useState("");
  const [query, setQuery] = useState("");
  /// A club that is not on Fishers at all: a name and nothing else.
  const [plain, setPlain] = useState("");
  const [results, setResults] = useState<OpponentIdentity[]>([]);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const resolve = async (token: string) => {
    setBusy(true);
    setNote(null);
    try {
      const identity = await api<OpponentIdentity>("POST", "/opponents/lookup", { token });
      setPlain("");
      onPick(identity, identity.name);
      setNote(`Matched ${identity.name}.`);
    } catch {
      setNote("That code is not one of ours. Try searching by name.");
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) {
      setResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        setResults(
          await api<OpponentIdentity[]>("GET", `/opponents/search?q=${encodeURIComponent(term)}`)
        );
      } catch {
        setResults([]);
      }
    }, 250);
    return () => clearTimeout(timer);
  }, [query]);

  return (
    <div>
      <div className="tabs" role="tablist" aria-label="Find the opposition">
        {(["search", "scan", "code"] as const).map((t) => (
          <button
            key={t}
            role="tab"
            aria-selected={tab === t}
            className={`tab${tab === t ? " active" : ""}`}
            type="button"
            onClick={() => setTab(t)}
          >
            {t === "search" ? "Search" : t === "scan" ? "Scan a code" : "Paste a link"}
          </button>
        ))}
      </div>

      {tab === "search" && (
        <>
          <label>
            Club or team name
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Hemel, Watford…"
            />
          </label>
          <ul className="plain-list" style={{ marginTop: "var(--s2)" }}>
            {results.map((r) => (
              <li key={r.id}>
                <button
                  className="btn sm"
                  type="button"
                  onClick={() => {
                    setPlain("");
                    onPick(r, r.name);
                    setNote(`Matched ${r.name}.`);
                  }}
                >
                  {r.name}
                  <span className="subtle"> {r.kind}</span>
                </button>
              </li>
            ))}
            {query.trim().length >= 2 && results.length === 0 && (
              <li className="muted">Nobody by that name in Fishers.</li>
            )}
          </ul>

          {/* Most opposition clubs are not on Fishers, and a fixture against
              one still has to be schedulable. This used to say "type it as a
              plain name below" with no field below it, so a club whose
              opponent was not a member could not schedule a match at all. */}
          <label style={{ marginTop: "var(--s3)" }}>
            Or just their name
            <input
              value={plain}
              onChange={(e) => {
                setPlain(e.target.value);
                // A typed name and a matched club are alternatives, so typing
                // clears whatever was matched — otherwise the fixture is
                // scheduled against the club they abandoned.
                onPick(null, e.target.value);
                setNote(null);
              }}
              placeholder="Hackney Wanderers"
            />
            <span className="subtle">
              They will not be asked who is available — only your side is.
            </span>
          </label>
        </>
      )}

      {tab === "scan" && <QrScanner onScan={resolve} />}

      {tab === "code" && (
        <div className="field-row">
          <label>
            Their code or link
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="https://…/play/abc123 or just the code"
            />
          </label>
          <button
            className="btn"
            type="button"
            disabled={!code.trim() || busy}
            onClick={() => resolve(code.trim())}
          >
            {busy ? "Looking…" : "Match"}
          </button>
        </div>
      )}

      {note && <p className="muted">{note}</p>}
    </div>
  );
}

/// Camera scanning, where the browser can do it.
///
/// `BarcodeDetector` is in Chrome and Edge but not Safari or Firefox, and
/// shipping a decoder just for those would be a lot of bytes for something the
/// other two tabs already cover. So this offers the camera when it is there and
/// says plainly when it is not.
function QrScanner({ onScan }: { onScan: (token: string) => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [state, setState] = useState<
    "idle" | "running" | "unsupported" | "denied" | "insecure"
  >("idle");

  useEffect(() => {
    // getUserMedia is secure-context only, so it is missing over plain HTTP on
    // a LAN address — the way a captain reaches this from the boundary. Saying
    // "no camera access" there sends them to Settings to grant a permission
    // that was never the problem.
    if (!isSecureContextAvailable() || !navigator.mediaDevices) setState("insecure");
    else if (!("BarcodeDetector" in window)) setState("unsupported");
  }, []);

  useEffect(() => {
    if (state !== "running") return;
    let stream: MediaStream | null = null;
    let stop = false;

    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const Detector = (window as any).BarcodeDetector;
        const detector = new Detector({ formats: ["qr_code"] });
        const tick = async () => {
          if (stop || !videoRef.current) return;
          try {
            const found = await detector.detect(videoRef.current);
            if (found?.[0]?.rawValue) {
              onScan(found[0].rawValue);
              stop = true;
              return;
            }
          } catch {
            // A frame that will not decode is not an error; try the next one.
          }
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      } catch {
        setState("denied");
      }
    })();

    return () => {
      stop = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [state, onScan]);

  if (state === "insecure") {
    return (
      <p className="muted">
        The camera needs an https address, so scanning is off over this LAN link. Paste
        their link instead, or search by name.
      </p>
    );
  }
  if (state === "unsupported") {
    return (
      <p className="muted">
        This browser cannot use the camera to read codes — Chrome and Edge can. Paste their
        link instead, or search by name.
      </p>
    );
  }
  if (state === "denied") {
    return <p className="muted">No camera access. Paste their link instead, or search by name.</p>;
  }
  return (
    <div>
      {state === "idle" ? (
        <button className="btn" type="button" onClick={() => setState("running")}>
          <Icon name="ball" size={16} /> Start the camera
        </button>
      ) : (
        <video ref={videoRef} className="qr-video" muted playsInline />
      )}
    </div>
  );
}
