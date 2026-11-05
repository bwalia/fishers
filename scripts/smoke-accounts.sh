#!/usr/bin/env bash
# Club accounts against a running API: who may open the books, and whether a
# real club's AGM figures come out the same as its treasurer's spreadsheet.
#
# The figures are a real small club's 2025/26 year. The spreadsheet's balance
# sheet did not agree with itself (£69.92 short); the app must say so.
#
#   ./scripts/smoke-accounts.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, time, urllib.error, urllib.request

BASE = os.environ["SMOKE_BASE"]
STAMP = int(time.time())
failures = []


def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, (json.loads(raw) if raw else None)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def check(label, got, want):
    ok = got == want
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}")
    if not ok:
        failures.append(f"{label}: got {got!r}, wanted {want!r}")


def signup(name):
    status, body = call("POST", "/auth/signup", {
        "name": name, "email": f"acc{STAMP}{name.split()[0].lower()}@t.test",
        "password": "password123"})
    assert status == 200, (status, body)
    return body["access_token"], f"acc{STAMP}{name.split()[0].lower()}@t.test"


owner, _ = signup("Owner Person")
treasurer, treasurer_email = signup("Treasurer Person")
secretary, secretary_email = signup("Secretary Person")
member, member_email = signup("Member Person")
outsider, _ = signup("Outsider Person")

