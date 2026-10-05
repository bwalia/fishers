#!/usr/bin/env python3
"""The Sher-E-Punjab T20 League schedule, as fixtures on clubs you already have.

Six franchises, the league's own 27 matches — 24 league games, two semi-finals
and the final — moved forward six weeks so every one of them is still to come.
Six weeks and not some other number because it is a whole number of weeks:
every match keeps the weekday and the start time the real schedule gave it.

The schedule is from https://sherepunjabt20.in/schedule/. The teams, grounds,
dates and order of play are the real league's.

This makes **no clubs, no teams and no accounts**. It only adds fixtures, and
only to clubs the accounts you give it already run, so it cannot duplicate a
franchise you already have. A franchise it cannot find, or finds twice, stops
the run and is named rather than guessed at.

Creating a fixture needs `manage_events` on the *home* club only — the away
side is referenced by id — so one secretary per franchise is enough, and one
account that is a secretary of all six is simplest.

    ./scripts/seed-punjab-t20.py \
      --api https://int.gullycricket.app \
      --login secretary@example.test:thepassword \
      --login another@example.test:thepassword

    --dry-run   says what it would create and writes nothing
    --club "Ludhiana Lions=719b47a0-..."   pins a franchise by id, for when
                                           two clubs share a name

Re-runnable: a fixture that already exists, matched on title and start, is
left alone rather than made twice.
"""

import argparse
import datetime as dt
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
LEAGUE = "Sher-E-Punjab T20 League 2026"
OVERS = 20
# A whole number of weeks, so every weekday and start time survives the move.
SHIFT = dt.timedelta(weeks=6)

FRANCHISES = ["Amritsar Soormas", "Mohali Kings", "Jalandhar Warriors",
              "Fazilka Falcons", "Bathinda Royals", "Ludhiana Lions"]

GROUNDS = {
    "mullanpur": ("Maharaja Yadavindra Singh International Cricket Stadium",
                  "Mullanpur, New Chandigarh, Punjab", 30.7906, 76.6553),
    "mohali": ("I.S. Bindra Stadium", "Sector 63, SAS Nagar, Mohali, Punjab", 30.6909, 76.7379),
}

# The league's own order of play. (home, away, date, start, ground, stage)
FIXTURES = [
    ("Amritsar Soormas", "Mohali Kings", "2026-08-30", "20:00", "mullanpur", None),
    ("Jalandhar Warriors", "Fazilka Falcons", "2026-08-31", "13:00", "mullanpur", None),
    ("Mohali Kings", "Bathinda Royals", "2026-08-31", "19:00", "mullanpur", None),
    ("Bathinda Royals", "Ludhiana Lions", "2026-09-01", "13:00", "mullanpur", None),
    ("Jalandhar Warriors", "Amritsar Soormas", "2026-09-01", "19:00", "mullanpur", None),
    ("Mohali Kings", "Ludhiana Lions", "2026-09-02", "13:00", "mullanpur", None),
    ("Fazilka Falcons", "Amritsar Soormas", "2026-09-02", "19:00", "mullanpur", None),
    ("Bathinda Royals", "Jalandhar Warriors", "2026-09-03", "13:00", "mullanpur", None),
    ("Fazilka Falcons", "Mohali Kings", "2026-09-03", "19:00", "mullanpur", None),
    ("Bathinda Royals", "Amritsar Soormas", "2026-09-04", "13:00", "mullanpur", None),
    ("Ludhiana Lions", "Jalandhar Warriors", "2026-09-04", "19:00", "mullanpur", None),
    ("Fazilka Falcons", "Bathinda Royals", "2026-09-05", "13:00", "mullanpur", None),
    ("Jalandhar Warriors", "Mohali Kings", "2026-09-05", "19:00", "mullanpur", None),
    ("Bathinda Royals", "Jalandhar Warriors", "2026-09-06", "13:00", "mullanpur", None),
    ("Ludhiana Lions", "Fazilka Falcons", "2026-09-06", "19:00", "mullanpur", None),
    ("Mohali Kings", "Ludhiana Lions", "2026-09-07", "13:00", "mullanpur", None),
    ("Fazilka Falcons", "Amritsar Soormas", "2026-09-07", "19:00", "mullanpur", None),
    ("Amritsar Soormas", "Mohali Kings", "2026-09-08", "13:00", "mullanpur", None),
    ("Jalandhar Warriors", "Ludhiana Lions", "2026-09-08", "19:00", "mullanpur", None),
    ("Ludhiana Lions", "Fazilka Falcons", "2026-09-09", "13:00", "mullanpur", None),
    ("Mohali Kings", "Bathinda Royals", "2026-09-09", "19:00", "mullanpur", None),
    ("Amritsar Soormas", "Jalandhar Warriors", "2026-09-10", "13:00", "mullanpur", None),
    ("Fazilka Falcons", "Bathinda Royals", "2026-09-10", "19:00", "mullanpur", None),
    ("Amritsar Soormas", "Ludhiana Lions", "2026-09-11", "19:00", "mullanpur", None),
    ("Mohali Kings", "Amritsar Soormas", "2026-09-12", "13:00", "mohali", "Semi-Final 1"),
    ("Ludhiana Lions", "Jalandhar Warriors", "2026-09-12", "19:00", "mohali", "Semi-Final 2"),
    ("Amritsar Soormas", "Ludhiana Lions", "2026-09-13", "19:00", "mohali", "Final"),
]


