# Fishers end-to-end: the full match

One Playwright journey through the whole app, the way a season actually starts:

| Step | What happens | Checked by |
|---|---|---|
| 1–2 | Two club secretaries register ("I run a club"), start **E2E Club One** and **E2E Club Two**, sign out and back in | dashboard, club page, the club's code link, secretary role in the members API |
| 3 | 22 players register ("I play for a club"), open their profile, get their profile link | role is player, nobody's secretary, the link opens as "This is your own link" |
| 4–5 | Each secretary adds 11 players from their profile links; each player approves the invite on their dashboard | exactly the right 11 in each club, no duplicates, none of the other club's players |
| 6–7 | Club 1 opens Club 2's code link, starts a match against them, takes the book, sets **5 overs** | the opposition is Club 2 on Fishers, the book is held |
| 8–10 | Club 1 proposes the terms; Club 2's captain finds the proposal in their notifications and accepts | terms, sides and proposer as saved |
| 12 | The toss (the app records it **before** the team sheets) | winner and decision saved |
| 10b, 11 | Club 2's captain is told to pick their side and names 11; then Club 1 | only their own players offered; order, captain and keeper saved |
| 13 | First innings, five overs, every kind of ball — dots, runs, fours, sixes, wides, a no-ball, byes, leg byes, bowled, caught, a new bowler each over | **after every ball** the total, wickets, overs, striker and bowler against an independent model of the Laws (`lib/model.ts`); then every batter, bowler and the extras on the scorecard |
| 14–15 | The book is handed to Club 2's captain | Club 1 can no longer score; Club 2 sees the first innings intact and the target |
| 16–17 | Second innings; the result | "E2E Club One won by 23 runs", both scorecards, both XIs and the toss, from both captains' accounts |
| 18 | The checklist | every check above passed |

## Accounts are kept

Identities are fixed (`lib/people.ts`): `e2e.club1@fishers-e2e.test`, `e2e.player01@…` and so on, all with the password in
`E2E_PASSWORD`. The first run registers them; every run after signs the same people back in and skips anything already done
(clubs that exist, players already in them). Each run plays a new match. Set `E2E_NAMESPACE` to anything else for a
completely fresh set.

## Run it

```sh
cd e2e
npm ci && npx playwright install chromium

# against int (E2E_PASSWORD is read from ../.env)
npx playwright test

# against your local stack (scripts/start.sh)
E2E_BASE_URL=http://localhost:7311 npx playwright test

# the report, and the Slack message (posted when SLACK_WEBHOOK is set)
npx playwright show-report
npm run slack
```

A failure keeps a screenshot of every browser in the run, a video per account (`test-results/videos/`) and a trace.

Signing in means typing the password into the page, so Playwright records it — in the error-context snapshot of the form and
inside traces. Before anything is uploaded, `node scripts/scrub-secrets.mjs` (run by the workflow, and worth running by hand
before sharing a local run) redacts it from text files and deletes any trace that still holds it. Screenshots and videos are
safe: the field shows dots.

## In CI

`.github/workflows/e2e.yml`:

- **Pull requests** build that branch's API and web app inside the job, against a fresh database, and run the journey
  there — so a change is checked before it is deployed.
- **After each int deploy, every morning, and on demand** it runs against https://int.fishers.cloud with the kept accounts.

Every run writes its result to the job summary and, when `SLACK_WEBHOOK` is set, to Slack: each step, the match and its
result, the accounts made or reused, the checklist, and for a failure the step, the account, what happened and a button to
the screenshots and videos.

| Secret / variable | For |
|---|---|
| `E2E_PASSWORD` (secret) | runs against int — the kept accounts' password; the same value as in your `.env` |
| `SLACK_WEBHOOK` (secret) | the Slack message |
| `SLACK_BOT_TOKEN` (secret) + `SLACK_CHANNEL` (variable, a channel id) | optional: failure screenshots uploaded into the channel |
