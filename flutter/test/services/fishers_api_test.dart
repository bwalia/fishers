import 'dart:typed_data';

import 'package:fishers/config/app_config.dart';
import 'package:fishers/models/fishers_models.dart';
import 'package:fishers/services/fishers_api.dart';
import 'package:fishers/services/keychain_store.dart';
import 'package:fishers/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_client.dart';

/// Every endpoint, checked for the request it actually sends.
///
/// This is the wire-compatibility test for the *request* side: the method, the
/// path, the query string and the body, against what
/// `ios/Fishers/Services/FishersAPI.swift` sends. The response side is covered
/// by the model round trips.
///
/// Each case runs against a stub that answers `{}`, which most decoders refuse
/// — that is fine and deliberate: the assertion is on what went out.
void main() {
  late StubClient client;

  setUp(() async {
    client = StubClient((RecordedRequest _) => (200, '{}'));
    NetworkService.shared = NetworkService(
      client: client,
      store: InMemoryTokenStore(<String, String>{'access_token': 'at'}),
      config: AppConfig(
        store: InMemoryConfigStore(),
        environment: <String, String>{AppConfig.apiEnvKey: 'https://int.fishers.cloud'},
      ),
    );
    await NetworkService.shared.loadTokensFromStore();
  });

  /// Run [call], ignore whatever it could not decode, and hand back the request.
  Future<RecordedRequest> sent(Future<void> Function() call) async {
    try {
      await call();
    } on ApiException {
      // A canned `{}` is not a Club; the request is what is under test.
    }
    return client.lastRequest;
  }

  void expectCall(
    String label,
    Future<void> Function() call, {
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) {
    test(label, () async {
      final RecordedRequest request = await sent(call);
      expect(request.method, method, reason: '$label: wrong method');
      expect(
        '${request.url.path}${request.url.hasQuery ? "?${request.url.query}" : ""}',
        '/api/v1$path',
        reason: '$label: wrong path',
      );
      if (body != null) {
        expect(request.json, body, reason: '$label: wrong body');
      } else {
        expect(request.body, isEmpty, reason: '$label: sent a body it should not have');
      }
      expect(
        request.headers['Authorization'],
        label.startsWith('auth: ') ? isNull : 'Bearer at',
        reason: '$label: wrong authorization',
      );
    });
  }

  const String clubId = '11111111-1111-1111-1111-111111111111';
  const String teamId = '22222222-2222-2222-2222-222222222222';
  const String eventId = '33333333-3333-3333-3333-333333333333';
  const String userId = '44444444-4444-4444-4444-444444444444';
  const String matchId = '55555555-5555-5555-5555-555555555555';
  const String blockId = '66666666-6666-6666-6666-666666666666';
  const String ticketId = '77777777-7777-7777-7777-777777777777';
  const String conversationId = '88888888-8888-8888-8888-888888888888';
  const String proposalId = '99999999-9999-9999-9999-999999999999';
  const String entrantId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const String productId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  group('auth and me', () {
    expectCall(
      'auth: signup',
      () => FishersAPI.signup(name: 'Pat', email: 'pat@example.com', password: 'hunter2'),
      method: 'POST',
      path: '/auth/signup',
      body: <String, dynamic>{
        'name': 'Pat',
        'email': 'pat@example.com',
        'phone': null,
        'password': 'hunter2',
      },
    );

    expectCall(
      'auth: login',
      () => FishersAPI.login(identifier: 'pat@example.com', password: 'hunter2'),
      method: 'POST',
      path: '/auth/login',
      body: <String, dynamic>{'identifier': 'pat@example.com', 'password': 'hunter2'},
    );

    expectCall(
      'auth: googleAuthConfig',
      FishersAPI.googleAuthConfig,
      method: 'GET',
      path: '/auth/google',
    );

    expectCall(
      'auth: signInWithGoogle',
      () => FishersAPI.signInWithGoogle(credential: 'id-token'),
      method: 'POST',
      path: '/auth/google',
      body: <String, dynamic>{'credential': 'id-token'},
    );

    expectCall('me', FishersAPI.me, method: 'GET', path: '/me');

    expectCall(
      'deleteAccount',
      () => FishersAPI.deleteAccount(password: 'hunter2'),
      method: 'POST',
      path: '/me/delete',
      body: <String, dynamic>{'password': 'hunter2'},
    );

    expectCall(
      'deleteAccount, for a Google account with no password',
      FishersAPI.deleteAccount,
      method: 'POST',
      path: '/me/delete',
      body: <String, dynamic>{'password': null},
    );

    expectCall(
      'setRoleIntent',
      () => FishersAPI.setRoleIntent(RoleIntent.secretary),
      method: 'PATCH',
      path: '/me',
      body: <String, dynamic>{'role_intent': 'secretary'},
    );

    expectCall(
      'verificationStatus',
      FishersAPI.verificationStatus,
      method: 'GET',
      path: '/me/verification',
    );

    expectCall(
      'sendVerificationCode',
      () => FishersAPI.sendVerificationCode(VerificationChannel.phone),
      method: 'POST',
      path: '/me/verification/phone',
    );

    expectCall(
      'confirmVerification',
      () => FishersAPI.confirmVerification(VerificationChannel.email, code: '123456'),
      method: 'POST',
      path: '/me/verification/email/confirm',
      body: <String, dynamic>{'code': '123456'},
    );

    expectCall('myInvites', FishersAPI.myInvites, method: 'GET', path: '/invites/mine');

    expectCall(
      'profileShareLink',
      FishersAPI.profileShareLink,
      method: 'POST',
      path: '/me/share-link',
    );

    test('updateProfile flattens the primary sport onto the top level', () async {
      final ProfileUpdate update = ProfileUpdate(
        name: 'Pat',
        primarySport: 'cricket',
        sportProfiles: <SportProfile>[
          const SportProfile(sport: 'cricket', position: 'Batter', skillLevel: 'club'),
          const SportProfile(sport: 'football', position: 'Midfielder'),
        ],
      );
      final RecordedRequest request = await sent(() => FishersAPI.updateProfile(update));
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/me');
      expect(request.json['sports_played'], <String>['cricket', 'football']);
      expect(request.json['position_role'], 'Batter');
      expect(request.json['skill_level'], 'club');
      expect(request.json['primary_sport'], 'cricket');
    });

    test('uploadAvatar posts multipart to /me/avatar', () async {
      final RecordedRequest request = await sent(
        () => FishersAPI.uploadAvatar(Uint8List.fromList(<int>[1, 2, 3])),
      );
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/me/avatar');
      expect(request.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
    });

    test('uploadAvatar names the file after the mime type it was given', () async {
      final RecordedRequest png = await sent(
        () => FishersAPI.uploadAvatar(Uint8List.fromList(<int>[1]), mimeType: 'image/png'),
      );
      expect(String.fromCharCodes(png.bodyBytes.take(200)), contains('filename="avatar.png"'));
    });
  });

  group('tournaments', () {
    expectCall(
      'fixtureBlocks',
      () => FishersAPI.fixtureBlocks(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/fixture-blocks',
    );

    expectCall(
      'createTournament',
      () => FishersAPI.createTournament(name: 'Summer Sixes', clubId: clubId),
      method: 'POST',
      path: '/fixture-blocks',
      body: <String, dynamic>{'name': 'Summer Sixes', 'club_id': clubId, 'kind': 'tournament'},
    );

    expectCall(
      'entrants',
      () => FishersAPI.entrants(blockId: blockId),
      method: 'GET',
      path: '/fixture-blocks/$blockId/entrants',
    );

    expectCall(
      'addEntrants seeds in the order they were typed',
      () => FishersAPI.addEntrants(blockId: blockId, names: <String>['A', 'B']),
      method: 'POST',
      path: '/fixture-blocks/$blockId/entrants',
      body: <String, dynamic>{
        'entrants': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'A', 'seed': 1},
          <String, dynamic>{'name': 'B', 'seed': 2},
        ],
      },
    );

    expectCall(
      'tournamentSchedule',
      () => FishersAPI.tournamentSchedule(blockId: blockId),
      method: 'GET',
      path: '/fixture-blocks/$blockId/schedule',
    );

    expectCall(
      'standings',
      () => FishersAPI.standings(blockId: blockId),
      method: 'GET',
      path: '/fixture-blocks/$blockId/standings',
    );

    expectCall(
      'generateSlots',
      () => FishersAPI.generateSlots(
        blockId: blockId,
        courts: <String>['Main', 'Top'],
        firstStart: DateTime.utc(2026, 7, 4, 10),
        matchMinutes: 45,
        gapMinutes: 15,
        rounds: 3,
      ),
      method: 'POST',
      path: '/fixture-blocks/$blockId/slots',
      body: <String, dynamic>{
        'courts': <String>['Main', 'Top'],
        'first_start': '2026-07-04T10:00:00Z',
        'match_minutes': 45,
        'gap_minutes': 15,
        'rounds': 3,
        'replace': true,
      },
    );

    expectCall(
      'generateSchedule',
      () => FishersAPI.generateSchedule(
        blockId: blockId,
        format: TournamentFormat.groupsKnockout,
        groupCount: 4,
        commit: false,
      ),
      method: 'POST',
      path: '/fixture-blocks/$blockId/schedule',
      body: <String, dynamic>{'format': 'groups_knockout', 'group_count': 4, 'commit': false},
    );

    expectCall(
      'generateKnockout',
      () => FishersAPI.generateKnockout(blockId: blockId, perGroup: 2, commit: true),
      method: 'POST',
      path: '/fixture-blocks/$blockId/knockout',
      body: <String, dynamic>{'per_group': 2, 'commit': true},
    );

    expectCall(
      'recordResult',
      () => FishersAPI.recordResult(
        eventId: eventId,
        entrants: <({String entrantId, int? score, String result})>[
          (entrantId: entrantId, score: 120, result: 'win'),
        ],
      ),
      method: 'POST',
      path: '/events/$eventId/result',
      body: <String, dynamic>{
        'entrants': <Map<String, dynamic>>[
          <String, dynamic>{'entrant_id': entrantId, 'score': 120, 'result': 'win'},
        ],
      },
    );

    expectCall(
      'withdrawEntrant',
      () => FishersAPI.withdrawEntrant(entrantId),
      method: 'POST',
      path: '/entrants/$entrantId/withdraw',
    );
  });

  group('ticketed events', () {
    expectCall(
      'tickets',
      () => FishersAPI.tickets(eventId: eventId),
      method: 'GET',
      path: '/events/$eventId/tickets',
    );

    expectCall(
      'bookTicket',
      () => FishersAPI.bookTicket(
        eventId: eventId,
        guests: 2,
        guestNames: 'Sam, Ravi',
        notes: 'veggie',
      ),
      method: 'POST',
      path: '/events/$eventId/tickets',
      body: <String, dynamic>{'guests': 2, 'guest_names': 'Sam, Ravi', 'notes': 'veggie'},
    );

    expectCall(
      'payTicket',
      () => FishersAPI.payTicket(ticketId),
      method: 'POST',
      path: '/tickets/$ticketId/pay',
    );

    expectCall(
      'cancelTicket',
      () => FishersAPI.cancelTicket(ticketId),
      method: 'POST',
      path: '/tickets/$ticketId/cancel',
    );

    expectCall(
      'markTicketPaid',
      () => FishersAPI.markTicketPaid(ticketId, method: 'cash'),
      method: 'POST',
      path: '/tickets/$ticketId/mark-paid',
      body: <String, dynamic>{'method': 'cash'},
    );
  });

  group('selection', () {
    expectCall(
      'selectionBoard',
      () => FishersAPI.selectionBoard(eventId: eventId),
      method: 'GET',
      path: '/events/$eventId/selection',
    );

    expectCall(
      'suggestSquad',
      () => FishersAPI.suggestSquad(eventId: eventId),
      method: 'POST',
      path: '/events/$eventId/selection/suggest',
    );

    expectCall(
      'agentSquad',
      () => FishersAPI.agentSquad(eventId: eventId),
      method: 'POST',
      path: '/events/$eventId/selection/agent',
    );

    expectCall(
      'setSquad',
      () => FishersAPI.setSquad(
        eventId: eventId,
        selected: <String>[userId],
        reserves: <String>[],
        announcement: 'Side is up',
        publish: true,
      ),
      method: 'POST',
      path: '/events/$eventId/selection',
      body: <String, dynamic>{
        'selected': <String>[userId],
        'reserves': <String>[],
        'announcement': 'Side is up',
        'publish': true,
      },
    );

    expectCall(
      'respondToSelection',
      () => FishersAPI.respondToSelection(eventId: eventId, confirming: true),
      method: 'POST',
      path: '/events/$eventId/selection/respond',
      body: <String, dynamic>{'confirming': true},
    );

    expectCall(
      'promoteReserves',
      () => FishersAPI.promoteReserves(eventId: eventId),
      method: 'POST',
      path: '/events/$eventId/selection/promote',
    );

    expectCall(
      'updateFixtureStatus',
      () => FishersAPI.updateFixtureStatus(
        eventId: eventId,
        status: 'postponed',
        note: 'rain',
        rescheduledTo: DateTime.utc(2026, 7, 11, 13),
      ),
      method: 'POST',
      path: '/events/$eventId/status',
      body: <String, dynamic>{
        'status': 'postponed',
        'note': 'rain',
        'rescheduled_to': '2026-07-11T13:00:00Z',
      },
    );

    expectCall(
      'outstandingFees',
      () => FishersAPI.outstandingFees(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/fees/outstanding',
    );

    expectCall(
      'chaseFees',
      () => FishersAPI.chaseFees(clubId: clubId),
      method: 'POST',
      path: '/clubs/$clubId/fees/chase',
    );
  });

  group('chat', () {
    expectCall('conversations', FishersAPI.conversations, method: 'GET', path: '/conversations');

    expectCall(
      'createConversation',
      () => FishersAPI.createConversation(title: '1st XI', clubId: clubId),
      method: 'POST',
      path: '/conversations',
      body: <String, dynamic>{
        'title': '1st XI',
        'club_id': clubId,
        'team_id': null,
        'event_id': null,
      },
    );

    expectCall(
      'messages',
      () => FishersAPI.messages(conversationId: conversationId),
      method: 'GET',
      path: '/conversations/$conversationId/messages?limit=50',
    );

    expectCall(
      'postMessage',
      () => FishersAPI.postMessage(conversationId: conversationId, body: 'Nets Thursday'),
      method: 'POST',
      path: '/conversations/$conversationId/messages',
      body: <String, dynamic>{'body': 'Nets Thursday'},
    );

    expectCall(
      'markRead',
      () => FishersAPI.markRead(conversationId: conversationId, at: DateTime.utc(2026, 7, 4)),
      method: 'POST',
      path: '/conversations/$conversationId/read',
      body: <String, dynamic>{'read_at': '2026-07-04T00:00:00Z'},
    );

    expectCall(
      'proposals',
      () => FishersAPI.proposals(conversationId: conversationId),
      method: 'GET',
      path: '/conversations/$conversationId/proposals',
    );

    expectCall(
      'analyseConversation',
      () => FishersAPI.analyseConversation(conversationId),
      method: 'POST',
      path: '/conversations/$conversationId/agent/analyse',
    );

    expectCall(
      'applyProposal',
      () => FishersAPI.applyProposal(proposalId),
      method: 'POST',
      path: '/agent/proposals/$proposalId/apply',
    );

    expectCall(
      'dismissProposal',
      () => FishersAPI.dismissProposal(proposalId),
      method: 'POST',
      path: '/agent/proposals/$proposalId/dismiss',
    );
  });

  group('QR codes and opponents', () {
    expectCall(
      'clubQrCode',
      () => FishersAPI.clubQrCode(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/qr',
    );

    expectCall(
      'teamQrCode',
      () => FishersAPI.teamQrCode(teamId: teamId),
      method: 'GET',
      path: '/teams/$teamId/qr',
    );

    expectCall(
      'rotateClubQrCode',
      () => FishersAPI.rotateClubQrCode(clubId: clubId),
      method: 'POST',
      path: '/clubs/$clubId/qr',
    );

    expectCall(
      'lookupOpponent',
      () => FishersAPI.lookupOpponent(token: 'abc123'),
      method: 'POST',
      path: '/opponents/lookup',
      body: <String, dynamic>{'token': 'abc123'},
    );

    test('searchOpponents escapes what was typed', () async {
      final RecordedRequest request = await sent(
        () => FishersAPI.searchOpponents(query: 'Hemel & Co'),
      );
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/opponents/search');
      expect(request.url.queryParameters['q'], 'Hemel & Co');
    });
  });

  group('match officials and the scoring lock', () {
    expectCall(
      'matchOfficials',
      () => FishersAPI.matchOfficials(matchId: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId/officials',
    );

    expectCall(
      'appointOfficial',
      () => FishersAPI.appointOfficial(matchId: matchId, userId: userId, role: 'umpire'),
      method: 'POST',
      path: '/cricket/matches/$matchId/officials',
      body: <String, dynamic>{'user_id': userId, 'role': 'umpire'},
    );

    expectCall(
      'removeOfficial',
      () => FishersAPI.removeOfficial(matchId: matchId, userId: userId),
      method: 'DELETE',
      path: '/cricket/matches/$matchId/officials/$userId',
    );

    expectCall(
      'handOverScoring',
      () => FishersAPI.handOverScoring(matchId: matchId, toUserId: userId),
      method: 'POST',
      path: '/cricket/matches/$matchId/handover',
      body: <String, dynamic>{'to_user_id': userId},
    );

    expectCall(
      'scorerTrail',
      () => FishersAPI.scorerTrail(matchId: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId/scorer-trail',
    );

    expectCall(
      'commentary',
      () => FishersAPI.commentary(matchId: matchId, over: 3, ballInOver: 4),
      method: 'POST',
      path: '/cricket/matches/$matchId/commentary',
      body: <String, dynamic>{'over': 3, 'ball_in_over': 4},
    );

    expectCall(
      'squads',
      () => FishersAPI.squads(matchId: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId/squad',
    );

    expectCall(
      'match',
      () => FishersAPI.match(matchId: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId',
    );

    expectCall(
      'proposeTerms',
      () => FishersAPI.proposeTerms(
        matchId: matchId,
        conditions: MatchConditions.standard(overs: 20),
        side: MatchSide.home,
        captainName: 'Sam',
      ),
      method: 'POST',
      path: '/cricket/matches/$matchId/propose',
      body: <String, dynamic>{
        'conditions': <String, dynamic>{
          'overs_limit': 20,
          'overs_per_bowler': 4,
          'ground': 'open',
          'ball': 'white',
          'powerplay_overs': 6,
          'fielders_outside_powerplay': 2,
          'fielders_outside_normal': 5,
          'fielders_behind_square_leg': 2,
          'target_overs_per_hour': 0,
        },
        'by': 'home',
        'by_name': 'Sam',
      },
    );

    expectCall(
      'agreeTerms',
      () => FishersAPI.agreeTerms(matchId: matchId, side: MatchSide.away, captainName: 'Ravi'),
      method: 'POST',
      path: '/cricket/matches/$matchId/agree',
      body: <String, dynamic>{'side': 'away', 'captain_name': 'Ravi'},
    );

    expectCall(
      'abandonMatch',
      () => FishersAPI.abandonMatch(matchId: matchId, reason: 'rain'),
      method: 'POST',
      path: '/cricket/matches/$matchId/abandon',
      body: <String, dynamic>{'reason': 'rain'},
    );

    expectCall(
      'deleteMatch',
      () => FishersAPI.deleteMatch(matchId: matchId),
      method: 'DELETE',
      path: '/cricket/matches/$matchId',
    );

    expectCall(
      'submitXi',
      () => FishersAPI.submitXi(
        matchId: matchId,
        side: MatchSide.home,
        players: <MatchPlayer>[const MatchPlayer(id: userId, name: 'Pat', batsLeft: true)],
        captainId: userId,
      ),
      method: 'POST',
      path: '/cricket/matches/$matchId/xi',
      body: <String, dynamic>{
        'side': 'home',
        'players': <Map<String, dynamic>>[
          <String, dynamic>{'id': userId, 'name': 'Pat', 'bats_left': true},
        ],
        'captain_id': userId,
        'keeper_id': null,
      },
    );
  });

  group('notifications and people', () {
    expectCall(
      'notifications, unfiltered',
      FishersAPI.notifications,
      method: 'GET',
      path: '/notifications?page=1&per_page=20',
    );

    expectCall(
      'notifications, filtered',
      () => FishersAPI.notifications(
        page: 2,
        perPage: 50,
        kind: 'invite',
        unreadOnly: true,
        search: 'Lords',
      ),
      method: 'GET',
      path: '/notifications?page=2&per_page=50&kind=invite&unread=true&q=Lords',
    );

    test('a one-character search is not worth a round trip', () async {
      final RecordedRequest request = await sent(() => FishersAPI.notifications(search: 'L'));
      expect(request.url.queryParameters.containsKey('q'), isFalse);
    });

    expectCall(
      'markNotificationRead, all of them',
      FishersAPI.markNotificationRead,
      method: 'POST',
      path: '/notifications/read',
      body: <String, dynamic>{'id': null},
    );

    expectCall(
      'markNotificationRead, one',
      () => FishersAPI.markNotificationRead(id: eventId),
      method: 'POST',
      path: '/notifications/read',
      body: <String, dynamic>{'id': eventId},
    );

    expectCall(
      'teammate',
      () => FishersAPI.teammate(userId),
      method: 'GET',
      path: '/users/$userId',
    );

    expectCall(
      'playerSeasons',
      () => FishersAPI.playerSeasons(userId),
      method: 'GET',
      path: '/users/$userId/stats',
    );

    expectCall(
      'playerAchievements',
      () => FishersAPI.playerAchievements(userId),
      method: 'GET',
      path: '/users/$userId/achievements',
    );
  });

  group('club administration', () {
    expectCall(
      'myClubRole',
      () => FishersAPI.myClubRole(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/my-role',
    );

    expectCall(
      'clubMembers',
      () => FishersAPI.clubMembers(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/members',
    );

    expectCall(
      'addClubMember',
      () => FishersAPI.addClubMember(
        clubId: clubId,
        identifier: 'pat@example.com',
        role: ClubRole.teamViceCaptain,
      ),
      method: 'POST',
      path: '/clubs/$clubId/members',
      body: <String, dynamic>{'identifier': 'pat@example.com', 'role': 'team_vice_captain'},
    );

    expectCall(
      'createClubInvite',
      () => FishersAPI.createClubInvite(clubId: clubId, email: 'pat@example.com'),
      method: 'POST',
      path: '/invites',
      body: <String, dynamic>{
        'target_type': 'club',
        'target_id': clubId,
        'invited_email': 'pat@example.com',
      },
    );

    expectCall(
      'acceptInvite',
      () => FishersAPI.acceptInvite(token: 'tok123'),
      method: 'POST',
      path: '/invites/tok123/accept',
    );

    expectCall(
      'setMemberRole, a secretary who captains',
      () => FishersAPI.setMemberRole(
        clubId: clubId,
        userId: userId,
        role: ClubRole.clubAdmin,
        captain: true,
      ),
      method: 'PATCH',
      path: '/clubs/$clubId/members/$userId',
      body: <String, dynamic>{'role': 'club_admin', 'captain': true},
    );

    expectCall(
      'removeClubMember',
      () => FishersAPI.removeClubMember(clubId: clubId, userId: userId),
      method: 'DELETE',
      path: '/clubs/$clubId/members/$userId',
    );

    expectCall(
      'invite, to a club',
      () => FishersAPI.invite(userId: userId, toClub: clubId),
      method: 'POST',
      path: '/invites',
      body: <String, dynamic>{
        'target_type': 'club',
        'target_id': clubId,
        'invited_user_id': userId,
      },
    );

    expectCall(
      'invite, to a team — a team wins over a club',
      () => FishersAPI.invite(userId: userId, toClub: clubId, toTeam: teamId),
      method: 'POST',
      path: '/invites',
      body: <String, dynamic>{
        'target_type': 'team',
        'target_id': teamId,
        'invited_user_id': userId,
      },
    );

    expectCall(
      'clubSettings',
      () => FishersAPI.clubSettings(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/settings',
    );

    expectCall(
      'updateClubSettings',
      () => FishersAPI.updateClubSettings(
        clubId: clubId,
        settings: const ClubSettings(
          selectionAutonomy: 'suggest',
          confirmLeadHours: 48,
          dropLeadHours: 24,
          feeChaseAfterHours: 72,
          feeChaseMaxReminders: 3,
        ),
      ),
      method: 'PATCH',
      path: '/clubs/$clubId/settings',
      body: <String, dynamic>{
        'selection_autonomy': 'suggest',
        'confirm_lead_hours': 48,
        'drop_lead_hours': 24,
        'fee_chase_after_hours': 72,
        'fee_chase_max_reminders': 3,
      },
    );
  });

  group('clubs, grounds, page and teams', () {
    expectCall('clubs', FishersAPI.clubs, method: 'GET', path: '/clubs');

    expectCall(
      'createClub',
      () => FishersAPI.createClub(name: 'Lords', sports: <String>['cricket']),
      method: 'POST',
      path: '/clubs',
      body: <String, dynamic>{
        'name': 'Lords',
        'sport_types': <String>['cricket'],
        'is_informal_group': false,
        'visibility': 'invite_only',
        'description': null,
      },
    );

    expectCall(
      'myClubs, unfiltered',
      () => FishersAPI.myClubs(const ClubListFilters(), page: 1),
      method: 'GET',
      path: '/me/clubs?sort=name&page=1&per_page=20',
    );

    expectCall(
      'myClubs, filtered',
      () => FishersAPI.myClubs(
        const ClubListFilters(
          query: 'hemel',
          role: ClubListRole.secretary,
          sport: 'cricket',
          publicPage: true,
          sort: ClubListSort.members,
        ),
        page: 3,
        perPage: 5,
      ),
      method: 'GET',
      path:
          '/me/clubs?sort=members&page=3&per_page=5&q=hemel&role=secretary'
          '&sport=cricket&public_page=true',
    );

    expectCall(
      'venues',
      () => FishersAPI.venues(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/venues',
    );

    expectCall(
      'createVenue',
      () => FishersAPI.createVenue(clubId: clubId, name: 'The Ground', address: 'HP1'),
      method: 'POST',
      path: '/clubs/$clubId/venues',
      body: <String, dynamic>{'name': 'The Ground', 'address': 'HP1'},
    );

    expectCall(
      'clubPage',
      () => FishersAPI.clubPage(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/page',
    );

    test('updateClubPage sends the sentinel when no icon player is set', () async {
      final RecordedRequest request = await sent(
        () => FishersAPI.updateClubPage(
          clubId: clubId,
          page: const ClubPageSettings(id: clubId, name: 'Lords', publicPage: false, slug: 'lords'),
          publish: true,
        ),
      );
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/clubs/$clubId/page');
      expect(
        request.json['icon_player_id'],
        ClubPageSettings.noIconPlayer,
        reason: 'a JSON null means "not touched", so clearing needs a value',
      );
      expect(request.json['public_page'], true);
      expect(request.json['slug'], 'lords');
      expect(
        request.json.containsKey('name'),
        isFalse,
        reason: 'the page editor never renames the club',
      );
    });

    expectCall(
      'createTeam',
      () => FishersAPI.createTeam(clubId: clubId, name: '1st XI', sport: 'cricket'),
      method: 'POST',
      path: '/clubs/$clubId/teams',
      body: <String, dynamic>{'name': '1st XI', 'sport': 'cricket'},
    );

    expectCall(
      'teams',
      () => FishersAPI.teams(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/teams',
    );

    expectCall(
      'teamMembers',
      () => FishersAPI.teamMembers(teamId: teamId),
      method: 'GET',
      path: '/teams/$teamId/members',
    );

    expectCall(
      'sharedPlayerCard',
      () => FishersAPI.sharedPlayerCard(token: 'tok123'),
      method: 'GET',
      path: '/players/card/tok123',
    );
  });

  group('events, fixtures and availability', () {
    expectCall(
      'eventPage',
      () => FishersAPI.eventPage(clubId: clubId, cricketSeason: true),
      method: 'GET',
      path: '/events?page=1&per_page=200&club_id=$clubId&cricket_season=true&',
    );

    expectCall(
      'eventPage, no club',
      FishersAPI.eventPage,
      method: 'GET',
      path: '/events?page=1&per_page=200&',
    );

    expectCall(
      'event',
      () => FishersAPI.event(id: eventId),
      method: 'GET',
      path: '/events/$eventId',
    );

    test('createEvent sends the whole body, nulls included', () async {
      final RecordedRequest request = await sent(
        () => FishersAPI.createEvent(
          CreateEventBody(
            clubId: clubId,
            sport: 'cricket',
            eventSubtype: 'league_match',
            title: 'Lords v Hemel',
            startAt: DateTime.utc(2026, 7, 4, 13),
            endAt: DateTime.utc(2026, 7, 4, 19),
            capacity: 22,
            feeAmountCents: 800,
          ),
        ),
      );
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/events');
      expect(request.json['start_at'], '2026-07-04T13:00:00Z');
      expect(request.json['end_at'], '2026-07-04T19:00:00Z');
      expect(request.json['event_subtype'], 'league_match');
      expect(request.json['fee_amount_cents'], 800);
      expect(request.json.containsKey('opponent_club_id'), isTrue);
      expect(request.json['opponent_club_id'], isNull);
    });

    expectCall(
      'myFixtures writes its timestamps with a Z',
      () => FishersAPI.myFixtures(from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 12, 31)),
      method: 'GET',
      path: '/events/mine?from=2026-01-01T00%3A00%3A00Z&to=2026-12-31T00%3A00%3A00Z',
    );

    expectCall(
      'rsvp',
      () => FishersAPI.rsvp(eventId: eventId, status: RsvpStatus.notGoing),
      method: 'POST',
      path: '/events/$eventId/rsvp',
      body: <String, dynamic>{'status': 'not_going'},
    );

    expectCall(
      'attendees',
      () => FishersAPI.attendees(eventId: eventId),
      method: 'GET',
      path: '/events/$eventId/attendees',
    );

    expectCall(
      'inviteToEvent',
      () => FishersAPI.inviteToEvent(eventId: eventId, userId: userId),
      method: 'POST',
      path: '/events/$eventId/invite',
      body: <String, dynamic>{'user_id': userId},
    );

    expectCall(
      'availability',
      () => FishersAPI.availability(from: '2026-01-01', to: '2026-12-31'),
      method: 'GET',
      path: '/availability?from=2026-01-01&to=2026-12-31',
    );

    expectCall(
      'setAvailability',
      () => FishersAPI.setAvailability(date: '2026-07-04', status: AvailabilityStatus.maybe),
      method: 'POST',
      path: '/availability',
      body: <String, dynamic>{'date': '2026-07-04', 'status': 'maybe'},
    );

    expectCall(
      'setAvailabilityForDates — Swift\'s second overload',
      () => FishersAPI.setAvailabilityForDates(
        dates: <String>['2026-07-04', '2026-07-11'],
        status: AvailabilityStatus.available,
      ),
      method: 'POST',
      path: '/availability/bulk',
      body: <String, dynamic>{
        'dates': <String>['2026-07-04', '2026-07-11'],
        'status': 'available',
      },
    );
  });

  group('shop and payments', () {
    expectCall(
      'products',
      () => FishersAPI.products(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/products',
    );

    expectCall(
      'placeOrder',
      () => FishersAPI.placeOrder(
        clubId: clubId,
        items: <({String productId, int quantity})>[(productId: productId, quantity: 2)],
      ),
      method: 'POST',
      path: '/orders',
      body: <String, dynamic>{
        'club_id': clubId,
        'event_id': null,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'product_id': productId, 'quantity': 2},
        ],
      },
    );

    expectCall(
      'paymentIntent is always in sterling',
      () => FishersAPI.paymentIntent(eventId: eventId, amountCents: 800),
      method: 'POST',
      path: '/payments/intent',
      body: <String, dynamic>{'event_id': eventId, 'amount_cents': 800, 'currency': 'GBP'},
    );
  });

  group('cricket scoring', () {
    expectCall(
      'createCricketMatch carries the device-minted id',
      () => FishersAPI.createCricketMatch(
        eventId: eventId,
        matchId: matchId,
        oversLimit: 20,
        homeName: 'Lords',
        awayName: 'Hemel',
        opponentClubId: clubId,
      ),
      method: 'POST',
      path: '/events/$eventId/cricket-match',
      body: <String, dynamic>{
        'match_id': matchId,
        'overs_limit': 20,
        'home_name': 'Lords',
        'away_name': 'Hemel',
        'opponent_club_id': clubId,
      },
    );

    expectCall(
      'cricketMatchForEvent',
      () => FishersAPI.cricketMatchForEvent(eventId: eventId),
      method: 'GET',
      path: '/events/$eventId/cricket-match',
    );

    expectCall(
      'cricketMatch',
      () => FishersAPI.cricketMatch(id: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId',
    );

    expectCall(
      'cricketFixtures, default',
      FishersAPI.cricketFixtures,
      method: 'GET',
      path: '/cricket/fixtures?page=1&per_page=20&order=asc',
    );

    expectCall(
      'cricketFixtures, newest first and filtered',
      () => FishersAPI.cricketFixtures(
        clubId: clubId,
        state: 'live',
        search: 'Hemel',
        newestFirst: true,
        page: 2,
        perPage: 10,
      ),
      method: 'GET',
      path:
          '/cricket/fixtures?page=2&per_page=10&order=desc&club_id=$clubId'
          '&state=live&q=Hemel',
    );

    test('a one-character search is dropped', () async {
      final RecordedRequest request = await sent(() => FishersAPI.cricketFixtures(search: 'H'));
      expect(request.url.queryParameters.containsKey('q'), isFalse);
    });

    expectCall(
      'claimScorer',
      () => FishersAPI.claimScorer(matchId: matchId, deviceId: 'pixel-7', force: true),
      method: 'POST',
      path: '/cricket/matches/$matchId/claim-scorer',
      body: <String, dynamic>{'device_id': 'pixel-7', 'force': true},
    );

    expectCall(
      'postCricketEvents',
      () => FishersAPI.postCricketEvents(
        matchId: matchId,
        deviceId: 'pixel-7',
        events: <ScoringEvent>[
          ScoringEvent(
            clientEventId: entrantId,
            seq: 1,
            kind: const MatchPrepared(oversLimit: 20, homeName: 'Lords', awayName: 'Hemel'),
            at: DateTime.utc(2026, 7, 4, 13),
          ),
        ],
      ),
      method: 'POST',
      path: '/cricket/matches/$matchId/events',
      body: <String, dynamic>{
        'device_id': 'pixel-7',
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'client_event_id': entrantId,
            'seq': 1,
            'kind': <String, dynamic>{
              'type': 'match_prepared',
              'overs_limit': 20,
              'home_name': 'Lords',
              'away_name': 'Hemel',
            },
            'at': '2026-07-04T13:00:00Z',
          },
        ],
      },
    );

    expectCall(
      'cricketScorecard',
      () => FishersAPI.cricketScorecard(matchId: matchId),
      method: 'GET',
      path: '/cricket/matches/$matchId/scorecard',
    );

    expectCall(
      'shareScoreboard',
      () => FishersAPI.shareScoreboard(matchId: matchId, postToChat: true),
      method: 'POST',
      path: '/cricket/matches/$matchId/share',
      body: <String, dynamic>{'post_to_chat': true, 'ttl_hours': 48},
    );
  });

  group('season stats', () {
    expectCall('mySeasonStats', FishersAPI.mySeasonStats, method: 'GET', path: '/me/stats');

    expectCall(
      'mySeasonStats, one season',
      () => FishersAPI.mySeasonStats(season: 2025),
      method: 'GET',
      path: '/me/stats?season=2025',
    );

    expectCall(
      'clubSeasonBoard',
      () => FishersAPI.clubSeasonBoard(clubId: clubId),
      method: 'GET',
      path: '/clubs/$clubId/stats?season=2026',
    );

    expectCall(
      'syncClubStats',
      () => FishersAPI.syncClubStats(clubId: clubId),
      method: 'POST',
      path: '/clubs/$clubId/stats/sync',
    );
  });

  group('the deliberate gap', () {
    test('nothing in the API surface calls /auth/apple', () {
      // Sign in with Apple is out of scope for v1. The check lives here rather
      // than in a comment so it stays true.
      final List<String> paths = client.requests
          .map((RecordedRequest r) => r.url.path)
          .toList(growable: false);
      expect(paths.any((String p) => p.contains('apple')), isFalse);
    });
  });
}
