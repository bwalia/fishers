# The video tour — what to publish with it

The film is made by `scripts/record-tour-video.sh`; this is the copy that goes around it. The
page at `/tour` carries the same chapters and the contents PDF for anyone who wants it offline.

- **Video** <https://youtu.be/AzYtyFYpedM>
- **Page** `/tour` — chapters, every caption with its timestamp, and the PDF
- **Thumbnail** `scripts/tour-thumbnail.swift` → `.dev/tour/tour-thumbnail.jpg` (2560×1440, ~400KB)
- **Contents PDF** `web/public/fishers-video-tour-contents.pdf`

## Title

> Fishers: a season on a phone — club cricket from sign-up to the last ball

Two alternatives, if a different emphasis suits better:

- `Scoring a whole T20 on a phone — the Fishers club cricket app (full tour)`
- `Club cricket, end to end: joining, availability, selection and ball-by-ball scoring`

## Description

```
Twenty minutes through Fishers, a club cricket app for iPhone: a player joining a club,
the Saturday availability, a captain picking the side, a whole twenty-over match scored
ball by ball, and everything else the cricket section does.

Nothing here is a mock-up. It is the app running against a seeded demo season — invented
clubs, invented players — and the scorecards are the scoring engine's own.

Chapters
0:00 Fishers — the video tour
0:05 1. A player joins a club — signing up, confirming, and being picked
3:07 2. Can you play on Saturday? — availability, from both ends
4:38 3. The captain picks the side — availability, reliability and who has sat out
6:52 4. A T20, ball by ball — twenty overs a side, scored on the phone
16:22 5. The rest of the cricket — the card, the wheel, the season and the book

What the app does
• Fixtures and availability — one tap an answer, or mark the Saturdays you are away
• Selection — the board shows what each player said and how reliably they turn up; publish
  and everyone hears at once
• Ball-by-ball scoring — extras, free hits, the bowling Laws, wagon wheel, commentary,
  Duckworth–Lewis–Stern, and a live scoreboard link for anyone without an account
• Season figures — batting, bowling and fielding, folded up out of the matches you scored
• Club pages, QR codes at the toss, club chat, shop and match fees

The full contents, with every screen listed against its timestamp:
https://www.fishers.cloud/tour

#cricket #clubcricket #cricketscoring #iosapp
```

## Notes

- YouTube turns the chapter list into chapters as long as the first line is `0:00` and there
  are at least three of them, each at least ten seconds apart.
- The timestamps come from the film's own index (`.dev/tour/index.json`), so re-cutting the
  film means re-running `./scripts/tour-page-data.py` and pasting this list again from
  `.dev/tour/chapters.txt`.
