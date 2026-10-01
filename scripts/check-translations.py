#!/usr/bin/env python3
"""Fail if the web app shows English on a Punjabi page, or a key on any page.

The static part is cheap and catches the common regression: a new key in
`en.ts` that nobody translated, a key whose Punjabi value is still its English,
or a key rendered as a bare string instead of through `t()`.

The runtime part is what actually found the last hundred strings. A sentence
split around an interpolated value — "Over {n} done — who bowls next?" — is
neither a string literal nor a whole JSX text node, so no amount of grepping
sees it. Loading the page and looking at the text does.

Static only, no browser needed:

    python3 scripts/check-translations.py

With the runtime walk, which needs a built web app, the API, and a browser:

    cd web && npx next build && npx next start -p 3123 &
    /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\
      --headless=new --remote-debugging-port=9222 --user-data-dir=/tmp/i18n-profile &
    python3 scripts/check-translations.py --walk --email you@club.test --password ...

The account only has to exist; what it can see does not matter, because the
check is about the words on the page rather than the data behind them.
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent / "web"
I18N = WEB / "src" / "lib" / "i18n"

GURMUKHI = re.compile(r"[਀-੿]")
ENTRY = re.compile(r'^  "([^"]+)": (".*?"),$', re.M)

# Latin that stays Latin on a Punjabi page: brands, governing bodies, the
# scorebook's own abbreviations, and legal names that are not ours to translate.
KEEPS_LATIN = re.compile(
    r"^(FISHERS|Fishers|ECB|Play|Cricket|Play-Cricket|Stripe|Google|Apple|WhatsApp|ICO|"
    r"UK|GDPR|T20|T10|CC|XI|QR|DLS|SR|NO|HS|Avg|Econ|Wkts|Mdns|Inns|Ct|St|"
    r"PLATFORM_ADMIN_EMAILS|ico|org|uk|http|https|com|cloud|test|example|invalid)$"
)


def dictionaries():
    """Both dictionaries as {key: raw JSON value}, in file order."""
    return {
        name: dict(ENTRY.findall((I18N / f"{name}.ts").read_text()))
        for name in ("en", "pa")
    }


def check_dictionaries(problems):
    dicts = dictionaries()
    en, pa = dicts["en"], dicts["pa"]

    for name in ("en", "pa"):
        keys = re.findall(r'^  "([^"]+)":', (I18N / f"{name}.ts").read_text(), re.M)
        for key in {k for k in keys if keys.count(k) > 1}:
            problems.append(f"{name}.ts: duplicate key {key} — the last one silently wins")

    for key in en:
        if key not in pa:
            problems.append(f"pa.ts: no translation for {key}")
    for key in pa:
        if key not in en:
            problems.append(f"pa.ts: {key} is not a key in en.ts")

    # A Punjabi value with no Gurmukhi in it is usually English that was copied
    # across and never translated. Emails, URLs and pure slot templates have
    # nothing to translate, so they are allowed through.
    for key, value in pa.items():
        if GURMUKHI.search(value):
            continue
        prose = re.sub(r"\{[^}]*\}", "", value)
        if not re.search(r"[A-Za-z]{3,}", prose):
            continue
        if re.search(r"[@/]|\bhttp", prose):
            continue
        if all(KEEPS_LATIN.match(w) for w in re.findall(r"[A-Za-z]+", prose)):
            continue
        problems.append(f"pa.ts: {key} still reads as English — {value}")


def check_bare_keys(problems):
    """A key rendered as a string rather than passed to `t()`.

    `{"tn.overs_an_innings"}` compiles, renders, and puts the key itself on the
    page. It shipped that way once, thirty-one times in one component.
    """
    for path in sorted((WEB / "src").rglob("*.tsx")):
        if "lib/i18n" in str(path):
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            for m in re.finditer(r'\{\s*"([a-z][a-z0-9_]*\.[a-z0-9_.]+)"\s*\}', line):
                rel = path.relative_to(WEB.parent)
                problems.append(f"{rel}:{n}: {m.group(1)} is rendered, not translated")


class Tab:
    """One browser tab over CDP, same shape as scripts/audit-screens.py."""

    def __init__(self, port):
        from websocket import create_connection

        pages = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
        page = next(t for t in pages if t["type"] == "page")
        self.ws = create_connection(
            page["webSocketDebuggerUrl"], timeout=40, suppress_origin=True
        )
        self.i = 0
        self.send("Runtime.enable")
        self.send("Page.enable")

    def send(self, method, **params):
        self.i += 1
        self.ws.send(json.dumps({"id": self.i, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.i:
                return msg.get("result", {})

    def js(self, expr):
        got = self.send(
            "Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True
        )
        return got.get("result", {}).get("value")

    def go(self, url, settle):
        self.send("Page.navigate", url=url)
        time.sleep(settle)
        return self.js("document.body ? document.body.innerText : ''") or ""


PAGES = [
    "/", "/clubs", "/events", "/availability", "/chat", "/notifications",
    "/profile", "/score", "/scores", "/shop", "/shop/sell", "/stats",
    "/tournaments", "/hire", "/tour", "/privacy", "/welcome", "/login",
    "/register", "/admin", "/admin/users",
]


def check_pages(problems, args):
    keys = set(dictionaries()["en"])
    tokens = json.loads(
        subprocess.run(
            ["curl", "-s", "-X", "POST", f"{args.api}/auth/login",
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"email": args.email, "password": args.password})],
            capture_output=True, text=True, check=True,
        ).stdout
    )
    if "access_token" not in tokens:
        problems.append(f"could not sign in as {args.email}: {tokens}")
        return

    tab = Tab(args.cdp)
    tab.go(f"{args.web}/login", args.settle)
    tab.js(
        "(() => {"
        f'localStorage.setItem("fishers_access_token", {json.dumps(tokens["access_token"])});'
        f'localStorage.setItem("fishers_refresh_token", {json.dumps(tokens["refresh_token"])});'
        f'localStorage.setItem("fishers_user", {json.dumps(json.dumps(tokens["user"]))});'
        "})()"
    )

    for locale in ("en", "pa"):
        tab.js(f'document.cookie = "fishers_lang={locale}; path=/; max-age=86400"')
        for path in PAGES:
            text = tab.go(f"{args.web}{path}", args.settle)

            for key in sorted(
                k for k in re.findall(r"\b[a-z][a-z0-9_]*\.[a-z0-9_]{3,}\b", text)
                if k in keys
            ):
                problems.append(f"{locale} {path}: the key {key} is on the page")

            if locale != "pa":
                continue
            # Two or more Latin words in a row is a phrase somebody wrote in
            # English, unless every word in it is one that stays Latin.
            # `[the operator of Fishers]`, `[privacy@your-domain]` — square
            # brackets are how the privacy notice marks what whoever deploys
            # has to fill in. Untranslated is the point; it is not English that
            # escaped, it is a blank.
            text = re.sub(r"\[[^\]]*\]", " ", text)
            runs = re.findall(
                r"(?:\b[A-Za-z][A-Za-z'’\-]*\b[ \t]+){1,}\b[A-Za-z][A-Za-z'’\-]*\b",
                text,
            )
            for run in dict.fromkeys(r.strip() for r in runs):
                words = re.findall(r"[A-Za-z]+", run)
                if not all(KEEPS_LATIN.match(w) for w in words):
                    problems.append(f"pa {path}: English on the page — {run[:80]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--walk", action="store_true", help="also load every screen in a browser")
    ap.add_argument("--web", default="http://127.0.0.1:3123")
    ap.add_argument("--api", default="http://127.0.0.1:7312/api/v1")
    ap.add_argument("--cdp", type=int, default=9222)
    ap.add_argument("--email")
    ap.add_argument("--password")
    ap.add_argument("--settle", type=float, default=2.2, help="seconds to let a page finish")
    args = ap.parse_args()

    problems = []
    check_dictionaries(problems)
    check_bare_keys(problems)
    if args.walk:
        if not (args.email and args.password):
            sys.exit("--walk needs --email and --password for an account that can sign in")
        check_pages(problems, args)

    for problem in problems:
        print(problem)
    walked = " and every screen in both languages" if args.walk else ""
    print(f"\n{len(problems)} problems in the dictionaries{walked}.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
