"use client";

import { useState } from "react";
import {
  economy,
  extrasLine,
  howOut,
  overs,
  strikeRate,
  type Innings,
  type MatchState,
} from "@/lib/cricket";

/// The full scorecard: one innings at a time, the way a scorebook reads.
///
/// Everything here is already in the match state — dismissals carry the bowler
/// and fielder, and each fall of wicket carries the stand that ended with it —
/// so nothing is inferred or approximated.
export function Scorecard({
  st,
  nameOf,
}: {
  st: MatchState;
  nameOf: (id?: string | null) => string;
}) {
  const [shown, setShown] = useState(0);
  if (st.innings.length === 0) return null;
  const index = Math.min(shown, st.innings.length - 1);
  const inn = st.innings[index];
  const battingName = inn.batting === "home" ? st.home_name : st.away_name;
  const xi = inn.batting === "home" ? st.home_xi : st.away_xi;

  // Anyone in the XI who has not been to the crease.
  const faced = new Set(inn.batters.filter((b) => b.balls > 0 || b.out).map((b) => b.player_id));
  const atCrease = new Set([inn.striker_id, inn.non_striker_id].filter(Boolean) as string[]);
  const yetToBat = xi.filter((id) => !faced.has(id) && !atCrease.has(id));

  // Batters in the order they came in, which is the order they appear in the
  // innings' own list.
  const batted = inn.batters.filter(
    (b) => b.balls > 0 || b.out || atCrease.has(b.player_id)
  );

  return (
    <div className="panel">
      {st.innings.length > 1 && (
        <div className="innings-tabs" role="tablist" aria-label="Innings">
          {st.innings.map((i, n) => (
            <button
              key={n}
              role="tab"
              aria-selected={n === index}
              className={`innings-tab${n === index ? " active" : ""}`}
              type="button"
              onClick={() => setShown(n)}
            >
              <strong>{i.batting === "home" ? st.home_name : st.away_name}</strong>
              <span className="num">
                {i.runs}-{i.wickets} ({overs(i.legal_balls)})
              </span>
            </button>
          ))}
        </div>
      )}

      <h3 className="section-head">{battingName} batting</h3>
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>Batter</th>
              <th className="n">R</th>
              <th className="n">B</th>
              <th className="n">4s</th>
              <th className="n">6s</th>
              <th className="n">SR</th>
            </tr>
          </thead>
          <tbody>
            {batted.map((b) => (
              <tr key={b.player_id}>
                {/* The dismissal line already says "not out"; an asterisk is
                    how a scorebook marks it without repeating itself. */}
                <td>
                  <span className="cell-name">
                    {nameOf(b.player_id)}
                    {!b.out && atCrease.has(b.player_id) ? "\u00a0*" : ""}
                  </span>
                  <span className="cell-sub">{howOut(b, nameOf)}</span>
                </td>
                <td className="n"><strong>{b.runs}</strong></td>
                <td className="n">{b.balls}</td>
                <td className="n">{b.fours}</td>
                <td className="n">{b.sixes}</td>
                <td className="n">{strikeRate(b.runs, b.balls)}</td>
              </tr>
            ))}
            <tr>
              <td>
                <span className="cell-name">Extras</span>
                <span className="cell-sub">{extrasLine(inn)}</span>
              </td>
              <td className="n"><strong>{inn.extras}</strong></td>
              <td colSpan={4}></td>
            </tr>
            <tr>
              <td>
                <span className="cell-name"><strong>Total</strong></span>
                <span className="cell-sub">
                  {overs(inn.legal_balls)} ov
                  {inn.legal_balls > 0 &&
                    ` · RR ${((inn.runs * 6) / inn.legal_balls).toFixed(2)}`}
                </span>
              </td>
              <td className="n">
                <strong>
                  {inn.runs}-{inn.wickets}
                </strong>
              </td>
              <td colSpan={4}></td>
            </tr>
          </tbody>
        </table>
      </div>

      {yetToBat.length > 0 && (
        <>
          <h3 className="section-head">Yet to bat</h3>
          <ul className="chip-list">
            {yetToBat.map((id) => (
              <li key={id} className="tag">{nameOf(id)}</li>
            ))}
          </ul>
        </>
      )}

      <h3 className="section-head">Bowling</h3>
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>Bowler</th>
              <th className="n">O</th>
              <th className="n">M</th>
              <th className="n">R</th>
              <th className="n">W</th>
              <th className="n">Econ</th>
            </tr>
          </thead>
          <tbody>
            {inn.bowlers
              .filter((b) => b.balls > 0)
              .map((b) => (
                <tr key={b.player_id}>
                  <td>{nameOf(b.player_id)}</td>
                  <td className="n">{overs(b.balls)}</td>
                  <td className="n">{b.maidens}</td>
                  <td className="n">{b.runs}</td>
                  <td className="n"><strong>{b.wickets}</strong></td>
                  <td className="n">{economy(b.runs, b.balls)}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>

      {(inn.fall?.length ?? 0) > 0 && (
        <>
          <h3 className="section-head">Fall of wickets</h3>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Batter</th>
                  <th className="n">Score</th>
                  <th className="n">Over</th>
                </tr>
              </thead>
              <tbody>
                {inn.fall!.map((f, i) => (
                  <tr key={i}>
                    <td>{nameOf(f.batter_id)}</td>
                    <td className="n">
                      {f.score}-{f.wickets}
                    </td>
                    <td className="n">{f.over_ball}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <Partnerships inn={inn} nameOf={nameOf} />
    </div>
  );
}

/// Each stand, with the one still going shown last.
///
/// The runs and balls come straight off each fall of wicket, which records the
/// stand it ended; the unbroken stand is the innings' running one.
function Partnerships({
  inn,
  nameOf,
}: {
  inn: Innings;
  nameOf: (id?: string | null) => string;
}) {
  const stands = (inn.fall || []).map((f, i) => ({
    wicket: f.wickets,
    runs: f.partnership_runs,
    balls: f.partnership_balls,
    endedBy: f.batter_id,
    key: `f${i}`,
  }));
  const unbroken =
    !inn.complete && (inn.partnership_runs ?? 0) >= 0 && inn.striker_id
      ? [
          {
            wicket: inn.wickets + 1,
            runs: inn.partnership_runs ?? 0,
            balls: inn.partnership_balls ?? 0,
            endedBy: null as string | null,
            key: "live",
          },
        ]
      : [];
  const all = [...stands, ...unbroken];
  if (all.length === 0) return null;
  const biggest = Math.max(...all.map((s) => s.runs), 1);

  return (
    <>
      <h3 className="section-head">Partnerships</h3>
      <ul className="plain-list">
        {all.map((s) => (
          <li key={s.key} className="stand">
            <span className="stand-label">
              {s.wicket === 1 ? "1st" : s.wicket === 2 ? "2nd" : s.wicket === 3 ? "3rd" : `${s.wicket}th`} wkt
            </span>
            <span className="stand-bar" aria-hidden="true">
              <span style={{ width: `${Math.max(4, (s.runs / biggest) * 100)}%` }} />
            </span>
            <span className="num stand-runs">
              {s.runs} <span className="subtle">({s.balls})</span>
            </span>
            <span className="subtle stand-end">
              {s.endedBy ? `${nameOf(s.endedBy)} out` : "unbroken"}
            </span>
          </li>
        ))}
      </ul>
    </>
  );
}
