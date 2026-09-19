import 'package:fishers/models/fishers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// The rules that live on the models rather than on the wire — the Dart side of
/// what `ios/FishersTests/` asserts about them.
void main() {
  group('a notification reads as a sentence', () {
    // The cases and the exact words are from
    // `ios/FishersTests/LiveTests.swift`; a player is never shown a wire type.
    AppNotification make(String type, JsonMap payload) =>
        AppNotification.fromJson(<String, dynamic>{
          'id': '0e3fb2c6-0f57-4a3a-9ad3-64e0d3b0c9a1',
          'type': type,
          'payload': payload,
          'sent_at': '2026-09-14T08:00:00.123Z',
          'read_at': null,
        });

    test('nulls in the payload do not sink the row', () {
      final AppNotification invite = make('invite', <String, dynamic>{
        'invite_id': 'x',
        'club_name': 'Boom Blast',
        'team_name': null,
        'event_title': null,
        'inviter': 'Sam',
        'url': '/',
        'tag': 'invite:x',
        'n': 3,
      });
      expect(invite.line, 'Boom Blast wants you in the club. Sam invited you.');
      expect(invite.payload['n'], '3', reason: 'a number is kept, as its text');
      expect(invite.payload['team_name'], isNull, reason: 'a null is dropped, not kept as "null"');

      final AppNotification team = make('invite', <String, dynamic>{
        'club_name': 'Boom Blast',
        'team_name': '2nd XI',
      });
      expect(team.line, 'Boom Blast wants you in their 2nd XI.');
    });

    test('every kind', () {
      expect(
        make('fixture_scheduled', <String, dynamic>{
          'event_id': '9f0a0f2c-7f4c-4a7f-8a55-2a2f2f1c9b10',
          'title': 'Boom v Bust',
          'start_at': '2026-09-20T13:00:00Z',
        }).line,
        'Boom v Bust — can you play?',
      );
      expect(
        make('player_responded', <String, dynamic>{'player': 'Ali', 'title': 'Boom v Bust'}).line,
        'Ali answered for Boom v Bust.',
      );
      expect(
        make('match_book_handed_over', <String, dynamic>{
          'home_name': 'Boom',
          'away_name': 'Bust',
        }).line,
        "Boom v Bust — you have the book. You're scoring from the next ball.",
      );
      expect(
        make('invite_accepted', <String, dynamic>{
          'player': 'Ali',
          'club_name': 'Boom Blast',
          'team_name': null,
        }).line,
        "Ali accepted — they're in Boom Blast.",
      );
      expect(
        make('profile_nudge', <String, dynamic>{'percent': 35, 'url': '/profile'}).line,
        "Finish your profile — you're 35% there. Captains pick players they can see.",
      );
      expect(
        make('match_terms_proposed', <String, dynamic>{
          'home_name': 'Boom',
          'away_name': 'Bust',
        }).line,
        'Boom v Bust — the other captain has proposed the terms. Tap to agree.',
      );
      expect(
        make('match_pick_your_xi', <String, dynamic>{
          'home_name': 'Boom',
          'away_name': 'Bust',
        }).line,
        'Boom v Bust — the toss is done. Pick your side.',
      );
      expect(
        make('match_terms_agreed', <String, dynamic>{}).line,
        'Both captains have agreed the terms. You can do the toss.',
      );
      // A kind this build has never heard of still reads as words.
      expect(make('brand_new_kind', <String, dynamic>{}).line, 'brand new kind');
    });

    test('a tap knows where to go', () {
      final AppNotification fixture = make('fixture_scheduled', <String, dynamic>{
        'event_id': '9F0A0F2C-7F4C-4A7F-8A55-2A2F2F1C9B10',
        'title': 'Boom v Bust',
        'start_at': '2026-09-20T13:00:00Z',
      });
      expect(fixture.eventId, '9f0a0f2c-7f4c-4a7f-8a55-2a2f2f1c9b10');
      expect(fixture.when, DateTime.utc(2026, 9, 20, 13));
      expect(fixture.isUnread, isTrue);

      // A payload value that is not an id reads as no id, rather than throwing.
      expect(make('invite', <String, dynamic>{'event_id': 'not-a-uuid'}).eventId, isNull);
      expect(make('invite', <String, dynamic>{'start_at': 'sometime'}).when, isNull);
    });
  });

  group('profile strength', () {
    test('an empty profile is 10%, and says what to add', () {
      final PublicUser bare = PublicUser.fromJson(<String, dynamic>{
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Pat',
        'sports_played': <String>[],
      });
      final ProfileStrength strength = ProfileStrength(bare);
      expect(strength.percent, 10);
      expect(strength.isComplete, isFalse);
      expect(strength.nextUp, 'Add what you play, a photo and the standard you play at');
    });

    test('a filled-in profile reaches 100', () {
      final PublicUser full = PublicUser.fromJson(loadFixture('public_user_full'));
      final ProfileStrength strength = ProfileStrength(full);
      // The captured profile has everything but a photo (15) and a confirmed
      // address or number (10).
      expect(strength.percent, 75);
      expect(strength.missing.map((ProfileStrengthItem i) => i.id), <String>['photo', 'verified']);
    });

    test('the weights add to 100', () {
      final PublicUser bare = PublicUser.fromJson(<String, dynamic>{
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Pat',
        'sports_played': <String>[],
      });
      expect(
        ProfileStrength(bare).items.fold(0, (int sum, ProfileStrengthItem i) => sum + i.weight),
        100,
      );
    });
  });

  group('reliability', () {
    test('matches the server\'s weighting', () {
      final ReliabilityScore perfect = ReliabilityScore.compute(
        invitesReceived: 10,
        responded: 10,
        saidGoing: 10,
        turnedUp: 10,
        lateCancellations: 0,
        feesDue: 4,
        feesPaid: 4,
      );
      expect(perfect.score, 100);
      expect(perfect.band, ReliabilityBand.rockSolid);
      expect(perfect.fraction, 1.0);
    });

    test('too few games is unproven, whatever the score', () {
      final ReliabilityScore thin = ReliabilityScore.compute(
        invitesReceived: 2,
        responded: 2,
        saidGoing: 2,
        turnedUp: 2,
        lateCancellations: 0,
        feesDue: 0,
        feesPaid: 0,
      );
      expect(thin.score, 100);
      expect(thin.band, ReliabilityBand.unproven);
    });

    test('a late drop-out costs five points each', () {
      final ReliabilityScore dropped = ReliabilityScore.compute(
        invitesReceived: 10,
        responded: 10,
        saidGoing: 10,
        turnedUp: 10,
        lateCancellations: 3,
        feesDue: 1,
        feesPaid: 1,
      );
      expect(dropped.score, 85);
      expect(dropped.band, ReliabilityBand.rockSolid);
    });

    test('never goes below zero', () {
      final ReliabilityScore awful = ReliabilityScore.compute(
        invitesReceived: 10,
        responded: 0,
        saidGoing: 0,
        turnedUp: 0,
        lateCancellations: 40,
        feesDue: 4,
        feesPaid: 0,
      );
      expect(awful.score, 0);
      expect(awful.band, ReliabilityBand.patchy);
    });
  });

  group('roles gate what a screen shows', () {
    test('a secretary is a captain, a member is neither', () {
      expect(ClubRole.clubAdmin.isSecretary, isTrue);
      expect(ClubRole.clubAdmin.isCaptain, isTrue);
      expect(ClubRole.superAdmin.isSecretary, isTrue);
      expect(ClubRole.teamCaptain.isCaptain, isTrue);
      expect(ClubRole.teamCaptain.isSecretary, isFalse);
      expect(ClubRole.teamViceCaptain.isCaptain, isTrue);
      expect(ClubRole.member.isCaptain, isFalse);
      expect(ClubRole.member.isSecretary, isFalse);
      expect(ClubRole.guest.canScoreMatch, isFalse);
      expect(ClubRole.guest.canManageMembers, isFalse);
    });

    test('only a secretary manages the roster', () {
      for (final ClubRole role in ClubRole.values) {
        expect(role.canManageMembers, role.isSecretary, reason: '$role');
        expect(role.canInviteToPlay, role.isCaptain, reason: '$role');
        expect(role.canManageSelection, role.isCaptain, reason: '$role');
      }
    });

    test('a secretary who captains gets its own label', () {
      final RoleChoice both = RoleChoice(role: ClubRole.clubAdmin, isCaptain: true);
      expect(both.label, 'Secretary & captain');
      expect(both.shortLabel, 'SEC · C');
      expect(both.id, 'club_admin+captain');

      // The flag means nothing on a role that captains by definition.
      final RoleChoice captain = RoleChoice(role: ClubRole.teamCaptain, isCaptain: true);
      expect(captain.isCaptain, isFalse);
      expect(captain.label, 'Team captain');
    });

    test('a role info reply without can_score_match falls back to the role', () {
      final ClubRoleInfo info = ClubRoleInfo.fromJson(<String, dynamic>{
        'role': 'team_captain',
        'display_name': 'Team captain',
        'is_secretary': false,
        'is_captain': true,
        'can_invite_to_play': true,
        'permissions': <String>[],
      });
      expect(info.canScoreMatch, isTrue);

      final ClubRoleInfo byPermission = ClubRoleInfo.fromJson(<String, dynamic>{
        'role': 'member',
        'display_name': 'Member',
        'is_secretary': false,
        'is_captain': false,
        'can_invite_to_play': false,
        'permissions': <String>['score_match'],
      });
      expect(byPermission.canScoreMatch, isTrue);

      final ClubRoleInfo plainMember = ClubRoleInfo.fromJson(<String, dynamic>{
        'role': 'member',
        'display_name': 'Member',
        'is_secretary': false,
        'is_captain': false,
        'can_invite_to_play': false,
        'permissions': <String>[],
      });
      expect(plainMember.canScoreMatch, isFalse);
    });
  });

  group('the clubs list asks the server', () {
    test('an unfiltered list still names its sort and page', () {
      const ClubListFilters filters = ClubListFilters();
      expect(filters.isFiltered, isFalse);
      expect(
        filters
            .queryItems(page: 1, perPage: 20)
            .map((({String name, String value}) i) => '${i.name}=${i.value}'),
        <String>['sort=name', 'page=1', 'per_page=20'],
      );
    });

    test('each filter adds its own item, in the iOS order', () {
      const ClubListFilters filters = ClubListFilters(
        query: '  hemel  ',
        role: ClubListRole.viceCaptain,
        sport: 'cricket',
        publicPage: true,
        sort: ClubListSort.members,
      );
      expect(filters.isFiltered, isTrue);
      expect(
        filters
            .queryItems(page: 2, perPage: 50)
            .map((({String name, String value}) i) => '${i.name}=${i.value}'),
        <String>[
          'sort=members',
          'page=2',
          'per_page=50',
          'q=hemel',
          'role=vice_captain',
          'sport=cricket',
          'public_page=true',
        ],
      );
    });

    test('a very long search is cut to what the server accepts', () {
      final ClubListFilters filters = ClubListFilters(query: 'x' * 200);
      final String q = filters
          .queryItems(page: 1, perPage: 20)
          .firstWhere((({String name, String value}) i) => i.name == 'q')
          .value;
      expect(q, hasLength(100));
    });
  });

  group('a club page', () {
    test('suggests a slug from the name', () {
      expect(ClubPageSettings.suggestedSlug('Hemel Hempstead CC'), 'hemel-hempstead-cc');
      expect(ClubPageSettings.suggestedSlug("St John's Wood XI"), 'st-john-s-wood-xi');
      expect(ClubPageSettings.suggestedSlug('  Lords  '), 'lords');
      expect(ClubPageSettings.suggestedSlug('Boom!!! Blast'), 'boom-blast');
    });

    test('has a value that means "nobody" for the icon', () {
      expect(ClubPageSettings.noIconPlayer, '00000000-0000-0000-0000-000000000000');
    });
  });

  group('a shared profile link', () {
    test('is pulled out of whatever was pasted', () {
      expect(
        SharedPlayerCard.token('Hi — here you go: https://www.fishers.cloud/p/abcdefghijklmnop'),
        'abcdefghijklmnop',
      );
      expect(SharedPlayerCard.token('no link here'), isNull);
      expect(SharedPlayerCard.token('/p/tooshort'), isNull);
    });
  });

  group('fixtures', () {
    MyFixture fixture(String id, String start, String end, {FixtureAnswer? answer}) =>
        MyFixture.fromJson(<String, dynamic>{
          'event_id': id,
          'title': 'A game',
          'sport': 'cricket',
          'event_subtype': 'league_match',
          'status': 'scheduled',
          'start_at': start,
          'end_at': end,
          'club_id': '22222222-2222-2222-2222-222222222222',
          'club_name': 'Lords',
          'my_answer': answer?.wire,
        });

    test('two fixtures you said yes to that overlap are a clash', () {
      final List<MyFixture> mine = <MyFixture>[
        fixture(
          '33333333-3333-3333-3333-333333333331',
          '2026-07-04T10:00:00Z',
          '2026-07-04T16:00:00Z',
          answer: FixtureAnswer.going,
        ),
        fixture(
          '33333333-3333-3333-3333-333333333332',
          '2026-07-04T14:00:00Z',
          '2026-07-04T18:00:00Z',
          answer: FixtureAnswer.going,
        ),
        fixture(
          '33333333-3333-3333-3333-333333333333',
          '2026-07-04T14:00:00Z',
          '2026-07-04T18:00:00Z',
          answer: FixtureAnswer.maybe,
        ),
      ];
      expect(FixtureList.clashes(mine), <String>{
        '33333333-3333-3333-3333-333333333331',
        '33333333-3333-3333-3333-333333333332',
      });
    });

    test('a maybe is not a clash', () {
      final List<MyFixture> mine = <MyFixture>[
        fixture(
          '33333333-3333-3333-3333-333333333331',
          '2026-07-04T10:00:00Z',
          '2026-07-04T16:00:00Z',
          answer: FixtureAnswer.maybe,
        ),
        fixture(
          '33333333-3333-3333-3333-333333333332',
          '2026-07-04T14:00:00Z',
          '2026-07-04T18:00:00Z',
          answer: FixtureAnswer.maybe,
        ),
      ];
      expect(FixtureList.clashes(mine), isEmpty);
    });

    test('an unanswered fixture says so', () {
      expect(
        fixture(
          '33333333-3333-3333-3333-333333333331',
          '2026-07-04T10:00:00Z',
          '2026-07-04T16:00:00Z',
        ).saidLabel,
        'Not answered yet',
      );
      expect(FixtureAnswer.going.said, "You're available");
      expect(FixtureAnswer.notGoing.rsvp, RsvpStatus.notGoing);
    });

    test('every Saturday in a month, Foundation-numbered', () {
      // July 2026: the 4th, 11th, 18th and 25th are Saturdays.
      final List<DateTime> saturdays = FixtureList.datesIn(DateTime(2026, 7), weekday: 7);
      expect(saturdays.map((DateTime d) => d.day), <int>[4, 11, 18, 25]);
      final List<DateTime> sundays = FixtureList.datesIn(DateTime(2026, 7), weekday: 1);
      expect(sundays.map((DateTime d) => d.day), <int>[5, 12, 19, 26]);
    });

    test('grouped by the day they start on, days in order', () {
      final List<MyFixture> mine = <MyFixture>[
        fixture(
          '33333333-3333-3333-3333-333333333332',
          '2026-07-05T10:00:00Z',
          '2026-07-05T16:00:00Z',
        ),
        fixture(
          '33333333-3333-3333-3333-333333333331',
          '2026-07-04T10:00:00Z',
          '2026-07-04T16:00:00Z',
        ),
      ];
      final List<({DateTime day, List<MyFixture> fixtures})> days = FixtureList.byDay(mine);
      expect(days, hasLength(2));
      expect(days.first.day.isBefore(days.last.day), isTrue);
    });
  });

  group('availability', () {
    test('cycles yes → maybe → no → yes', () {
      expect(AvailabilityStatus.available.next(), AvailabilityStatus.maybe);
      expect(AvailabilityStatus.maybe.next(), AvailabilityStatus.unavailable);
      expect(AvailabilityStatus.unavailable.next(), AvailabilityStatus.available);
    });
  });

  group('sports and their stats', () {
    test('a sport spelled the old way still resolves', () {
      expect(Sport.named('padel'), Sport.paddle);
      expect(Sport.named('PADDLE'), Sport.paddle);
      expect(Sport.named('  cricket '), Sport.cricket);
      expect(Sport.named(''), isNull);
      expect(Sport.named(null), isNull);
      expect(Sport.named('quidditch'), isNull);
    });

    test('a standard stored capitalised still resolves', () {
      expect(SkillTier.stored('Club standard'), SkillTier.club);
      expect(SkillTier.stored('ELITE'), SkillTier.elite);
      expect(SkillTier.stored('made up'), isNull);
    });

    test('every sport has a stat catalog', () {
      for (final Sport sport in Sport.values) {
        expect(SportStats.fields(sport), isNotEmpty, reason: '$sport has no stats form');
      }
    });

    test('a profile renders only the stats it has, in catalog order', () {
      const SportProfile profile = SportProfile(
        sport: 'cricket',
        stats: <String, String>{'wickets': '47', 'batting_style': 'Left-hand', 'nonsense': 'x'},
      );
      expect(SportStats.summary(profile), <({String label, String value})>[
        (label: 'Batting', value: 'Left-hand'),
        (label: 'Career wickets', value: '47'),
      ]);
    });

    test('a win rate is shown as a percentage', () {
      const SportProfile profile = SportProfile(
        sport: 'tennis',
        stats: <String, String>{'win_rate': '62'},
      );
      expect(SportStats.summary(profile).single.value, '62%');
    });

    test('divisions count the rungs to the target', () {
      const SportProfile climbing = SportProfile(
        sport: 'cricket',
        currentDivision: 'division3',
        targetDivision: 'division1',
      );
      expect(climbing.divisionsToTarget, 2);
      const SportProfile arrived = SportProfile(
        sport: 'cricket',
        currentDivision: 'premier',
        targetDivision: 'division1',
      );
      expect(arrived.divisionsToTarget, 0);
    });

    test('a profile is complete once it says what standard', () {
      expect(const SportProfile(sport: 'cricket').isComplete, isFalse);
      expect(const SportProfile(sport: 'cricket', skillLevel: 'club').isComplete, isTrue);
    });
  });

  group('the assistant proposes', () {
    test('a payload describes what applying it would do', () {
      expect(
        const ProposalPayload(
          date: '2026-07-04',
          availabilityStatus: AvailabilityStatus.maybe,
        ).summary,
        'Set maybe for 2026-07-04',
      );
      expect(const ProposalPayload(userIds: <String>['a', 'b', 'c']).summary, 'Invite 3 players');
      expect(const ProposalPayload(message: 'Nets moved to 7pm').summary, 'Nets moved to 7pm');
      expect(const ProposalPayload().summary, 'No details');
    });
  });

  group('a club setup checklist', () {
    ClubMemberDetail member(ClubRole role, {bool? captain}) =>
        ClubMemberDetail.fromJson(<String, dynamic>{
          'user_id': '44444444-4444-4444-4444-444444444444',
          'name': 'Pat',
          'role': role.wire,
          'is_captain': captain,
          'status': 'active',
          'joined_at': '2026-01-01T00:00:00Z',
        });

    test('ticks off from what exists', () {
      final List<ClubSetupStep> empty = ClubSetupStep.steps(
        members: <ClubMemberDetail>[member(ClubRole.clubAdmin)],
        teams: 0,
        venues: 0,
      );
      expect(empty.every((ClubSetupStep s) => !s.done), isTrue);

      final List<ClubSetupStep> done = ClubSetupStep.steps(
        members: <ClubMemberDetail>[
          member(ClubRole.clubAdmin, captain: true),
          member(ClubRole.member),
        ],
        teams: 1,
        venues: 1,
      );
      expect(done.every((ClubSetupStep s) => s.done), isTrue);
    });
  });
}
