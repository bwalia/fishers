"use client";

import { useEffect, useRef, useState } from "react";
import { api, type OpponentIdentity } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { isSecureContextAvailable } from "@/lib/clipboard";
import { useT } from "@/lib/i18n/provider";
import { brand } from "@/brand.generated";

/// Three ways to name the other side, because a ground is not a laboratory:
/// scan their code, paste the link they sent, or search for them by name. A
/// club that is not in Fishers at all is typed in and stays a plain name.
///
/// Your own club is never the opposition. Two of its teams can be, when it has
/// two — a trial match, the 1st XI against the 2nd.
export function OppositionPicker({
  onPick,
  homeClubId,
  ownTeamsAllowed = false,
  initialToken,
}: {
  onPick: (identity: OpponentIdentity | null, name: string) => void;
  /// The club you are playing for.
  homeClubId?: string;
  /// It has two or more teams, so one of them may be the opposition.
  ownTeamsAllowed?: boolean;
  /// A code they already have — they followed its link. Looked up here rather
  /// than by the page, so it meets the same rules as one typed or scanned.
  initialToken?: string;
}) {
  const t = useT();
  const [tab, setTab] = useState<"scan" | "code" | "search">("search");
  /// What is currently chosen, so the result that was clicked can say so.
  ///
  /// The picker used to hand the choice to the parent and forget it, which
  /// left the thing you clicked looking exactly as it did before — the only
  /// confirmation was a line of prose two fields further down, past an empty
  /// input. People clicked, saw nothing change, and concluded it had not
  /// worked.
  const [picked, setPicked] = useState<OpponentIdentity | null>(null);
  const [code, setCode] = useState("");
  const [query, setQuery] = useState("");
  /// A club that is not on Fishers at all: a name and nothing else.
  const [plain, setPlain] = useState("");
  const [results, setResults] = useState<OpponentIdentity[]>([]);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const isOurs = (r: OpponentIdentity) => !!homeClubId && r.club_id === homeClubId;
  /// Whether this can be the opposition at all.
  const allowed = (r: OpponentIdentity) => !isOurs(r) || (r.kind === "team" && ownTeamsAllowed);
  const ownClubNote = ownTeamsAllowed
    ? t("le.that_s_your_own_club_to_play_within_it")
    : t("le.that_s_your_own_club_a_club_can_t_play");

  const resolve = async (token: string) => {
    setBusy(true);
    setNote(null);
    try {
      const identity = await api<OpponentIdentity>("POST", "/opponents/lookup", { token });
      if (!allowed(identity)) {
        setNote(ownClubNote);
        return;
      }
      setPlain("");
      setPicked(identity);
      onPick(identity, identity.name);
      setNote(t("opp.matched", { name: identity.name }));
    } catch {
      setNote(t("le.that_code_is_not_one_of_ours_try_searc"));
    } finally {
      setBusy(false);
    }
  };

  const looked = useRef<string | null>(null);
  useEffect(() => {
    // Only once the club is known: until then "is that our own club?" has no
    // answer, and the picker would accept one it is meant to refuse.
    if (!initialToken || !homeClubId || looked.current === initialToken) return;
    looked.current = initialToken;
    void resolve(initialToken);
    // resolve is stable enough for this: it only reads props.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialToken, homeClubId]);

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
      <div className="tabs" role="tablist" aria-label={t("rest.find_the_opposition")}>
        {(["search", "scan", "code"] as const).map((each) => (
          <button
            key={each}
            role="tab"
            aria-selected={tab === each}
            className={`tab${tab === each ? " active" : ""}`}
            type="button"
            onClick={() => setTab(each)}
          >
            {each === "search" ? t("rest.search") : each === "scan" ? t("le.scan_a_code") : t("le.paste_a_link")}
          </button>
        ))}
      </div>

      {/* Once a club is chosen the search has done its job. Leaving the box,
          the result list and the "or just their name" field all on screen was
          the complaint: the list still offered clubs that were no longer
          relevant, and the empty name field read as though nothing had been
          picked. This is what was chosen and how to change it, and nothing
          else. */}
      {tab === "search" && picked && (
        <div className="opp-chosen">
          <p className="opp-chosen-name">
            <Icon name="check" size={16} />
            <strong>{t("opp.playing", { name: picked.name })}</strong>
            <span className="subtle">{picked.kind}</span>
          </p>
          <p className="subtle">{t("opp.on_brand_too", { brand: brand.name })}</p>
          <button
            className="btn ghost sm"
            type="button"
            onClick={() => {
              // Back to the search they had — same term, same results — rather
              // than a blank box they have to start again from.
              setPicked(null);
              onPick(null, "");
              setNote(null);
            }}
          >
            {t("opp.change")}
          </button>
        </div>
      )}

      {tab === "search" && !picked && (
        <>
          <label>
            {t("rest.club_or_team_name")}
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t("rest.hemel_watford")}
            />
          </label>
          <ul className="plain-list" style={{ marginTop: "var(--s2)" }}>
            {results.filter(allowed).map((r) => (
              <li key={r.id}>
                <button
                  className="btn sm"
                  type="button"
                  onClick={() => {
                    // The results stay in state deliberately. They are hidden
                    // while something is chosen, so "Change" puts the list
                    // back exactly as it was rather than making somebody type
                    // their search again.
                    setPlain("");
                    setPicked(r);
                    onPick(r, r.name);
                    setNote(null);
                  }}
                >
                  {r.name}
                  <span className="subtle"> {r.kind}</span>
                </button>
              </li>
            ))}
            {query.trim().length >= 2 && results.filter(allowed).length === 0 && (
              // Search only ever finds clubs that chose "anyone can find it".
              // A club set to invite only is deliberately kept out of it, so
              // "nobody by that name" read as though they were not on Fishers
              // at all — and left no way forward.
              <li className="muted">
                {t("opp.nobody_by_that_name")}{" "}
                <strong>{t("rest.invite_only")}</strong> {t("rest.is_kept_out_of_search_ask_them_for_the")}
              </li>
            )}
          </ul>
          {results.some((r) => !allowed(r)) && <p className="subtle">{ownClubNote}</p>}

          {/* Most opposition clubs are not on Fishers, and a fixture against
              one still has to be schedulable. This used to say "type it as a
              plain name below" with no field below it, so a club whose
              opponent was not a member could not schedule a match at all. */}
          <label style={{ marginTop: "var(--s3)" }}>
            {t("rest.or_just_their_name")}
            <input
              value={plain}
              onChange={(e) => {
                setPlain(e.target.value);
                // A typed name and a matched club are alternatives, so typing
                // clears whatever was matched — otherwise the fixture is
                // scheduled against the club they abandoned.
                setPicked(null);
                onPick(null, e.target.value);
                setNote(null);
              }}
              placeholder={t("rest.hackney_wanderers")}
            />
            <span className="subtle">
              {t("rest.they_will_not_be_asked_who_is_availabl")}
            </span>
          </label>
        </>
      )}

      {tab === "scan" && <QrScanner onScan={resolve} />}

      {tab === "code" && (
        <div className="field-row">
          <label>
            {t("rest.their_code_or_link")}
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder={t("rest.https_play_abc123_or_just_the_code")}
            />
          </label>
          <button
            className="btn"
            type="button"
            disabled={!code.trim() || busy}
            onClick={() => resolve(code.trim())}
          >
            {busy ? t("le.looking") : t("opp.match_button")}
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
  const t = useT();
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
        {t("rest.the_camera_needs_an_https_address_so_s")}
      </p>
    );
  }
  if (state === "unsupported") {
    return (
      <p className="muted">
        {t("rest.this_browser_cannot_use_the_camera_to")}
      </p>
    );
  }
  if (state === "denied") {
    return <p className="muted">{t("rest.no_camera_access_paste_their_link_inst")}</p>;
  }
  return (
    <div>
      {state === "idle" ? (
        <button className="btn" type="button" onClick={() => setState("running")}>
          <Icon name="ball" size={16} /> {t("rest.start_the_camera")}
        </button>
      ) : (
        <video ref={videoRef} className="qr-video" muted playsInline />
      )}
    </div>
  );
}
