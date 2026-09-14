import Link from "next/link";
import { Icon, type IconName } from "@/components/Icon";

/// What a signed-out visitor sees at `/`: what Fishers is, who it is for and
/// how a club gets going. Everything promised here is a screen that exists.
export function Landing() {
  return (
    <main id="main" className="lp">
      <section className="lp-hero">
        <div className="lp-hero-copy">
          <p className="lp-eyebrow">
            <span aria-hidden="true" /> The club app for grassroots cricket
          </p>
          <h1>
            Run your club.
            <br />
            <span className="lp-accent">Score every ball.</span>
          </h1>
          <p className="lp-lead">
            Fishers puts fixtures, availability, team selection, live ball-by-ball scoring and
            season stats in one place — so the secretary, the captains and every player are
            reading from the same scorebook.
          </p>
          <div className="lp-actions">
            <Link className="btn primary lp-btn" href="/register?as=secretary">
              <Icon name="plus" size={18} /> Start your club
            </Link>
            <Link className="btn lp-btn" href="/register?as=player">
              I play for a club
            </Link>
          </div>
          <p className="lp-fine">
            Sign up with Google, an email address or a mobile number. Already in?{" "}
            <Link href="/login">Sign in</Link>
          </p>
        </div>

        <Scoreboard />
      </section>

      <section className="lp-section" aria-labelledby="lp-what">
        <p className="lp-kicker">What it does</p>
        <h2 id="lp-what">Everything a club season needs, in one app</h2>
        <p className="lp-sub">
          No more spreadsheets, group-chat polls and a paper scorebook that nobody can read by
          Tuesday.
        </p>
        <div className="lp-features">
          {FEATURES.map((f) => (
            <article className="lp-feature" key={f.title}>
              <span className="lp-feature-icon"><Icon name={f.icon} size={22} /></span>
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="lp-section" aria-labelledby="lp-how">
        <p className="lp-kicker">How it works</p>
        <h2 id="lp-how">From sign-up to first ball in three steps</h2>
        <ol className="lp-steps">
          {STEPS.map((s, i) => (
            <li className="lp-step" key={s.title}>
              <span className="lp-step-num">{String(i + 1).padStart(2, "0")}</span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="lp-section" aria-labelledby="lp-who">
        <p className="lp-kicker">Who it&apos;s for</p>
        <h2 id="lp-who">Made for everyone at the club</h2>
        <div className="lp-roles">
          {ROLES.map((r) => (
            <article className="lp-role" key={r.name}>
              <span className="lp-feature-icon"><Icon name={r.icon} size={22} /></span>
              <h3>{r.name}</h3>
              <p className="lp-role-line">{r.line}</p>
              <ul>
                {r.gets.map((g) => (
                  <li key={g}>
                    <Icon name="check" size={16} /> {g}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </section>

      <section className="lp-cta" aria-labelledby="lp-cta">
        <h2 id="lp-cta">Ready for the new season?</h2>
        <p>Set your club up tonight and have the invite link in the WhatsApp group before nets.</p>
        <div className="lp-actions">
          <Link className="btn primary lp-btn" href="/register?as=secretary">
            <Icon name="plus" size={18} /> Start your club
          </Link>
          <Link className="btn lp-btn" href="/register?as=player">
            Join as a player
          </Link>
        </div>
      </section>
    </main>
  );
}

/// An illustration of the live board, drawn in markup so it follows the theme.
function Scoreboard() {
  return (
    <div className="lp-visual" role="img" aria-label="Example of a live match scoreboard in Fishers">
      <div className="lp-board" aria-hidden="true">
        <div className="lp-board-head">
          <span className="tag live">Live</span>
          <span>T20 · Sunday League</span>
        </div>
        <div className="lp-board-team done">
          <span>Fishers CC</span>
          <strong>168/6</strong>
          <em>20 ov</em>
        </div>
        <div className="lp-board-team">
          <span>Riverside CC</span>
          <strong>142/4</strong>
          <em>18.4 ov</em>
        </div>
        <p className="lp-board-need">Riverside need 27 runs from 8 balls</p>
        <div className="lp-board-over">
          <span>This over</span>
          <div>
            {["1", "4", "W", "6"].map((b, i) => (
              <i key={i} className={`lp-ball b${b}`}>{b}</i>
            ))}
            <i className="lp-ball next" />
            <i className="lp-ball next" />
          </div>
        </div>
        <div className="lp-board-bats">
          <p><span>A. Khan</span><b>58*</b><em>41</em></p>
          <p><span>J. Patel</span><b>12*</b><em>9</em></p>
        </div>
      </div>

      <div className="lp-float one" aria-hidden="true">
        <span className="lp-float-icon"><Icon name="users" size={16} /></span>
        <div>
          <strong>Side picked</strong>
          <span>14 available · 11 selected</span>
        </div>
      </div>
      <div className="lp-float two" aria-hidden="true">
        <span className="lp-float-icon gold"><Icon name="share" size={16} /></span>
        <div>
          <strong>Live link shared</strong>
          <span>Anyone can follow — no app needed</span>
        </div>
      </div>
    </div>
  );
}

const FEATURES: { icon: IconName; title: string; body: string }[] = [
  {
    icon: "bat",
    title: "Live ball-by-ball scoring",
    body: "One tap a ball, with the shot and wagon wheel if you want them. Hand the book to the other side at the innings break.",
  },
  {
    icon: "calendar",
    title: "Fixtures & availability",
    body: "Schedule a match and every player is asked if they can play. Usual days are set once, not every week.",
  },
  {
    icon: "users",
    title: "Team selection",
    body: "Captains pick the eleven from who is actually available, and the squad hears the moment it's published.",
  },
  {
    icon: "share",
    title: "A link anyone can follow",
    body: "Share a live scoreboard to WhatsApp, email or Messages. Family and fans watch along without an account.",
  },
  {
    icon: "chart",
    title: "Stats that keep themselves",
    body: "Batting, bowling and club results are written as matches finish — the season table is never out of date.",
  },
  {
    icon: "chat",
    title: "Chat & notifications",
    body: "Message a teammate, a team or the whole club, with alerts for invites, selections and fixtures.",
  },
];

const STEPS = [
  {
    title: "Start your club",
    body: "Give it a name and pick your sports. You become the secretary — teams, members and fixtures hang off the club.",
  },
  {
    title: "Bring your players in",
    body: "Drop the invite link in the club WhatsApp group, or add people by email or phone. Players join in seconds.",
  },
  {
    title: "Play, score, repeat",
    body: "Schedule a fixture, let the captain pick the side from who's available, and score it live on a phone.",
  },
];

const ROLES: { icon: IconName; name: string; line: string; gets: string[] }[] = [
  {
    icon: "shield",
    name: "Secretaries",
    line: "Run the club without chasing anyone.",
    gets: ["Teams, members and roles", "Invite links and QR codes", "Fixtures, tournaments and a club page"],
  },
  {
    icon: "trophy",
    name: "Captains",
    line: "Know your side before the toss.",
    gets: ["Availability at a glance", "Pick and publish the squad", "Run the scorebook on match day"],
  },
  {
    icon: "ball",
    name: "Players",
    line: "Everything about your cricket, in your pocket.",
    gets: ["Say whether you can play in one tap", "Follow matches live", "Your own season stats and profile"],
  },
];
