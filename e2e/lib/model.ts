/// The scorer's arithmetic, done independently of the app — what the
/// scorecard *should* say after every ball, so the test checks the app's sums
/// rather than reading them back. The rules mirror the Laws as the engine
/// applies them (`backend/domain/src/cricket/engine.rs`).

export type Ball =
  | { t: "runs"; runs: number } //                off the bat: 0 is a dot, 4 and 6 boundaries
  | { t: "wide"; runs: number } //                runs taken on top of the wide
  | { t: "no_ball"; runs: number } //             runs taken, not off the bat (they are byes)
  | { t: "bye"; runs: number }
  | { t: "leg_bye"; runs: number }
  | { t: "wicket"; kind: "bowled" | "caught"; fielder?: string }; // the striker, no runs

export type BatterLine = { name: string; runs: number; balls: number; fours: number; sixes: number; out: boolean };
export type BowlerLine = { name: string; balls: number; runs: number; wickets: number; maidens: number };

export class Innings {
  runs = 0;
  wickets = 0;
  legal = 0;
  extras = 0;
  wides = 0;
  noBalls = 0;
  byes = 0;
  legByes = 0;
  striker: string;
  nonStriker: string;
  bowler: string;
  readonly batters = new Map<string, BatterLine>();
  readonly bowlers = new Map<string, BowlerLine>();
  private nextIn: string[];
  private overRuns = 0;

  constructor(
    readonly battingOrder: string[],
    firstBowler: string,
    readonly oversLimit: number
  ) {
    [this.striker, this.nonStriker] = battingOrder;
    this.nextIn = battingOrder.slice(2);
    this.bowler = firstBowler;
    this.bat(this.striker);
    this.bat(this.nonStriker);
  }

  get complete() {
    return this.legal >= this.oversLimit * 6 || this.wickets >= this.battingOrder.length - 1;
  }
  /// "3.4", as the app prints overs.
  get overs() {
    return `${Math.floor(this.legal / 6)}.${this.legal % 6}`;
  }
  get scoreline() {
    return `${this.runs}/${this.wickets}`;
  }
  /// The over just finished and the next needs a bowler.
  get needsBowler() {
    return this.legal > 0 && this.legal % 6 === 0 && !this.complete;
  }

  private bat(name: string) {
    if (!this.batters.has(name)) this.batters.set(name, { name, runs: 0, balls: 0, fours: 0, sixes: 0, out: false });
    return this.batters.get(name)!;
  }
  private bowl(name: string) {
    if (!this.bowlers.has(name)) this.bowlers.set(name, { name, balls: 0, runs: 0, wickets: 0, maidens: 0 });
    return this.bowlers.get(name)!;
  }
  private swap() {
    [this.striker, this.nonStriker] = [this.nonStriker, this.striker];
  }
  private legalBall() {
    this.legal += 1;
    this.bowl(this.bowler).balls += 1;
    if (this.legal % 6 === 0) {
      if (this.overRuns === 0) this.bowl(this.bowler).maidens += 1;
      this.overRuns = 0;
      this.swap(); // ends change at the end of the over
    }
  }
  private bowlerConcedes(runs: number) {
    this.bowl(this.bowler).runs += runs;
    this.overRuns += runs;
  }

  setBowler(name: string) {
    this.bowler = name;
  }

  apply(b: Ball) {
    const striker = this.bat(this.striker);
    switch (b.t) {
      case "runs":
        this.runs += b.runs;
        striker.runs += b.runs;
        striker.balls += 1;
        if (b.runs === 4) striker.fours += 1;
        if (b.runs === 6) striker.sixes += 1;
        this.bowlerConcedes(b.runs);
        if (b.runs % 2 === 1) this.swap();
        this.legalBall();
        break;
      case "wide":
        this.runs += 1 + b.runs;
        this.extras += 1 + b.runs;
        this.wides += 1 + b.runs;
        this.bowlerConcedes(1 + b.runs);
        if (b.runs % 2 === 1) this.swap();
        break;
      case "no_ball":
        this.runs += 1 + b.runs;
        this.extras += 1 + b.runs;
        this.noBalls += 1;
        this.byes += b.runs;
        striker.balls += 1;
        this.bowlerConcedes(1);
        if (b.runs % 2 === 1) this.swap();
        break;
      case "bye":
      case "leg_bye":
        this.runs += b.runs;
        this.extras += b.runs;
        if (b.t === "bye") this.byes += b.runs;
        else this.legByes += b.runs;
        striker.balls += 1;
        if (b.runs % 2 === 1) this.swap();
        this.legalBall();
        break;
      case "wicket": {
        striker.out = true;
        striker.balls += 1;
        this.wickets += 1;
        this.bowl(this.bowler).wickets += 1;
        const incoming = this.nextIn.shift();
        this.legal += 1;
        this.bowl(this.bowler).balls += 1;
        if (!this.complete && incoming) {
          this.striker = incoming; // the new batter takes the dismissed one's end
          this.bat(incoming);
        }
        if (this.legal % 6 === 0) {
          if (this.overRuns === 0) this.bowl(this.bowler).maidens += 1;
          this.overRuns = 0;
          this.swap();
        }
        break;
      }
    }
  }
}