_, club = call("POST", "/clubs", {
    "name": f"Accounts CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, owner)
cid = club["id"]
for email, role in [(treasurer_email, "member"), (secretary_email, "club_admin"), (member_email, "member")]:
    status, _ = call("POST", f"/clubs/{cid}/members", {"identifier": email, "role": role}, owner)
    assert status == 200, status
_, roster = call("GET", f"/clubs/{cid}/members", token=owner)
uid = {m["name"]: m["user_id"] for m in roster}

# --- who may open the books -------------------------------------------------
A = f"/clubs/{cid}/accounts"
check("the owner can open the accounts", call("GET", A, token=owner)[0], 200)
check("a member cannot", call("GET", A, token=member)[0], 403)
check("a secretary who isn't the owner cannot", call("GET", A, token=secretary)[0], 403)
check("someone outside the club cannot", call("GET", A, token=outsider)[0], 403)
status, body = call("GET", A, token=member)
check("the refusal says who can", body.get("code"), "accounts_forbidden")

check("a member cannot appoint a treasurer",
      call("PUT", f"/clubs/{cid}/members/{uid['Treasurer Person']}/treasurer", {"is_treasurer": True}, member)[0], 403)
check("the secretary can appoint one",
      call("PUT", f"/clubs/{cid}/members/{uid['Treasurer Person']}/treasurer", {"is_treasurer": True}, secretary)[0], 200)
check("and appointing one doesn't let the secretary in", call("GET", A, token=secretary)[0], 403)
check("the treasurer can open the accounts", call("GET", A, token=treasurer)[0], 200)

_, role = call("GET", f"/clubs/{cid}/my-role", token=treasurer)
check("my-role says the treasurer may open them", role["can_open_accounts"], True)
check("and that they are treasurer", role["is_treasurer"], True)
check("their role is unchanged — older apps never see a new value", role["role"], "member")
_, role = call("GET", f"/clubs/{cid}/my-role", token=secretary)
check("my-role says the secretary may not", role["can_open_accounts"], False)
_, roster = call("GET", f"/clubs/{cid}/members", token=member)
check("the roster marks the treasurer",
      [m["name"] for m in roster if m.get("is_treasurer")], ["Treasurer Person"])

# A treasurer of another club is nobody here.
_, other = call("POST", "/clubs", {
    "name": f"Other CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, outsider)
check("another club's books are closed to this treasurer",
      call("GET", f"/clubs/{other['id']}/accounts", token=treasurer)[0], 403)

# --- the year ---------------------------------------------------------------
status, ov = call("GET", A, token=treasurer)
check("a first visit seeds the usual categories", len(ov["categories"]), 22)
check("and suggests a cricket year, 1 Oct to 30 Sep", (ov["suggested_next"]["starts_on"][5:], ov["suggested_next"]["ends_on"][5:]), ("10-01", "09-30"))
cat = {(c["kind"], c["name"]): c["id"] for c in ov["categories"]}

status, period = call("POST", f"{A}/periods", {
    "label": "2025/26", "starts_on": "2025-10-01", "ends_on": "2026-09-30",
    "opening_balance_cents": 384659}, treasurer)
check("the year opens", status, 200)
pid = period["id"]
check("a second open year is refused", call("POST", f"{A}/periods", {
    "label": "x", "starts_on": "2026-10-01", "ends_on": "2027-09-30"}, treasurer)[0], 409)

_, bank = call("POST", f"{A}/money-accounts", {"name": "Bank current a/c", "kind": "bank",
                                                "opening_cents": 299688}, treasurer)
_, balls = call("POST", f"{A}/stock", {"name": "Unused balls"}, treasurer)
check("opening stock", call("PUT", f"{A}/stock/{balls['id']}/count", {
    "period_id": pid, "opening_cents": 10494, "closing_cents": 7085}, treasurer)[0], 200)


def post(kind, name, pence, desc, account=True, **extra):
    body = {"occurred_on": "2026-06-01", "kind": kind, "category_id": cat[(kind, name)],
            "amount_cents": pence, "description": desc, **extra}
    if account:
        body["money_account_id"] = bank["id"]
    status, row = call("POST", f"{A}/periods/{pid}/transactions", body, treasurer)
    assert status == 200, (status, row)
    return row


post("income", "Indoor net fees", 64876, "Winter nets")
post("income", "Outdoor match fees", 254961, "Summer match fees")
post("income", "Cost share with other teams", 62000, "Cost share received")
for name, pence in [("Indoor nets", 112000), ("Pitch hire", 169250),
                    ("Cost share with other teams", 24500),
                    ("Losses on previous year recovered debt", 1883),
                    ("Equipment purchase", 34337), ("Public liability insurance", 10080),
                    ("Engraving, trophies etc.", 6000), ("Food (home games)", 31893),
                    ("Website", 21421)]:
    post("expenditure", name, pence, name)
post("expenditure", "Miscellaneous", 49000, "Two committee-authorised payments",
     extraordinary=True, authorised_on="2026-05-01", authorisation_ref="Committee minute 4")

# Debts: this year's unpaid fees and cost share go through the income lines;
# last year's unpaid fees were income last year, so they don't.
def debt(kind, pence, desc, accrue=True, raised_on="2026-09-30", **extra):
    status, row = call("POST", f"{A}/debts", {
        "direction": "debtor", "kind": kind, "description": desc, "amount_cents": pence,
        "raised_on": raised_on, "accrue": accrue, **extra}, treasurer)
    assert status == 200, (status, row)
    return row

fees_2026 = debt("member_fees", 33900, "Unpaid 2026 match/net fees")
debt("member_fees", 6100, "Unpaid 2025 match fees", accrue=False, raised_on="2025-10-01")
debt("cost_share", 13000, "Cost share from another team", counterparty="Neighbouring club")

check("the bank statement figure goes in", call("PUT", f"{A}/money-accounts/{bank['id']}/balance", {
    "period_id": pid, "reconciled_cents": 282546}, treasurer)[0], 200)

status, rep = call("GET", f"{A}/periods/{pid}/report", token=treasurer)
check("the report renders", status, 200)
cur = rep["current"]
b = cur["balance_sheet"]
check("income", cur["income_total_cents"], 428737)
check("expenditure", cur["expenditure_total_cents"], 463773)
check("excess of income over expenditure", cur["surplus_cents"], -35036)
check("balance c/f", b["carried_forward_cents"], 349623)
check("represented by", b["represented_total_cents"], 342631)
check("the £69.92 gap is reported", b["difference_cents"], -6992)
check("debtors", cur["debtors_total_cents"], 53000)
check("without the one-offs it was a profitable year",
      cur["insights"]["surplus_excluding_extraordinary_cents"], 13964)
check("equipment carries the balls used off the shelf",
      next(l["amount_cents"] for l in cur["expenditure"] if l["name"] == "Equipment purchase"), 37746)
check("fees owed landed on its income line",
      next(l["amount_cents"] for l in cur["income"] if l["name"] == "Match/net fees owed"), 33900)

# A correction, then voiding it: the gap comes back.
_, adj = call("POST", f"{A}/periods/{pid}/transactions", {
    "occurred_on": "2026-09-30", "kind": "adjustment", "amount_cents": -6992,
    "description": "Errors in the 2025 books"}, treasurer)
_, rep = call("GET", f"{A}/periods/{pid}/report", token=treasurer)
check("a prior-period adjustment closes the gap", rep["current"]["balance_sheet"]["difference_cents"], 0)
check("and isn't trading", rep["current"]["surplus_cents"], -35036)
check("voiding needs a reason",
      call("POST", f"{A}/transactions/{adj['id']}/void", {"reason": ""}, treasurer)[0], 400)
call("POST", f"{A}/transactions/{adj['id']}/void", {"reason": "Agreed to show the gap at the AGM"}, treasurer)
_, rep = call("GET", f"{A}/periods/{pid}/report", token=treasurer)
check("voided, the gap shows again", rep["current"]["balance_sheet"]["difference_cents"], -6992)

status, _ = call("POST", f"{A}/periods/{pid}/transactions", {
    "occurred_on": "2026-10-02", "kind": "income", "category_id": cat[("income", "Interest")],
    "amount_cents": 100, "description": "Outside the year"}, treasurer)
check("a line dated outside the year is refused", status, 400)

# --- close, carry forward, paid since close --------------------------------
check("the year closes", call("POST", f"{A}/periods/{pid}/close", token=treasurer)[0], 200)
status, _ = call("POST", f"{A}/periods/{pid}/transactions", {
    "occurred_on": "2026-06-02", "kind": "income", "category_id": cat[("income", "Interest")],
    "amount_cents": 100, "description": "Too late"}, treasurer)
check("a closed year takes no new lines", status, 409)

status, nxt = call("POST", f"{A}/periods", {
    "label": "2026/27", "starts_on": "2026-10-01", "ends_on": "2027-09-30",
    "opening_balance_cents": 1}, treasurer)
check("next year opens", status, 200)
check("with last year's c/f as its b/f, not the typed figure", nxt["opening_balance_cents"], 349623)
_, money = call("GET", f"{A}/periods/{nxt['id']}/money", token=treasurer)
check("the bank opens on the statement figure", money[0]["opening_cents"], 282546)
_, stock = call("GET", f"{A}/periods/{nxt['id']}/stock", token=treasurer)
check("stock opens on last year's count", stock[0]["opening_cents"], 7085)

status, _ = call("POST", f"{A}/debts/{fees_2026['id']}/settlements", {
    "kind": "payment", "amount_cents": 10850, "settled_on": "2026-10-15",
    "money_account_id": bank["id"]}, treasurer)
check("part of last year's fees comes in", status, 200)
status, _ = call("POST", f"{A}/debts/{fees_2026['id']}/settlements", {
    "kind": "payment", "amount_cents": 99999, "settled_on": "2026-10-16",
    "money_account_id": bank["id"]}, treasurer)
check("more than is owed is refused", status, 400)
_, rep = call("GET", f"{A}/periods/{pid}/report", token=treasurer)
check("the closed year shows £108.50 paid since the books closed",
      rep["current"]["insights"]["paid_since_close_cents"], 10850)
check("and its own figures haven't moved", rep["current"]["debtors_total_cents"], 53000)
_, rep2 = call("GET", f"{A}/periods/{nxt['id']}/report", token=treasurer)
check("the new year shows the debt reduced", rep2["current"]["debtors_total_cents"], 53000 - 10850)
check("and the money in the bank, not as income",
      rep2["current"]["income_total_cents"], 0)
check("with last year beside it", rep2["previous"]["label"], "2025/26")

# --- reopening ---------------------------------------------------------------
check("a treasurer can't reopen a closed year",
      call("POST", f"{A}/periods/{pid}/reopen", {"reason": "fix a line"}, treasurer)[0], 403)
check("nor the owner while a later year is open",
      call("POST", f"{A}/periods/{pid}/reopen", {"reason": "fix a line"}, owner)[0], 409)

_, log = call("GET", f"{A}/audit", token=treasurer)
check("everything is in the audit trail", len(log) >= 25, True)
check("including who appointed the treasurer",
      any(e["action"] == "appoint_treasurer" and e["actor_name"] == "Secretary Person" for e in log), True)

check("removing the treasurer", call("PUT", f"/clubs/{cid}/members/{uid['Treasurer Person']}/treasurer",
                                     {"is_treasurer": False}, owner)[0], 200)
check("shuts them out", call("GET", A, token=treasurer)[0], 403)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY
