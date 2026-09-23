import { brand } from "@/brand.generated";

// Generated from the film's own index by scripts/tour-page-data.py, so every timestamp
// here is the video's arithmetic rather than a second copy of it that can drift.
//
//   ./scripts/cut-tour-video.sh && ./scripts/tour-page-data.py

export type TourBeat = { at: number; stamp: string; text: string };
export type TourChapter = {
  number: number;
  title: string;
  subtitle: string;
  at: number;
  stamp: string;
  beats: TourBeat[];
};

export const TOUR_VIDEO_ID = "AzYtyFYpedM";
export const TOUR_DURATION = "20:45";
export const TOUR_FOOTER = "Recorded on the iOS Simulator against a seeded demo season. Invented clubs and invented players, not a real club's records.";

export const TOUR_CHAPTERS: TourChapter[] = [
  {
    number: 1,
    title: "A player joins a club",
    subtitle: "Signing up, confirming, and being picked",
    at: 5,
    stamp: "0:05",
    beats: [
      { at: 11, stamp: "0:11", text: `${brand.name} is club cricket on a phone: fixtures, availability, selection and the scorebook. This is a player opening it for the first time.` },
      { at: 46, stamp: "0:46", text: "Signing up asks one thing first \u2014 whether you run a club or play for one. The app is a different shape for each." },
      { at: 73, stamp: "1:13", text: "The quick start is a sport and a mobile number. Everything else about a player can wait until they have been picked once." },
      { at: 85, stamp: "1:25", text: "New players are not searched for; they hand over a link. This one goes in the club's WhatsApp group, and the secretary invites them from it." },
      { at: 98, stamp: "1:38", text: "Home before a club: the profile is part filled, and there is nothing in the diary yet." },
      { at: 119, stamp: "1:59", text: "A club is somebody's real membership list, so an address gets confirmed before it can join one. The code arrives by email." },
      { at: 143, stamp: "2:23", text: "The secretary sends the invite from that link, and it is waiting on Home \u2014 no code to type in, no email to go and find." },
      { at: 156, stamp: "2:36", text: "Accepted, and the club's season is theirs: fixtures, the squad, the chat and the scores." },
      { at: 164, stamp: "2:44", text: "The profile keeps a score of itself. What is missing is what a captain looks at when picking, so the app says which line to fill in next." },
      { at: 178, stamp: "2:58", text: "A cricketer's profile: where they bat, what they bowl, the standard they play and how far they will travel." },
    ],
  },
  {
    number: 2,
    title: "Can you play on Saturday?",
    subtitle: "Availability, from both ends",
    at: 187,
    stamp: "3:07",
    beats: [
      { at: 197, stamp: "3:17", text: "The Fixtures tab is every fixture of every club you are in, each asking the one thing it needs: can you play?" },
      { at: 208, stamp: "3:28", text: "Three taps \u2014 available, maybe, can't play. The answer is saved as it is tapped and the captain sees it immediately." },
      { at: 220, stamp: "3:40", text: "It says what you said, and it can be changed until the side goes up." },
      { at: 231, stamp: "3:51", text: "The calendar is the other way round: mark the Saturdays you are away and every fixture on them is answered at once." },
      { at: 246, stamp: "4:06", text: "A weekend away marked once, rather than a message to the captain for each game." },
      { at: 253, stamp: "4:13", text: "And the days you usually play, so the season starts from your own pattern rather than from nothing." },
      { at: 271, stamp: "4:31", text: "Inside a fixture: where, when, the match fee, and who else has said yes." },
    ],
  },
  {
    number: 3,
    title: "The captain picks the side",
    subtitle: "Availability, reliability and who has sat out",
    at: 279,
    stamp: "4:39",
    beats: [
      { at: 318, stamp: "5:18", text: "The captain's selection board for Saturday. Everyone who could play, in one list." },
      { at: 328, stamp: "5:28", text: "Beside each name: what they said, what the calendar says, and how reliably they turn up when they are picked." },
      { at: 340, stamp: "5:40", text: "The assistant can suggest a side from availability, reliability and who has been left out lately. The captain is the one who picks." },
      { at: 354, stamp: "5:54", text: "Eleven picked and two down as reserves, in batting order." },
      { at: 362, stamp: "6:02", text: "Publishing tells everybody at once." },
      { at: 377, stamp: "6:17", text: "The squad lands in the club chat, where the rest of the week's arrangements already are." },
    ],
  },
  {
    number: 4,
    title: "A T20, ball by ball",
    subtitle: "Twenty overs a side, scored on the phone",
    at: 412,
    stamp: "6:52",
    beats: [
      { at: 427, stamp: "7:07", text: "Tonight's fixture: a floodlit T20, twenty overs a side. The captain has the book." },
      { at: 439, stamp: "7:19", text: "Before a ball: the terms both captains settle at the toss. Twenty overs, four an over each, a six-over powerplay, white ball." },
      { at: 461, stamp: "7:41", text: "One captain proposes and the other agrees, each against their own name. There is no toss until both have." },
      { at: 475, stamp: "7:55", text: "The toss, recorded before the team sheets, the way it happens." },
      { at: 538, stamp: "8:58", text: "The team sheet is picked from the club's squad, in batting order, with the captain and the keeper marked." },
      { at: 608, stamp: "10:08", text: "Openers and the bowler to start. From here the app is a scorebook." },
      { at: 635, stamp: "10:35", text: "One tap a ball. The score, the two batters, the bowler's figures and this over so far." },
      { at: 664, stamp: "11:04", text: "A boundary asks where it went. The field mirrors for a left-hander, so 'driven through cover' is right for both." },
      { at: 673, stamp: "11:13", text: "The powerplay is on the screen while it lasts, with the overs left in it." },
      { at: 700, stamp: "11:40", text: "Extras are the arithmetic the app does rather than the scorer: a wide they ran a single off is two runs, and both of them wides." },
      { at: 742, stamp: "12:22", text: "A wicket takes the bowler's name, the fielder's, and who is in next." },
      { at: 765, stamp: "12:45", text: "A no ball sets a free hit. While it stands, only a run out can get the batter, and the sheet offers nothing else." },
      { at: 792, stamp: "13:12", text: "Nobody bowls two overs in a row and nobody bowls more than their four, so at the end of an over the app asks who is next \u2014 and says who cannot." },
      { at: 837, stamp: "13:57", text: "Twenty overs bowled. The innings closes itself." },
      { at: 852, stamp: "14:12", text: "The chase, with the target, the rate it needs and the Duckworth\u2013Lewis\u2013Stern par beside it in case the rain comes." },
      { at: 921, stamp: "15:21", text: "Last over, and the arithmetic every fielding side is doing in its head." },
      { at: 948, stamp: "15:48", text: "The result, from the log rather than from anyone's addition." },
      { at: 960, stamp: "16:00", text: "Player of the match, and the game is finished." },
      { at: 970, stamp: "16:10", text: "The full card: every batter, every bowler, the extras and the fall of wickets." },
    ],
  },
  {
    number: 5,
    title: "The rest of the cricket",
    subtitle: "The card, the wheel, the season and the book",
    at: 982,
    stamp: "16:22",
    beats: [
      { at: 998, stamp: "16:38", text: "Every match the club has played or is playing, live and finished." },
      { at: 1007, stamp: "16:47", text: "A finished league match from earlier in the season, with its own card kept the same way." },
      { at: 1023, stamp: "17:03", text: "The wagon wheel is built from the same balls \u2014 every scoring shot, where it went and what the stroke was." },
      { at: 1036, stamp: "17:16", text: "And a commentary, written from the log rather than typed by anybody: over, bowler, batter, what happened." },
      { at: 1055, stamp: "17:35", text: "The 2nd XI are playing at the same time, scored on somebody else's phone. Everyone in the club sees it move." },
      { at: 1095, stamp: "18:15", text: "What else the book can do: correct a ball three back, set the field, add penalty runs, cut the overs for rain, or hand the book to somebody else." },
      { at: 1110, stamp: "18:30", text: "Scorers get it wrong three balls back, not just on the last one. Pick the ball and the innings winds back to it \u2014 recorded, not erased." },
      { at: 1128, stamp: "18:48", text: "One person scores at a time. The book moves when they pass it on, and the trail keeps who had it when." },
      { at: 1156, stamp: "19:16", text: "The club's season, folded up out of those cards: runs, wickets, catches \u2014 nobody types this in." },
      { at: 1175, stamp: "19:35", text: "The club's public page \u2014 record, top players and next fixtures \u2014 for anyone who has heard of the club and has no account." },
      { at: 1195, stamp: "19:55", text: "Every club and team has a QR code. At the toss the other captain scans it, and the scorecard knows who they are without anyone spelling a name." },
      { at: 1219, stamp: "20:19", text: "A player's own figures, and the record they are building across seasons." },
      { at: 1230, stamp: "20:30", text: "All of it lands back on Home: what is in progress, what is next, and what the club needs from you this week." },
    ],
  },
];
