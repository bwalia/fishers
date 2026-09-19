import 'dart:convert';

import 'package:fishers/models/fishers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// The append-only scoring log, against real events.
///
/// `test/fixtures/api/scoring_events.json` is not invented: the everyday events
/// are a sample of what the seeded world's matches actually wrote, and the rest
/// were posted to a live match through `POST /cricket/matches/{id}/events` —
/// the API accepted the log and moved the match to `complete`, then the rows
/// were read back out of `cricket_scoring_events`. A wrong key would have been
/// a 4xx rather than a fixture.
void main() {
  final List<dynamic> events = loadFixtureList('scoring_events');

  test('the log covers all twenty event kinds', () {
    final Set<String> kinds = <String>{
      for (final dynamic raw in events) asMap(asMap(raw)['kind'])['type'] as String,
    };
    expect(kinds, hasLength(20));
    expect(kinds, <String>{
      'match_prepared',
      'toss_recorded',
      'xi_selected',
      'innings_started',
      'delivery_recorded',
      'extras_recorded',
      'overs_revised',
      'conditions_proposed',
      'conditions_agreed',
      'officials_appointed',
      'batter_resumed',
      'player_of_the_match',
      'penalty_runs',
      'field_set',
      'wicket_recorded',
      'bowler_changed',
      'innings_completed',
      'match_completed',
      'match_abandoned',
      'undo_last',
    });
  });

  test('every event round-trips, and writes back what the server stored', () {
    expect(events, hasLength(greaterThan(400)));
    for (final dynamic raw in events) {
      final JsonMap json = asMap(raw);
      final ScoringEvent event = ScoringEvent.fromJson(json);
      final JsonMap written = jsonDecode(jsonEncode(event.toJson())) as JsonMap;
      expect(
        ScoringEvent.fromJson(written),
        event,
        reason: 'a ${event.kind.typeName} does not survive a round trip',
      );

      // The tag and every field the model writes must match the stored row.
      final JsonMap storedKind = asMap(json['kind']);
      final JsonMap writtenKind = asMap(written['kind']);
      expect(writtenKind['type'], storedKind['type']);
      for (final MapEntry<String, dynamic> field in writtenKind.entries) {
        expect(
          storedKind.containsKey(field.key),
          isTrue,
          reason:
              '${event.kind.typeName} writes "${field.key}", which the server '
              'never sent — check the CodingKeys string',
        );
      }
    }
  });

  test('a delivery keeps its shot, and a shot keeps its region', () {
    final ScoringEvent boundary = events
        .map((dynamic raw) => ScoringEvent.fromJson(asMap(raw)))
        .firstWhere(
          (ScoringEvent e) =>
              e.kind is DeliveryRecorded && (e.kind as DeliveryRecorded).shot != null,
        );
    final DeliveryRecorded delivery = boundary.kind as DeliveryRecorded;
    expect(delivery.shot!.kind, isA<ShotKind>());
    expect(delivery.shot!.reach, inInclusiveRange(0, 1));
  });

  test('a nil captain leaves the key out, as encodeIfPresent does', () {
    const XiSelected picked = XiSelected(
      side: MatchSide.home,
      players: <MatchPlayer>[MatchPlayer(id: 'a', name: 'Sam')],
    );
    expect(picked.toJson().containsKey('captain_id'), isFalse);
    expect(picked.toJson().containsKey('keeper_id'), isFalse);

    const XiSelected withCaptain = XiSelected(
      side: MatchSide.away,
      players: <MatchPlayer>[],
      captainId: '00000000-0000-0000-0000-000000000001',
    );
    expect(withCaptain.toJson()['captain_id'], '00000000-0000-0000-0000-000000000001');
    expect(withCaptain.toJson().containsKey('keeper_id'), isFalse);
  });

  test('an unknown event kind is refused, not guessed at', () {
    expect(
      () => ScoringEventKind.fromJson(<String, dynamic>{'type': 'ball_tampering_recorded'}),
      throwsA(isA<JsonDecodeException>()),
    );
  });

  group('the state that log folds to', () {
    test('a scored match', () {
      expectRoundTrip<MatchState>(
        'match_state_scored',
        MatchState.fromJson,
        (MatchState s) => s.toJson(),
        ignoredWireKeys: <String>{'abandoned', 'dls'},
      );
      final MatchState state = MatchState.fromJson(loadFixture('match_state_scored'));
      expect(state.status, CricketMatchStatus.complete);
      expect(state.innings, hasLength(2));
      expect(state.winner, MatchSide.home);
      expect(state.playerOfTheMatch, isNotNull);
      expect(state.officials.isEmpty, isFalse);
      expect(state.conditionsAgreed, isTrue);
      expect(state.awaitingAgreement, isEmpty);
      // The names map is keyed lower-case, which is what makes a lookup work.
      expect(state.playerNames.keys.every((String k) => k == k.toLowerCase()), isTrue);
      expect(state.nameForPlayer(state.homeXi.first), isNot(startsWith('0000')));
      expect(state.scoreLine(), contains('/'));
    });

    test('an abandoned match is not a win for anybody', () {
      expectRoundTrip<CricketMatchDto>(
        'cricket_match_abandoned',
        CricketMatchDto.fromJson,
        (CricketMatchDto d) => d.toJson(),
      );
      final CricketMatchDto dto = CricketMatchDto.fromJson(loadFixture('cricket_match_abandoned'));
      expect(dto.state.winner, isNull);
      expect(dto.state.abandoned, isTrue);
      expect(dto.state.margin, isNotNull);
    });
  });

  group('the enums the brief names', () {
    test('CricketMatchStatus has its nine cases', () {
      expect(CricketMatchStatus.values.map((CricketMatchStatus s) => s.wire), <String>[
        'scheduled',
        'preparing',
        'toss',
        'selecting_xi',
        'ready',
        'live',
        'innings_break',
        'complete',
        'published',
      ]);
    });

    test('DismissalKind has its nine, with the Laws attached', () {
      expect(DismissalKind.values, hasLength(9));
      expect(
        DismissalKind.values.where((DismissalKind k) => k.creditsBowler).toSet(),
        <DismissalKind>{
          DismissalKind.bowled,
          DismissalKind.caught,
          DismissalKind.lbw,
          DismissalKind.stumped,
          DismissalKind.hitWicket,
        },
      );
      expect(
        DismissalKind.values.where((DismissalKind k) => k.allowedOnAFreeHit).toSet(),
        <DismissalKind>{
          DismissalKind.runOut,
          DismissalKind.retired,
          DismissalKind.retiredHurt,
          DismissalKind.other,
        },
      );
      expect(DismissalKind.retiredHurt.costsAWicket, isFalse);
      expect(DismissalKind.retired.usesABall, isFalse);
      expect(DismissalKind.runOut.canDismissNonStriker, isTrue);
      expect(DismissalKind.caught.canDismissNonStriker, isFalse);
    });

    test('ExtraKind has its five', () {
      expect(ExtraKind.values.map((ExtraKind k) => k.wire), <String>[
        'wide',
        'no_ball',
        'bye',
        'leg_bye',
        'penalty',
      ]);
      expect(ExtraKind.noBall.shortLabel, 'nb');
    });

    test('ShotKind has its thirteen', () {
      expect(ShotKind.values, hasLength(13));
      expect(ShotKind.reverseSweep.wire, 'reverse_sweep');
      expect(ShotKind.likely(runs: 6).first, ShotKind.loft);
      expect(ShotKind.likely(runs: 0).first, ShotKind.defence);
    });

    test('BallType has its five and GroundType its three', () {
      expect(BallType.values.map((BallType b) => b.wire), <String>[
        'red',
        'white',
        'pink',
        'tennis',
        'tape',
      ]);
      expect(GroundType.values.map((GroundType g) => g.wire), <String>['open', 'boxed', 'indoor']);
    });

    test('MatchSide, TossDecision and SyncStatus', () {
      expect(MatchSide.home.opposite, MatchSide.away);
      expect(MatchSide.away.opposite, MatchSide.home);
      expect(TossDecision.values.map((TossDecision d) => d.wire), <String>['bat', 'bowl']);
      expect(SyncStatus.values.map((SyncStatus s) => s.wire), <String>[
        'saved',
        'syncing',
        'offline',
      ]);
    });
  });

  group('the wagon wheel', () {
    test('names the eight sectors from the batter\'s own field', () {
      expect(cricketRegion(angle: 0, batsLeft: false), 'long on');
      expect(cricketRegion(angle: 60, batsLeft: false), 'mid-wicket');
      expect(cricketRegion(angle: 100, batsLeft: false), 'square leg');
      expect(cricketRegion(angle: 150, batsLeft: false), 'fine leg');
      expect(cricketRegion(angle: 200, batsLeft: false), 'third man');
      expect(cricketRegion(angle: 240, batsLeft: false), 'point');
      expect(cricketRegion(angle: 300, batsLeft: false), 'cover');
      expect(cricketRegion(angle: 340, batsLeft: false), 'long off');
    });

    test('mirrors for a left-hander', () {
      expect(cricketRegion(angle: 60, batsLeft: true), 'cover');
      expect(cricketRegion(angle: 300, batsLeft: true), 'mid-wicket');
      // Straight down the ground is straight down the ground either way.
      expect(cricketRegion(angle: 0, batsLeft: true), 'long on');
    });

    test('wraps past a full circle', () {
      expect(cricketRegion(angle: 380, batsLeft: false), cricketRegion(angle: 20, batsLeft: false));
    });
  });

  group('MatchConditions', () {
    test('a fifth of the innings each, rounded up', () {
      expect(MatchConditions.standardOversPerBowler(20), 4);
      expect(MatchConditions.standardOversPerBowler(50), 10);
      expect(MatchConditions.standardOversPerBowler(5), 1);
      expect(MatchConditions.standardOversPerBowler(1), 1);
    });

    test('the powerplay most competitions use at each length', () {
      expect(MatchConditions.standardPowerplay(5), 0);
      expect(MatchConditions.standardPowerplay(10), 2);
      expect(MatchConditions.standardPowerplay(20), 6);
      expect(MatchConditions.standardPowerplay(40), 8);
      expect(MatchConditions.standardPowerplay(50), 10);
    });

    test('the standard terms read as a sentence', () {
      final MatchConditions terms = MatchConditions.standard(overs: 20);
      expect(terms.oversLimit, 20);
      expect(terms.oversPerBowler, 4);
      expect(terms.ball, BallType.white);
      expect(terms.ground, GroundType.open);
      expect(
        terms.summary,
        '20 overs · 4 per bowler · white leather · open ground · 6 over powerplay',
      );
    });

    test('an innings with no overs is still a match', () {
      expect(MatchConditions.standard(overs: 0).oversLimit, 1);
    });
  });
}
