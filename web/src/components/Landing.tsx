import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";
import { Icon, type IconName } from "@/components/Icon";
import { brand } from "@/brand.generated";

/// Signed-out `/`: brand, what Fishers does, and how a club gets going.
/// Everything named here is a screen that exists in the app.
export function Landing() {
  return (
    <main id="main" className="lp">
      <section className="lp-hero">
        <div className="lp-hero-inner">
          <div className="lp-hero-copy">
            <p className="lp-brand">
              <BrandMark size={40} />
              <span>{brand.name}</span>
            </p>
            <h1>Run the club. Score the match.</h1>
            <p className="lp-lead">
              The multi-sport club app for fixtures, availability, selection, live
              scoring, and the people who keep a side going.
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
              Google, email or mobile. Already in? <Link href="/login">Sign in</Link>
            </p>
            <p className="lp-fine">
              Rather see it first? <Link href="/tour">Watch the 20-minute tour</Link> — a
              season on a phone, from sign-up to the last ball.
            </p>
          </div>
          <Scoreboard />
        </div>
      </section>

      <section className="lp-section lp-sports" aria-labelledby="lp-sports">
        <p className="lp-kicker">Built for club sport</p>
        <h2 id="lp-sports">Cricket first. Room for the rest of the club.</h2>
        <p className="lp-sub">
          {brand.name} is strongest on cricket — live ball-by-ball scoring and a shareable
          board — and the same club shell covers football, badminton, padel and the
          sessions you already run every week.
        </p>
      </section>

      <section className="lp-section" id="features" aria-labelledby="lp-features">
        <p className="lp-kicker">Features</p>
        <h2 id="lp-features">Everything a club season needs</h2>
        <p className="lp-sub">
          One place instead of spreadsheets, group-chat polls and a paper scorebook
          nobody can read by Tuesday.
        </p>
        <ul className="lp-feature-list">
          {FEATURES.map((f) => (
            <li className="lp-feature-row" key={f.title}>
              <span className="lp-feature-icon" aria-hidden="true">
                <Icon name={f.icon} size={22} />
              </span>
              <div>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section className="lp-section" aria-labelledby="lp-how">
        <p className="lp-kicker">How it works</p>
        <h2 id="lp-how">From sign-up to first ball</h2>
        <ol className="lp-steps">
          {STEPS.map((s, i) => (
            <li className="lp-step" key={s.title}>
              <span className="lp-step-num" aria-hidden="true">
                {String(i + 1).padStart(2, "0")}
              </span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="lp-section" aria-labelledby="lp-who">
        <p className="lp-kicker">Who it&apos;s for</p>
        <h2 id="lp-who">Secretaries, captains and players</h2>
        <div className="lp-roles">
          {ROLES.map((r) => (
            <article className="lp-role" key={r.name}>
              <h3>
                <Icon name={r.icon} size={20} /> {r.name}
              </h3>
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
        <p>Set the club up tonight and drop the invite in the WhatsApp group before nets.</p>
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

function Scoreboard() {
  return (
    <div
      className="lp-visual"
      role="img"
      aria-label={`Example of a live match scoreboard in ${brand.name}`}
    >
      <div className="lp-board" aria-hidden="true">
        <div className="lp-board-head">
          <span className="tag live">Live</span>
          <span>T20 · Sunday League</span>
        </div>
        <div className="lp-board-team done">
          <span>{brand.name} CC</span>
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
              <i key={i} className={`lp-ball b${b}`}>
                {b}
              </i>
            ))}
            <i className="lp-ball next lp-ball-pulse" />
            <i className="lp-ball next" />
          </div>
        </div>
        <div className="lp-board-bats">
          <p>
            <span>A. Khan</span>
            <b>58*</b>
            <em>41</em>
          </p>
          <p>
            <span>J. Patel</span>
            <b>12*</b>
            <em>9</em>
          </p>
        </div>
      </div>
    </div>
  );
}

const FEATURES: { icon: IconName; title: string; body: string }[] = [
  {
    icon: "calendar",
    title: "Fixtures & recurring sessions",
    body: "League games, nets, socials — schedule once and keep the whole club looking at the same calendar.",
  },
  {
    icon: "clock",
    title: "Availability & RSVP",
    body: "Ask who can play. Usual days are set once; each fixture is answered in one tap.",
  },
  {
    icon: "users",
    title: "Team selection",
    body: "Captains pick the eleven from who is actually free, then publish so the squad hears immediately.",
  },
  {
    icon: "bat",
    title: "Live ball-by-ball scoring",
    body: "One tap a ball on the phone at the boundary — shot and wagon wheel when you want them.",
  },
  {
    icon: "share",
    title: "Shareable live scoreboard",
    body: "Send a link on WhatsApp or Messages. Family and fans follow along without installing anything.",
  },
  {
    icon: "chart",
    title: "Season stats",
    body: "Batting, bowling and results update as matches finish — the table never waits on a spreadsheet.",
  },
  {
    icon: "chat",
    title: "Club chat & notifications",
    body: "Message a teammate, a team or the club. Alerts for invites, selections and upcoming fixtures.",
  },
  {
    icon: "link",
    title: "Invites & QR codes",
    body: "Drop a link in the group chat or show a QR at nets. Players join in seconds.",
  },
  {
    icon: "trophy",
    title: "Tournaments & public club page",
    body: "Run knockout days, and give the club a public page outsiders can find without an account.",
  },
  {
    icon: "shop",
    title: "Fees & club shop",
    body: "Match fees and kit or food orders with Stripe — less chasing on Saturday morning.",
  },
  {
    icon: "book",
    title: "Player profiles",
    body: "Sport, level, positions and reliability in one place so captains know who they are picking.",
  },
  {
    icon: "shield",
    title: "Roles that match the club",
    body: "Secretaries run the club, captains pick and score, players answer and play — permissions stay clear.",
  },
];

const STEPS = [
  {
    title: "Start your club",
    body: "Name it, pick your sports, and you are the secretary. Teams and fixtures hang off the club.",
  },
  {
    title: "Bring your players in",
    body: "Share the invite link or add people by email or phone. They join on the web or in the iOS app.",
  },
  {
    title: "Play, score, repeat",
    body: "Schedule a fixture, let the captain pick from availability, and score it live on a phone.",
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
    line: "Your club life, in your pocket.",
    gets: ["Say whether you can play in one tap", "Follow matches live", "Your season stats and profile"],
  },
];