class ApiError(RuntimeError):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path} -> {status}: {body[:300]}")
        self.status = status


class Api:
    def __init__(self, base):
        self.v1 = base.rstrip("/") + "/api/v1"

    def __call__(self, method, path, body=None, token=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            self.v1 + path, data=data, method=method,
            headers={"Content-Type": "application/json",
                     **({"Authorization": f"Bearer {token}"} if token else {})})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise ApiError(method, path, e.code, e.read().decode(errors="replace")) from None


def rows(data):
    return data["items"] if isinstance(data, dict) and "items" in data else (data or [])


def when(date, time):
    day = dt.date.fromisoformat(date) + SHIFT
    hour, minute = (int(part) for part in time.split(":"))
    return dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=IST)


def iso(moment):
    return moment.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def title_of(home, away, stage):
    return f"{stage} — {home} v {away}" if stage else f"{home} v {away}"


def sign_in(api, logins):
    """Who can act for which club. A secretary of the home club is all a
    fixture needs, so this collects every club each login runs."""
    desks = []
    for email, password in logins:
        got = api("POST", "/auth/login", {"email": email, "password": password})
        token, user_id = got["access_token"], got["user"]["id"]
        runs = {}
        for club in rows(api("GET", "/me/clubs?per_page=100", None, token)):
            cid = club.get("id") or club.get("club_id")
            role = api("GET", f"/clubs/{cid}/my-role", None, token)
            if role.get("is_secretary") or "manage_events" in (role.get("permissions") or []):
                runs.setdefault(club["name"], []).append(cid)
        desks.append({"email": email, "token": token, "user_id": user_id, "runs": runs})
        print(f"  {email} runs {len(runs)}: {', '.join(sorted(runs)) or 'nothing'}")
    return desks


def resolve(desks, pinned):
    """One club id per franchise, or a refusal that names the problem. Two
    clubs with the same name is the trap this exists for."""
    found, trouble = {}, []
    for name in FRANCHISES:
        if name in pinned:
            found[name] = pinned[name]
            continue
        ids = {cid for d in desks for cid in d["runs"].get(name, [])}
        if len(ids) == 1:
            found[name] = ids.pop()
        elif not ids:
            trouble.append(f"  {name}: no club of that name is run by any login given")
        else:
            listed = "\n      ".join(sorted(ids))
            trouble.append(f"  {name}: {len(ids)} clubs share this name — pin one with "
                           f'--club "{name}=<id>"\n      {listed}')
    if trouble:
        sys.exit("cannot tell which club is which:\n" + "\n".join(trouble))
    return found


def desk_for(desks, club_id):
    for d in desks:
        if any(club_id in ids for ids in d["runs"].values()):
            return d
    return None


def ground_on(api, desk, club_id, key, cache):
    """The fixture's ground has to be a venue of the club hosting it."""
    if (club_id, key) in cache:
        return cache[(club_id, key)]
    name, address, lat, lng = GROUNDS[key]
    have = {v["name"]: v["id"] for v in rows(api("GET", f"/clubs/{club_id}/venues", None, desk["token"]))}
    vid = have.get(name) or api("POST", f"/clubs/{club_id}/venues",
                                {"name": name, "address": address, "lat": lat, "lng": lng},
                                desk["token"])["id"]
    cache[(club_id, key)] = vid
    return vid


