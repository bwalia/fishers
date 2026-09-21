import 'package:fishers/models/fishers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// The club's man-of-the-match vote — `ios/Fishers/Models/ManOfTheMatch.swift`
/// and `web/src/lib/motm.ts`.
///
/// Both fixtures are real captures: an open poll with both elevens on the
/// ballot, and the same poll after a secretary closed it.
void main() {
  group('ManOfTheMatch.swift', () {
    test('MotmPollView', () {
      expectRoundTrip<MotmPollView>(
        'motm_poll_view',
        MotmPollView.fromJson,
        (MotmPollView v) => v.toJson(),
      );
      expectRoundTrip<MotmPollView>(
        'motm_poll_view_closed',
        MotmPollView.fromJson,
        (MotmPollView v) => v.toJson(),
      );
    });

    /// The poll's own fields arrive flattened in beside the ballot rather than
    /// under a key of their own, so a synthesised `fromJson` would have read
    /// an empty poll and said nothing about it.
    test('the flattened poll is read out of the same object as the ballot', () {
      final MotmPollView view = MotmPollView.fromJson(loadFixture('motm_poll_view'));
      expect(view.poll.title, isNotEmpty);
      expect(view.poll.status, 'open');
      expect(view.poll.isOpen, isTrue);
      expect(view.poll.clubId, isNotEmpty);
      expect(view.candidates, hasLength(22));
    });

    /// Both team sheets go on the ballot: a man of the match is quite often
    /// the opposition's opening bowler.
    test('the ballot is both elevens, and splits into two sheets', () {
      final MotmPollView view = MotmPollView.fromJson(loadFixture('motm_poll_view'));
      expect(view.sheet('home'), hasLength(11));
      expect(view.sheet('away'), hasLength(11));
      // Home first, as a scorecard is read.
      expect(view.candidates.first.side, 'home');
    });

    test('the sides are named from the fixture title', () {
      final MotmPollView view = MotmPollView.fromJson(loadFixture('motm_poll_view'));
      final ({String away, String home}) names = view.sideNames;
      expect(view.poll.title, contains(names.home));
      expect(view.poll.title, contains(names.away));

      // A fixture titled some other way falls back rather than guessing.
      final MotmPollView odd = MotmPollView.fromJson(<String, dynamic>{
        ...loadFixture('motm_poll_view'),
        'title': 'Sunday friendly',
      });
      expect(odd.sideNames, (home: 'Home', away: 'Away'));
    });

    /// Votes stay hidden until you have voted, so nobody is nudged towards
    /// whoever is already ahead — and the order must not leak it either.
    test('an unvoted ballot shows no tally at all', () {
      final MotmPollView view = MotmPollView.fromJson(loadFixture('motm_poll_view'));
      expect(view.tallyVisible, isFalse);
      expect(view.myVote, isNull);
      expect(view.candidates.every((MotmCandidate c) => c.votes == 0), isTrue);
      // A member who did not play may still vote. That is the feature.
      expect(view.canVote, isTrue);
    });

    test('a closed vote names its winner and shows the counts', () {
      final MotmPollView view = MotmPollView.fromJson(loadFixture('motm_poll_view_closed'));
      expect(view.poll.status, 'closed');
      expect(view.poll.isOpen, isFalse);
      expect(view.tallyVisible, isTrue);
      expect(view.canVote, isFalse);

      final MotmCandidate? winner = view.winner;
      expect(winner, isNotNull);
      expect(winner!.userId, view.poll.winnerUserId);
      expect(winner.votes, greaterThan(0));
      expect(view.tiedAtTheTop, isEmpty, reason: 'a clear winner is not a tie');
    });

    /// A tie closes with no winner recorded — choosing between two players who
    /// drew is a captain's job — so the card has to name everybody level.
    test('a tie names everybody at the top and no winner', () {
      final Map<String, dynamic> raw = loadFixture('motm_poll_view_closed');
      final List<dynamic> ballot = raw['candidates'] as List<dynamic>;
      final List<dynamic> tied = <dynamic>[
        <String, dynamic>{...(ballot[0] as Map<String, dynamic>), 'votes': 4},
        <String, dynamic>{...(ballot[1] as Map<String, dynamic>), 'votes': 4},
        <String, dynamic>{...(ballot[2] as Map<String, dynamic>), 'votes': 1},
      ];
      final MotmPollView view = MotmPollView.fromJson(<String, dynamic>{
        ...raw,
        'candidates': tied,
        'winner_user_id': null,
        'total_votes': 9,
      });

      expect(view.winner, isNull);
      expect(view.tiedAtTheTop.map((MotmCandidate c) => c.votes), <int>[4, 4]);
    });

    /// A poll past its closing time is over whatever the status column says:
    /// the sweeper runs every quarter of an hour, so there is always a window
    /// where the two disagree.
    test('a poll past its closing time reads as closed', () {
      final Map<String, dynamic> raw = loadFixture('motm_poll_view');
      final MotmPollView stale = MotmPollView.fromJson(<String, dynamic>{
        ...raw,
        'closes_at': '2020-01-01T12:00:00Z',
      });
      expect(stale.poll.status, 'open');
      expect(stale.poll.isOpen, isFalse);
    });

    /// The scorer's own award travels with the poll, so the card can show the
    /// two side by side rather than letting a club vote look as though it
    /// overruled the person scoring.
    test('the scorer pick is carried separately from the vote', () {
      final Map<String, dynamic> raw = loadFixture('motm_poll_view');
      const String scorersPick = 'a1b2c3d4-0000-0000-0000-00000000beef';
      final MotmPollView view = MotmPollView.fromJson(<String, dynamic>{
        ...raw,
        'scorer_award_user_id': scorersPick,
      });
      expect(view.scorerAwardUserId, scorersPick);
      expect(view.poll.winnerUserId, isNull);
    });
  });
}
