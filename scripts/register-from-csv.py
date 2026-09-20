#!/usr/bin/env python3
"""Register clubs, members and users on a Fishers ring from one CSV.

Built for production, which is why it refuses to do anything by default: a run
without --apply prints the plan and changes nothing. Everything below follows
from the accounts being real, on a live system, belonging to real people.

    scripts/register-from-csv.py people.csv                     # plan only
    scripts/register-from-csv.py people.csv --apply             # do it
    BASE_URL=https://int.fishers.cloud scripts/register-from-csv.py p.csv --apply

CSV columns — `name` plus one of `email`/`phone` are the only required ones:

    name                the person
    email               their address (email or phone must be present)
    phone               E.164, e.g. +447700900123
    password            optional; generated and reported back when blank
    club                club to put them in; created if it does not exist
    club_sport          cricket|football|badminton|paddle|pickleball|tennis|other
                        (default cricket; only read when the club is created)
    club_visibility     invite_only|public (default invite_only, likewise)
    club_description    likewise
    role                club_admin|team_captain|team_vice_captain|member|guest
                        (default member; the club's creator is always its admin)
    team                optional team within the club, created if missing

The first row naming a club that does not exist creates it, and that person
owns it. Later rows naming the same club are added as members.

On verification: this asks the server whether it wants a code, and only then
tries. It never touches a database — the psql shortcut in seed-area.py works
because that database is on the same machine, which is exactly what is not
true of a ring. If the server does ask, supply the codes with --codes
(a second CSV of email,code) or run with --interactive and paste them.

Nothing is printed that would leak a credential: generated passwords go to the
results file, never to the terminal or a log.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import secrets
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

DEFAULT_BASE = os.environ.get("BASE_URL", "https://www.fishers.cloud")
API = "/api/v1"

SPORTS = {"cricket", "football", "badminton", "paddle", "pickleball", "tennis", "other"}
ROLES = {"club_admin", "team_captain", "team_vice_captain", "member", "guest"}
VISIBILITY = {"invite_only", "public"}

# Rings where a mistake is somebody's real account, not a row in a test database.
PRODUCTION_HOSTS = {"www.fishers.cloud", "fishers.cloud"}


class SkipRow(Exception):
    """Already there and not ours to change — not an error, just nothing to do."""


class ApiError(Exception):
    def __init__(self, method: str, path: str, status: int, body: str):
        self.status = status
        self.body = body
        # The API's own sentence where it has one — it is written for a person.
        try:
            detail = json.loads(body).get("message") or body
        except Exception:
            detail = body
        super().__init__(f"{method} {path} -> {status}: {detail[:300]}")


def call(base: str, method: str, path: str, body: Any = None, token: str | None = None,
         retries: int = 3) -> Any:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "fishers-register-from-csv/1")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            # 5xx and rate limits are worth another go; 4xx is our mistake.
            if (e.code >= 500 or e.code == 429) and attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise ApiError(method, path, e.code, text) from None
        except urllib.error.URLError as e:
            if attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise ApiError(method, path, 0, str(e.reason)) from None


def generate_password(n: int = 20) -> str:
    # Excludes nothing clever: length does the work, and the person can change
    # it. Mixed classes only because some validators still insist.
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(n))


@dataclass
class Row:
    line: int
    name: str
    email: str | None
    phone: str | None
    password: str | None
    club: str | None
    club_sport: str
    club_visibility: str
    club_description: str | None
    role: str
    team: str | None
    generated_password: bool = False
    # Filled in as the run proceeds.
    user_id: str | None = None
    token: str | None = None
    outcome: list[str] = field(default_factory=list)

    @property
    def who(self) -> str:
        return self.email or self.phone or self.name


EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_RE = re.compile(r"^\+[1-9]\d{6,14}$")


def parse(path: str) -> tuple[list[Row], list[str]]:
    """Read and validate the whole file before a single request goes out.

    Fail-fast on the network means half a club created and no record of which
    half. Every problem in the file is reported at once instead.
    """
    rows: list[Row] = []
    errors: list[str] = []
    seen_ids: dict[str, int] = {}

    with open(path, newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames or "name" not in {f.strip() for f in reader.fieldnames}:
            return [], [f"{path}: needs a header row with at least a 'name' column"]

        for raw in reader:
            line = reader.line_num
            get = lambda k, d="": (raw.get(k) or "").strip() or d  # noqa: E731

            name = get("name")
            email = get("email") or None
            phone = get("phone") or None
            if not name:
                errors.append(f"line {line}: name is required")
                continue
            if not email and not phone:
                errors.append(f"line {line}: {name} needs an email or a phone")
                continue
            if email and not EMAIL_RE.match(email):
                errors.append(f"line {line}: '{email}' is not an email address")
            if phone and not PHONE_RE.match(phone):
                errors.append(f"line {line}: '{phone}' is not an E.164 phone (+447700900123)")

            ident = (email or phone or "").lower()
            if ident in seen_ids:
                errors.append(f"line {line}: {ident} already appears on line {seen_ids[ident]}")
            else:
                seen_ids[ident] = line

            sport = get("club_sport", "cricket").lower()
            if sport not in SPORTS:
                errors.append(f"line {line}: club_sport '{sport}' is not one of {sorted(SPORTS)}")
            role = get("role", "member").lower()
            if role not in ROLES:
                errors.append(f"line {line}: role '{role}' is not one of {sorted(ROLES)}")
            vis = get("club_visibility", "invite_only").lower()
            if vis not in VISIBILITY:
                errors.append(f"line {line}: club_visibility '{vis}' is not one of {sorted(VISIBILITY)}")

            password = get("password") or None
            if password and len(password) < 8:
                errors.append(f"line {line}: password for {name} is shorter than 8 characters")

            rows.append(Row(
                line=line, name=name, email=email, phone=phone,
                password=password, club=get("club") or None,
                club_sport=sport, club_visibility=vis,
                club_description=get("club_description") or None,
                role=role, team=get("team") or None,
            ))

    return rows, errors


CODE_RE = re.compile(r"\b(\d{6})\b")


def code_from_mailpit(mailpit: str, address: str, attempts: int = 8,
                      delay: float = 1.0) -> str | None:
    """The code a local or staging ring just emailed, from the mail catcher.

    Polls, because signup sends the first code from a background task — the
    API answers before the mail is written, so looking once finds nothing and
    asking for a resend only earns a 429 telling you one is already on its way.

    Only ever reaches a Mailpit instance you point it at. Production sends
    through a real provider and has no such inbox, which is the point: there is
    no way for this to quietly read a stranger's mail.
    """
    url = f"{mailpit.rstrip('/')}/api/v1/search?query=" + urllib.parse.quote(f"to:{address}")
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                data = json.loads(r.read().decode())
            for msg in data.get("messages", []):
                # Fishers puts it in the subject: "453941 is your Fishers code".
                found = CODE_RE.search(msg.get("Subject") or "")
                if found:
                    return found.group(1)
        except Exception:
            pass
        if attempt < attempts - 1:
            time.sleep(delay)
    return None


def load_previous(path: str | None) -> dict[str, str]:
    """email/phone -> password, from an earlier run's results file.

    Without this a second run cannot sign in as anyone whose password this
    script invented, so re-running a partly-finished file stalls on everybody
    it already created — which is exactly when you want to re-run it.
    """
    if not path:
        return {}
    known: dict[str, str] = {}
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for raw in csv.DictReader(fh):
            who = (raw.get("email") or raw.get("phone") or "").strip().lower()
            pw = (raw.get("password") or "").strip()
            if who and pw:
                known[who] = pw
    return known


def load_codes(path: str | None) -> dict[str, str]:
    if not path:
        return {}
    codes: dict[str, str] = {}
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for raw in csv.DictReader(fh):
            who = (raw.get("email") or raw.get("phone") or "").strip().lower()
            code = (raw.get("code") or "").strip()
            if who and code:
                codes[who] = code
    return codes


def sign_up_or_sign_in(base: str, row: Row) -> str:
    """Create the account, or recognise one that is already there.

    Re-running the same file must not be destructive, and must not stop at the
    first person who already exists — a part-finished run is the normal way
    this gets used the second time.
    """
    password = row.password or generate_password()
    row.generated_password = row.password is None
    body: dict[str, Any] = {"name": row.name, "password": password}
    if row.email:
        body["email"] = row.email
    if row.phone:
        body["phone"] = row.phone

    try:
        res = call(base, "POST", "/auth/signup", body)
        row.password = password
        row.outcome.append("user created")
    except ApiError as e:
        if e.status not in (400, 409, 422):
            raise
        # Already registered. Only a known password gets us back in; a
        # generated one never matched an account we did not create.
        if not row.password:
            row.generated_password = False
            raise SkipRow(
                "already registered, and this run generated the password rather than "
                "reading it — pass --resume <results.csv> from the run that created them"
            ) from None
        res = call(base, "POST", "/auth/login",
                   {"identifier": row.email or row.phone, "password": row.password})
        row.outcome.append("user existed, signed in")

    row.token = res["access_token"]
    row.user_id = res["user"]["id"]
    return row.token


def satisfy_verification(base: str, row: Row, codes: dict[str, str], interactive: bool,
                         mailpit: str | None = None) -> None:
    """Only when the server actually asks. Never a database write."""
    status = call(base, "GET", "/me/verification", token=row.token)
    if not status.get("enabled"):
        return
    if (status.get("email") or {}).get("verified") or (status.get("phone") or {}).get("verified"):
        row.outcome.append("already verified")
        return

    channel = "email" if row.email else "phone"
    code = codes.get((row.email or row.phone or "").lower())
    if not code and mailpit and row.email:
        # Signup already sent one, so wait for that rather than asking again:
        # a resend inside the cooldown is a 429, not a second email.
        code = code_from_mailpit(mailpit, row.email)
        if not code:
            try:
                call(base, "POST", f"/me/verification/{channel}", {}, row.token, retries=1)
                code = code_from_mailpit(mailpit, row.email)
            except ApiError as e:
                if e.status != 429:
                    raise
                # Already on its way — wait it out rather than fail the row.
                code = code_from_mailpit(mailpit, row.email, attempts=20)
    if not code and interactive:
        call(base, "POST", f"/me/verification/{channel}", {}, row.token)
        code = input(f"  code sent to {row.who} — paste it: ").strip()
    if not code:
        row.outcome.append("NEEDS VERIFICATION (no code supplied)")
        return
    call(base, "POST", f"/me/verification/{channel}/confirm", {"code": code}, row.token)
    row.outcome.append(f"{channel} verified")


def ensure_club(base: str, row: Row, clubs: dict[str, str]) -> str | None:
    """Return the club id, creating it the first time the name is seen."""
    if not row.club:
        return None
    key = row.club.lower()
    if key in clubs:
        return clubs[key]

    # Already a member of one by that name? Then it is not ours to recreate.
    mine = call(base, "GET", "/me/clubs?page=1&per_page=100", token=row.token) or {}
    for item in (mine.get("items") or mine.get("data") or []):
        club = item.get("club") or item
        if (club.get("name") or "").lower() == key:
            clubs[key] = club["id"]
            row.outcome.append("club already existed")
            return club["id"]

    body = {
        "name": row.club,
        "sport_types": [row.club_sport],
        "visibility": row.club_visibility,
    }
    if row.club_description:
        body["description"] = row.club_description
    club = call(base, "POST", "/clubs", body, row.token)
    clubs[key] = club["id"]
    row.outcome.append(f"club created ({row.club_sport})")
    return club["id"]


def add_member(base: str, owner_token: str, club_id: str, row: Row) -> None:
    try:
        call(base, "POST", f"/clubs/{club_id}/members",
             {"user_id": row.user_id, "role": row.role}, owner_token)
        row.outcome.append(f"added to club as {row.role}")
    except ApiError as e:
        if e.status in (409, 400):
            row.outcome.append("already a club member")
        else:
            raise


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", help="the people to register")
    ap.add_argument("--base-url", default=DEFAULT_BASE, help=f"ring (default {DEFAULT_BASE})")
    ap.add_argument("--apply", action="store_true", help="actually do it (default: plan only)")
    ap.add_argument("--yes", action="store_true", help="skip the production confirmation")
    ap.add_argument("--codes", help="CSV of email,code for servers that ask for one")
    ap.add_argument("--interactive", action="store_true", help="prompt for verification codes")
    ap.add_argument("--mailpit", help="Mailpit base URL to read codes from (local/staging only, "
                                      "e.g. http://127.0.0.1:8025)")
    ap.add_argument("--resume", help="a previous results CSV, to reuse generated passwords")
    ap.add_argument("--out", help="results CSV (default <input>.results.csv)")
    ap.add_argument("--pause", type=float, default=0.3,
                    help="seconds between people, to stay polite (default 0.3)")
    args = ap.parse_args()

    base = args.base_url.rstrip("/")
    host = base.split("//", 1)[-1].split("/", 1)[0]

    rows, errors = parse(args.csv)
    if errors:
        print(f"{len(errors)} problem(s) in {args.csv}:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 2
    if not rows:
        print("nothing to do — the file has no rows", file=sys.stderr)
        return 2

    clubs_named = sorted({r.club for r in rows if r.club})
    print(f"== {args.csv} -> {base}")
    print(f"   {len(rows)} people, {len(clubs_named)} club(s): {', '.join(clubs_named) or 'none'}")
    if not args.apply:
        print("\n   PLAN ONLY — nothing will be created. Re-run with --apply.\n")
        for r in rows:
            bits = [f"line {r.line}: {r.name} <{r.who}>"]
            if r.club:
                bits.append(f"-> {r.club} as {r.role}")
            if not r.password:
                bits.append("(password generated)")
            print("   " + " ".join(bits))
        return 0

    if host in PRODUCTION_HOSTS and not args.yes:
        print(f"\n   {host} is PRODUCTION. This creates real accounts for real people.")
        if input("   Type the hostname to continue: ").strip() != host:
            print("   stopped.")
            return 1

    codes = load_codes(args.codes)
    previous = load_previous(args.resume)
    for r in rows:
        if not r.password:
            r.password = previous.get((r.email or r.phone or "").lower())
    club_ids: dict[str, str] = {}
    club_owner_token: dict[str, str] = {}
    failures = 0
    skipped = 0

    for r in rows:
        try:
            sign_up_or_sign_in(base, r)
            satisfy_verification(base, r, codes, args.interactive, args.mailpit)
            if r.club:
                key = r.club.lower()
                if key not in club_ids:
                    ensure_club(base, r, club_ids)
                    club_owner_token[key] = r.token or ""
                    r.role = "club_admin"  # whoever creates it runs it
                else:
                    owner = club_owner_token.get(key)
                    if owner:
                        add_member(base, owner, club_ids[key], r)
                    else:
                        r.outcome.append("SKIPPED club (no owner token this run)")
        except SkipRow as e:
            skipped += 1
            r.outcome.append(f"skipped: {e}")
        except ApiError as e:
            failures += 1
            r.outcome.append(f"FAILED: {e}")
        except Exception as e:  # noqa: BLE001
            failures += 1
            r.outcome.append(f"FAILED: {e}")
        print(f"   {r.name} <{r.who}>: {'; '.join(r.outcome) or 'nothing'}")
        time.sleep(args.pause)

    # Timestamped, and never overwritten. A results file holds the only copy of
    # every password this run generated; a later run writing over it destroys
    # the credentials for accounts that already exist and cannot be recreated.
    if args.out:
        out = args.out
        if os.path.exists(out):
            print(f"   {out} already exists — refusing to overwrite credentials.", file=sys.stderr)
            return 2
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out = f"{args.csv.rsplit('.', 1)[0]}.results-{stamp}.csv"
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["line", "name", "email", "phone", "user_id", "club", "role",
                    "password", "password_generated", "outcome"])
        for r in rows:
            w.writerow([r.line, r.name, r.email or "", r.phone or "", r.user_id or "",
                        r.club or "", r.role, r.password or "",
                        "yes" if r.generated_password else "no", "; ".join(r.outcome)])

    done = len(rows) - failures - skipped
    print(f"\n   {done}/{len(rows)} succeeded"
          + (f", {skipped} skipped" if skipped else "")
          + (f", {failures} failed" if failures else "") + ".")
    print(f"   results (and any generated passwords): {out}")
    if any(r.generated_password for r in rows):
        print("   that file contains credentials — deliver it and delete it.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