def existing(api, desk, club_id):
    by_key = {}
    for event in rows(api("GET", f"/events?club_id={club_id}&per_page=200", None, desk["token"])):
        start = dt.datetime.fromisoformat(event["start_at"].replace("Z", "+00:00"))
        by_key[(event["title"], start)] = event
    return by_key


def main(opts):
    api = Api(opts.api)
    print(f"{LEAGUE} → {opts.api}")
    print(f"  every date moved on by {SHIFT.days} days, so the weekdays and start times hold\n")

    desks = sign_in(api, opts.login)
    clubs = resolve(desks, opts.club)
    print()
    for name in FRANCHISES:
        print(f"  {name:<22} {clubs[name]}")

    teams, venues, seen = {}, {}, {}
    made = skipped = 0
    print()
    for index, (home, away, date, time, ground, stage) in enumerate(FIXTURES, start=1):
        start = when(date, time)
        title = title_of(home, away, stage)
        desk = desk_for(desks, clubs[home])
        if desk is None:
            sys.exit(f"no login given runs {home}, which hosts {title}")
        if clubs[home] not in seen:
            seen[clubs[home]] = existing(api, desk, clubs[home])
            sides = rows(api("GET", f"/clubs/{clubs[home]}/teams", None, desk["token"]))
            teams[clubs[home]] = sides[0]["id"] if sides else None

        label = stage or f"match {index}"
        if (title, start) in seen[clubs[home]]:
            skipped += 1
            print(f"  {start:%a %d %b %H:%M}  {title:<52} {label}  already there")
            continue
        if opts.dry_run:
            made += 1
            print(f"  {start:%a %d %b %H:%M}  {title:<52} {label}  would create")
            continue

        event = api("POST", "/events", {
            "club_id": clubs[home], "sport": "cricket", "title": title,
            "event_subtype": "league_match", "opponent_club_id": clubs[away],
            "team_id": teams[clubs[home]],
            "venue_id": ground_on(api, desk, clubs[home], ground, venues),
            "start_at": iso(start), "end_at": iso(start + dt.timedelta(hours=4)),
            "capacity": 16, "fee_currency": "INR", "guests_allowed": 0,
            "tickets_public": False, "status": "scheduled", "created_by": desk["user_id"],
            "metadata": {"competition": f"{LEAGUE}{' · ' + stage if stage else f', match {index}'}",
                         "opposition": away, "home_name": home},
        }, desk["token"])
        # Made now so the fixture opens on the toss rather than asking how many
        # overs. Idempotent: it hands back the match if one exists.
        api("POST", f"/events/{event['id']}/cricket-match",
            {"overs_limit": OVERS, "home_name": home, "away_name": away,
             "opponent_club_id": clubs[away]}, desk["token"])
        made += 1
        print(f"  {start:%a %d %b %H:%M}  {title:<52} {label}  created")

    verb = "would create" if opts.dry_run else "created"
    print(f"\n  {len(FIXTURES)} fixtures: {made} {verb}, {skipped} already there, {OVERS} overs a side")
    if not opts.dry_run:
        print("  each one is a scheduled match with no toss and no XI named — "
              "the playing is yours to do")


def login_arg(text):
    email, sep, password = text.partition(":")
    if not sep or not email or not password:
        raise argparse.ArgumentTypeError("give a login as email:password")
    return (email, password)


def club_arg(text):
    name, sep, club_id = text.partition("=")
    if not sep or name not in FRANCHISES:
        raise argparse.ArgumentTypeError(f'give a club as "<franchise>=<id>", one of {FRANCHISES}')
    return (name, club_id)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--api", default="http://127.0.0.1:7312", help="base URL of the API")
    p.add_argument("--login", action="append", type=login_arg, required=True, metavar="EMAIL:PASSWORD",
                   help="an account that runs one or more of the franchises. Repeatable.")
    p.add_argument("--club", action="append", type=club_arg, default=[], metavar="NAME=ID",
                   help="pin a franchise to a club id, for when two clubs share a name")
    p.add_argument("--dry-run", action="store_true", help="say what would happen and write nothing")
    opts = p.parse_args()
    opts.club = dict(opts.club)
    try:
        main(opts)
    except ApiError as e:
        sys.exit(f"stopped: {e}")
