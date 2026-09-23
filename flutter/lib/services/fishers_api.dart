import 'dart:typed_data';

import '../config/app_config.dart';
import '../models/fishers_models.dart';
import 'network_service.dart';
import 'social_auth.dart';

/// Every endpoint the app calls, typed — a port of
/// `ios/Fishers/Services/FishersAPI.swift`, in the same order, so the two can
/// be diffed.
///
/// No screen hand-rolls a URL. Swift has 126 functions here; this has 124,
/// and the two that are missing are `appleAuthConfig` and `signInWithApple`:
/// **Sign in with Apple is out of scope for v1**, so `/auth/apple` is never
/// called.
///
/// Swift's two `setAvailability` overloads become [setAvailability] and
/// [setAvailabilityForDates], because Dart has no overloading. Nothing else
/// differs.
abstract final class FishersAPI {
  static NetworkService get _net => NetworkService.shared;

  static Future<ClubRoleInfo> myClubRole({required String clubId}) =>
      _net.requestObject('GET', '/clubs/$clubId/my-role', ClubRoleInfo.fromJson);

  /// Delete this account, which cannot be undone.
  ///
  /// The password is asked for when the account has one, so a live session on a
  /// phone somebody else is holding is not enough to end it. Accounts that sign
  /// in with Google have none and send null.
  static Future<void> deleteAccount({String? password}) =>
      _net.requestVoid('POST', '/me/delete', body: <String, dynamic>{'password': password});

  static Future<void> inviteToEvent({required String eventId, required String userId}) => _net
      .requestVoid('POST', '/events/$eventId/invite', body: <String, dynamic>{'user_id': userId});

  /// An address or a mobile number — whichever they actually use. Sending both
  /// as null is rejected by the API, not silently accepted.
  static Future<AuthTokens> signup({
    required String name,
    String? email,
    String? phone,
    required String password,
  }) => _net.requestObject(
    'POST',
    '/auth/signup',
    AuthTokens.fromJson,
    body: <String, dynamic>{'name': name, 'email': email, 'phone': phone, 'password': password},
    authorized: false,
  );

  static Future<AuthTokens> login({required String identifier, required String password}) =>
      _net.requestObject(
        'POST',
        '/auth/login',
        AuthTokens.fromJson,
        body: <String, dynamic>{'identifier': identifier, 'password': password},
        authorized: false,
      );

  /// Whether the Google button should show, and the client id to use.
  static Future<SocialAuthConfig> googleAuthConfig() =>
      _net.requestObject('GET', '/auth/google', SocialAuthConfig.fromJson, authorized: false);

  /// Google ID token → Fishers session (sign-in or register).
  static Future<SocialSignedIn> signInWithGoogle({required String credential}) =>
      _net.requestObject(
        'POST',
        '/auth/google',
        SocialSignedIn.fromJson,
        body: <String, dynamic>{'credential': credential},
        authorized: false,
      );

  static Future<PublicUser> me() => _net.requestObject('GET', '/me', PublicUser.fromJson);

  // MARK: Onboarding

  /// Only the one field: `PATCH /me` leaves everything it is not sent alone.
  static Future<PublicUser> setRoleIntent(RoleIntent role) => _net.requestObject(
    'PATCH',
    '/me',
    PublicUser.fromJson,
    body: <String, dynamic>{'role_intent': role.wire},
  );

  static Future<VerificationStatus> verificationStatus() =>
      _net.requestObject('GET', '/me/verification', VerificationStatus.fromJson);

  static Future<VerificationSent> sendVerificationCode(VerificationChannel channel) =>
      _net.requestObject('POST', '/me/verification/${channel.wire}', VerificationSent.fromJson);

  /// Answers with the user, now marked verified.
  static Future<PublicUser> confirmVerification(
    VerificationChannel channel, {
    required String code,
  }) => _net.requestObject(
    'POST',
    '/me/verification/${channel.wire}/confirm',
    PublicUser.fromJson,
    body: <String, dynamic>{'code': code},
  );

  // MARK: Man of the match

  /// The club's vote for a fixture. Throws a 404 when the game has not
  /// finished, or finished without a team sheet to vote on.
  static Future<MotmPollView> motmPollForEvent({required String eventId}) =>
      _net.requestObject('GET', '/events/$eventId/motm', MotmPollView.fromJson);

  static Future<MotmPollView> motmPoll({required String pollId}) =>
      _net.requestObject('GET', '/motm/polls/$pollId', MotmPollView.fromJson);

  /// Vote, or move a vote already cast. The answer carries the tally, which
  /// the API withholds until you have voted.
  static Future<MotmPollView> voteForManOfTheMatch({
    required String pollId,
    required String candidateUserId,
  }) => _net.requestObject(
    'POST',
    '/motm/polls/$pollId/vote',
    MotmPollView.fromJson,
    body: <String, dynamic>{'candidate_user_id': candidateUserId},
  );

  static Future<MotmPollView> withdrawManOfTheMatchVote({required String pollId}) =>
      _net.requestObject('DELETE', '/motm/polls/$pollId/vote', MotmPollView.fromJson);

  /// Captain or secretary: end the vote now rather than waiting it out. A 403
  /// is ordinary — most of a club cannot close one — and is worth saying in
  /// plain words rather than passing on the permission's own name.
  static Future<MotmPollView> closeManOfTheMatchVote({required String pollId}) =>
      _net.requestObject('POST', '/motm/polls/$pollId/close', MotmPollView.fromJson);

  static Future<List<PendingInvite>> myInvites() =>
      _net.requestList('GET', '/invites/mine', PendingInvite.fromJson);

  /// The link a player sends their secretary. The same token comes back each
  /// time until it is rotated, so asking twice is harmless.
  static Future<Uri> profileShareLink() async {
    final ShareLinkToken link = await _net.requestObject(
      'POST',
      '/me/share-link',
      ShareLinkToken.fromJson,
    );
    return Uri.parse('${AppConfig.instance.webBaseUrl}/p/${link.token}');
  }

  /// Profile setup and later edits both send the whole profile the app holds.
  static Future<PublicUser> updateProfile(ProfileUpdate update) =>
      _net.requestObject('PATCH', '/me', PublicUser.fromJson, body: update.toJson());

  // MARK: Tournaments

  static Future<List<FixtureBlock>> fixtureBlocks({required String clubId}) =>
      _net.requestList('GET', '/clubs/$clubId/fixture-blocks', FixtureBlock.fromJson);

  static Future<FixtureBlock> createTournament({
    required String name,
    required String clubId,
    String kind = 'tournament',
  }) => _net.requestObject(
    'POST',
    '/fixture-blocks',
    FixtureBlock.fromJson,
    body: <String, dynamic>{'name': name, 'club_id': clubId, 'kind': kind},
  );

  static Future<List<TournamentEntrant>> entrants({required String blockId}) =>
      _net.requestList('GET', '/fixture-blocks/$blockId/entrants', TournamentEntrant.fromJson);

  static Future<List<TournamentEntrant>> addEntrants({
    required String blockId,
    required List<String> names,
  }) => _net.requestList(
    'POST',
    '/fixture-blocks/$blockId/entrants',
    TournamentEntrant.fromJson,
    body: <String, dynamic>{
      'entrants': <Map<String, dynamic>>[
        for (int i = 0; i < names.length; i++) <String, dynamic>{'name': names[i], 'seed': i + 1},
      ],
    },
  );

  /// Ask a club into a tournament. They answer for themselves — this creates
  /// the invitation, not the entry.
  ///
  /// Either `clubId` for a club on Fishers, who answer in the app, or `name`
  /// plus `contactEmail` for one that is not, who answer by following a link.
  static Future<InviteEntrantResult> inviteEntrant({
    required String blockId,
    String? clubId,
    String? teamId,
    String? name,
    String? contactEmail,
  }) => _net.requestObject(
    'POST',
    '/fixture-blocks/$blockId/invite',
    InviteEntrantResult.fromJson,
    body: <String, dynamic>{
      'club_id': clubId,
      'team_id': teamId,
      'name': name,
      'contact_email': contactEmail,
    },
  );

  /// Tournaments this club has been asked into and has not answered.
  static Future<List<EntryInvitation>> tournamentInvitations({required String clubId}) =>
      _net.requestList(
        'GET',
        '/clubs/$clubId/tournament-invites?pending=true',
        EntryInvitation.fromJson,
      );

  /// Accept or decline on behalf of the invited club.
  static Future<TournamentEntrant> respondToEntry({
    required String entrantId,
    required EntryStatus status,
  }) => _net.requestObject(
    'POST',
    '/entrants/$entrantId/respond',
    TournamentEntrant.fromJson,
    body: <String, dynamic>{'status': status.wire},
  );

  static Future<List<ScheduleRow>> tournamentSchedule({required String blockId}) =>
      _net.requestList('GET', '/fixture-blocks/$blockId/schedule', ScheduleRow.fromJson);

  static Future<List<Standing>> standings({required String blockId}) =>
      _net.requestList('GET', '/fixture-blocks/$blockId/standings', Standing.fromJson);

  /// Lay out the grid: one slot per court per round.
  static Future<void> generateSlots({
    required String blockId,
    required List<String> courts,
    required DateTime firstStart,
    required int matchMinutes,
    required int gapMinutes,
    required int rounds,
  }) => _net.requestVoid(
    'POST',
    '/fixture-blocks/$blockId/slots',
    body: <String, dynamic>{
      'courts': courts,
      'first_start': encodeDate(firstStart),
      'match_minutes': matchMinutes,
      'gap_minutes': gapMinutes,
      'rounds': rounds,
      'replace': true,
    },
  );

  /// `commit: false` previews the fixture list without writing it.
  static Future<void> generateSchedule({
    required String blockId,
    required TournamentFormat format,
    int? groupCount,
    required bool commit,
  }) => _net.requestVoid(
    'POST',
    '/fixture-blocks/$blockId/schedule',
    body: <String, dynamic>{'format': format.wire, 'group_count': groupCount, 'commit': commit},
  );

  static Future<void> generateKnockout({
    required String blockId,
    required int perGroup,
    required bool commit,
  }) => _net.requestVoid(
    'POST',
    '/fixture-blocks/$blockId/knockout',
    body: <String, dynamic>{'per_group': perGroup, 'commit': commit},
  );

  static Future<void> recordResult({
    required String eventId,
    required List<({String entrantId, int? score, String result})> entrants,
  }) => _net.requestVoid(
    'POST',
    '/events/$eventId/result',
    body: <String, dynamic>{
      'entrants': <Map<String, dynamic>>[
        for (final ({String entrantId, int? score, String result}) line in entrants)
          <String, dynamic>{
            'entrant_id': line.entrantId,
            'score': line.score,
            'result': line.result,
          },
      ],
    },
  );

  // MARK: Ticketed events

  static Future<TicketBooking> tickets({required String eventId}) =>
      _net.requestObject('GET', '/events/$eventId/tickets', TicketBooking.fromJson);

  static Future<EventTicket> bookTicket({
    required String eventId,
    required int guests,
    String? guestNames,
    String? notes,
  }) => _net.requestObject(
    'POST',
    '/events/$eventId/tickets',
    EventTicket.fromJson,
    body: <String, dynamic>{'guests': guests, 'guest_names': guestNames, 'notes': notes},
  );

  static Future<EventTicket> payTicket(String ticketId) =>
      _net.requestObject('POST', '/tickets/$ticketId/pay', EventTicket.fromJson);

  static Future<EventTicket> cancelTicket(String ticketId) =>
      _net.requestObject('POST', '/tickets/$ticketId/cancel', EventTicket.fromJson);

  // MARK: Selection

  static Future<SelectionBoard> selectionBoard({required String eventId}) =>
      _net.requestObject('GET', '/events/$eventId/selection', SelectionBoard.fromJson);

  /// Deterministic pick — no model, works with no API key on the server.
  static Future<SquadProposal> suggestSquad({required String eventId}) =>
      _net.requestObject('POST', '/events/$eventId/selection/suggest', SquadProposal.fromJson);

  /// Let the assistant decide the side.
  static Future<SquadProposal> agentSquad({required String eventId}) =>
      _net.requestObject('POST', '/events/$eventId/selection/agent', SquadProposal.fromJson);

  static Future<SelectionBoard> setSquad({
    required String eventId,
    required List<String> selected,
    required List<String> reserves,
    String? announcement,
    required bool publish,
  }) => _net.requestObject(
    'POST',
    '/events/$eventId/selection',
    SelectionBoard.fromJson,
    body: <String, dynamic>{
      'selected': selected,
      'reserves': reserves,
      'announcement': announcement,
      'publish': publish,
    },
  );

  /// The player's reconfirmation, a couple of days out.
  static Future<void> respondToSelection({required String eventId, required bool confirming}) =>
      _net.requestVoid(
        'POST',
        '/events/$eventId/selection/respond',
        body: <String, dynamic>{'confirming': confirming},
      );

  /// Rain stops play: change the fixture and tell the squad.
  static Future<void> updateFixtureStatus({
    required String eventId,
    required String status,
    String? note,
    DateTime? rescheduledTo,
  }) => _net.requestVoid(
    'POST',
    '/events/$eventId/status',
    body: <String, dynamic>{
      'status': status,
      'note': note,
      'rescheduled_to': encodeDateOrNull(rescheduledTo),
    },
  );

  static Future<OutstandingFees> outstandingFees({required String clubId}) =>
      _net.requestObject('GET', '/clubs/$clubId/fees/outstanding', OutstandingFees.fromJson);

  static Future<void> chaseFees({required String clubId}) =>
      _net.requestVoid('POST', '/clubs/$clubId/fees/chase');

  // MARK: Chat

  static Future<List<ConversationSummary>> conversations() =>
      _net.requestList('GET', '/conversations', ConversationSummary.fromJson);

  static Future<Conversation> createConversation({
    required String title,
    String? clubId,
    String? teamId,
    String? eventId,
  }) => _net.requestObject(
    'POST',
    '/conversations',
    Conversation.fromJson,
    body: <String, dynamic>{
      'title': title,
      'club_id': clubId,
      'team_id': teamId,
      'event_id': eventId,
    },
  );

  static Future<List<ChatMessage>> messages({required String conversationId, int limit = 50}) =>
      _net.requestList(
        'GET',
        '/conversations/$conversationId/messages?limit=$limit',
        ChatMessage.fromJson,
      );

  static Future<ChatMessage> postMessage({required String conversationId, required String body}) =>
      _net.requestObject(
        'POST',
        '/conversations/$conversationId/messages',
        ChatMessage.fromJson,
        body: <String, dynamic>{'body': body},
      );

  static Future<void> markRead({required String conversationId, DateTime? at}) => _net.requestVoid(
    'POST',
    '/conversations/$conversationId/read',
    body: <String, dynamic>{'read_at': encodeDate(at ?? DateTime.now())},
  );

  static Future<List<AgentProposal>> proposals({required String conversationId}) =>
      _net.requestList('GET', '/conversations/$conversationId/proposals', AgentProposal.fromJson);

  /// Asks the assistant to read the thread and propose what needs doing.
  static Future<AgentAnalysis> analyseConversation(String conversationId) => _net.requestObject(
    'POST',
    '/conversations/$conversationId/agent/analyse',
    AgentAnalysis.fromJson,
  );

  static Future<AgentProposal> applyProposal(String id) =>
      _net.requestObject('POST', '/agent/proposals/$id/apply', AgentProposal.fromJson);

  static Future<AgentProposal> dismissProposal(String id) =>
      _net.requestObject('POST', '/agent/proposals/$id/dismiss', AgentProposal.fromJson);

  // MARK: Push

  /// The token this device hears notifications on. `platform` tells the
  /// server which transport to use: `android` is FCM, `ios` is APNs, `web` is
  /// a Web Push subscription.
  static Future<void> registerDevice({required String token, required String platform}) =>
      _net.requestVoid(
        'POST',
        '/notifications/register-device',
        body: <String, dynamic>{'device_token': token, 'platform': platform},
      );

  /// Stop pushing to this device. Scoped to the caller by the server, so
  /// knowing somebody else's token buys nothing.
  static Future<void> unregisterDevice({required String token}) => _net.requestVoid(
    'POST',
    '/notifications/unregister-device',
    body: <String, dynamic>{'device_token': token},
  );

  // MARK: QR codes and opponents

  static Future<ClubQrCode> clubQrCode({required String clubId}) =>
      _net.requestObject('GET', '/clubs/$clubId/qr', ClubQrCode.fromJson);

  static Future<ClubQrCode> teamQrCode({required String teamId}) =>
      _net.requestObject('GET', '/teams/$teamId/qr', ClubQrCode.fromJson);

  /// Retires the old code immediately.
  static Future<ClubQrCode> rotateClubQrCode({required String clubId}) =>
      _net.requestObject('POST', '/clubs/$clubId/qr', ClubQrCode.fromJson);

  /// Resolve a scanned code — or the whole URL the camera read — to a side.
  static Future<ClubIdentity> lookupOpponent({required String token}) => _net.requestObject(
    'POST',
    '/opponents/lookup',
    ClubIdentity.fromJson,
    body: <String, dynamic>{'token': token},
  );

  static Future<List<ClubIdentity>> searchOpponents({required String query}) => _net.requestList(
    'GET',
    '/opponents/search?q=${Uri.encodeQueryComponent(query)}',
    ClubIdentity.fromJson,
  );

  // MARK: Match officials and the scoring lock

  static Future<List<MatchOfficialRow>> matchOfficials({required String matchId}) =>
      _net.requestList('GET', '/cricket/matches/$matchId/officials', MatchOfficialRow.fromJson);

  /// Appoint an umpire or a scorer. Either may control the scoring.
  static Future<List<MatchOfficialRow>> appointOfficial({
    required String matchId,
    required String userId,
    required String role,
  }) => _net.requestList(
    'POST',
    '/cricket/matches/$matchId/officials',
    MatchOfficialRow.fromJson,
    body: <String, dynamic>{'user_id': userId, 'role': role},
  );

  static Future<List<MatchOfficialRow>> removeOfficial({
    required String matchId,
    required String userId,
  }) => _net.requestList(
    'DELETE',
    '/cricket/matches/$matchId/officials/$userId',
    MatchOfficialRow.fromJson,
  );

  /// Pass the book on. Only the scorer holding it can.
  static Future<CricketMatchDto> handOverScoring({
    required String matchId,
    required String toUserId,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/handover',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{'to_user_id': toUserId},
  );

  static Future<List<ScorerHandover>> scorerTrail({required String matchId}) =>
      _net.requestList('GET', '/cricket/matches/$matchId/scorer-trail', ScorerHandover.fromJson);

  /// A line of colour for one ball, written by the model the API is pointed at.
  /// `line` is null when none is configured or it said something that did not
  /// match the ball — the line the app writes from the log then stands.
  static Future<BallCommentary> commentary({
    required String matchId,
    required int over,
    required int ballInOver,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/commentary',
    BallCommentary.fromJson,
    body: <String, dynamic>{'over': over, 'ball_in_over': ballInOver},
  );

  /// Who each captain has to pick from: the fixture's squad for the home side,
  /// the opposing club's members when they are a Fishers club.
  static Future<MatchSquads> squads({required String matchId}) =>
      _net.requestObject('GET', '/cricket/matches/$matchId/squad', MatchSquads.fromJson);

  /// The match as the server sees it — including which side this caller plays
  /// for and what they are allowed to act for.
  static Future<CricketMatchDto> match({required String matchId}) =>
      _net.requestObject('GET', '/cricket/matches/$matchId', CricketMatchDto.fromJson);

  /// A captain puts terms on the table, for their *own* side.
  ///
  /// The server refuses a proposal made on behalf of the opposition: that
  /// signed for a club which had not seen the terms and left them nothing to
  /// accept. The opposition is asked, and agrees separately.
  static Future<CricketMatchDto> proposeTerms({
    required String matchId,
    required MatchConditions conditions,
    required MatchSide side,
    required String captainName,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/propose',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{
      'conditions': conditions.toJson(),
      'by': side.wire,
      'by_name': captainName,
    },
  );

  /// Rain, bad light, ground unfit. The scorecard survives and the match goes
  /// down as no result — which is not the same as deleting it.
  static Future<CricketMatchDto> abandonMatch({required String matchId, required String reason}) =>
      _net.requestObject(
        'POST',
        '/cricket/matches/$matchId/abandon',
        CricketMatchDto.fromJson,
        body: <String, dynamic>{'reason': reason},
      );

  /// Only a match nobody has scored a ball in — that one was a mistake.
  static Future<void> deleteMatch({required String matchId}) =>
      _net.requestVoid('DELETE', '/cricket/matches/$matchId');

  /// A captain accepts the terms. A separate door from the scoring lock, so the
  /// visiting captain can agree from their own phone — they will never have
  /// scoring rights in the home club.
  static Future<void> agreeTerms({
    required String matchId,
    required MatchSide side,
    required String captainName,
  }) => _net.requestVoid(
    'POST',
    '/cricket/matches/$matchId/agree',
    body: <String, dynamic>{'side': side.wire, 'captain_name': captainName},
  );

  // MARK: Notifications

  /// One page of notifications, filtered server-side.
  ///
  /// The filtering and paging happen in the database: a club generates
  /// thousands of these over a season, and pulling the lot down to a phone to
  /// slice twenty out of them is exactly what a mobile connection is worst at.
  static Future<NotificationFeed> notifications({
    int page = 1,
    int perPage = 20,
    String? kind,
    bool unreadOnly = false,
    String? search,
  }) {
    final Map<String, String> query = <String, String>{'page': '$page', 'per_page': '$perPage'};
    if (kind != null && kind.isNotEmpty) query['kind'] = kind;
    if (unreadOnly) query['unread'] = 'true';
    // The server refuses one character; asking is a wasted round trip.
    final String trimmed = search?.trim() ?? '';
    if (trimmed.length >= 2) query['q'] = trimmed;
    return _net.requestObject(
      'GET',
      '/notifications${_queryString(query)}',
      NotificationFeed.fromJson,
    );
  }

  /// Another player, as their club-mates may see them. No contact details: the
  /// server does not send them, on purpose.
  static Future<TeammateProfile> teammate(String userId) =>
      _net.requestObject('GET', '/users/$userId', TeammateProfile.fromJson);

  static Future<List<PlayerSeasonStats>> playerSeasons(String userId) =>
      _net.requestList('GET', '/users/$userId/stats', PlayerSeasonStats.fromJson);

  static Future<List<UserAchievement>> playerAchievements(String userId) =>
      _net.requestList('GET', '/users/$userId/achievements', UserAchievement.fromJson);

  /// One notification, or every unread one when [id] is null.
  static Future<void> markNotificationRead({String? id}) =>
      _net.requestVoid('POST', '/notifications/read', body: <String, dynamic>{'id': id});

  /// Name one side. A separate door from the scoring log: a captain does this
  /// from their own phone without taking the book off whoever is scoring.
  static Future<CricketMatchDto> submitXi({
    required String matchId,
    required MatchSide side,
    required List<MatchPlayer> players,
    String? captainId,
    String? keeperId,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/xi',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{
      'side': side.wire,
      'players': players.map((MatchPlayer p) => p.toJson()).toList(growable: false),
      'captain_id': captainId,
      'keeper_id': keeperId,
    },
  );

  // MARK: Club administration

  /// The roster, with names and roles. Any member may read it; only a secretary
  /// may change it.
  static Future<List<ClubMemberDetail>> clubMembers({required String clubId}) =>
      _net.requestList('GET', '/clubs/$clubId/members', ClubMemberDetail.fromJson);

  /// Add someone already on Fishers to the club, by whatever they signed up
  /// with — an email address or a mobile number.
  static Future<void> addClubMember({
    required String clubId,
    required String identifier,
    required ClubRole role,
  }) => _net.requestVoid(
    'POST',
    '/clubs/$clubId/members',
    body: <String, dynamic>{'identifier': identifier, 'role': role.wire},
  );

  /// A link for somebody with no account yet: they follow it, sign up, and land
  /// in the club. Sending it is the secretary's job — the share sheet,
  /// WhatsApp, however they already talk to their players.
  static Future<ClubInvite> createClubInvite({required String clubId, String? email}) =>
      _net.requestObject(
        'POST',
        '/invites',
        ClubInvite.fromJson,
        body: <String, dynamic>{'target_type': 'club', 'target_id': clubId, 'invited_email': email},
      );

  static Future<ClubInvite> acceptInvite({required String token}) =>
      _net.requestObject('POST', '/invites/$token/accept', ClubInvite.fromJson);

  /// Appoint a captain or vice captain, or stand someone down. `captain` only
  /// means something for a secretary — one who captains the side too.
  static Future<void> setMemberRole({
    required String clubId,
    required String userId,
    required ClubRole role,
    bool captain = false,
  }) => _net.requestVoid(
    'PATCH',
    '/clubs/$clubId/members/$userId',
    body: <String, dynamic>{'role': role.wire, 'captain': captain},
  );

  // MARK: Clubs list, grounds, public page, teams

  /// Your clubs a page at a time, filtered and sorted by the server.
  static Future<ApiPage<ClubMembershipRow>> myClubs(
    ClubListFilters filters, {
    required int page,
    int perPage = 20,
  }) {
    final Map<String, String> query = <String, String>{
      for (final ({String name, String value}) item in filters.queryItems(
        page: page,
        perPage: perPage,
      ))
        item.name: item.value,
    };
    return _net.requestDecoded(
      'GET',
      '/me/clubs${_queryString(query)}',
      (Object? json) =>
          ApiPage<ClubMembershipRow>.fromJson(asMap(json), ClubMembershipRow.fromJson),
    );
  }

  static Future<List<Venue>> venues({required String clubId}) =>
      _net.requestList('GET', '/clubs/$clubId/venues', Venue.fromJson);

  static Future<Venue> createVenue({
    required String clubId,
    required String name,
    String? address,
  }) => _net.requestObject(
    'POST',
    '/clubs/$clubId/venues',
    Venue.fromJson,
    body: <String, dynamic>{'name': name, 'address': address},
  );

  static Future<ClubPageSettings> clubPage({required String clubId}) =>
      _net.requestObject('GET', '/clubs/$clubId/page', ClubPageSettings.fromJson);

  /// Only what changed is applied; null fields are left alone by the API.
  static Future<ClubPageSettings> updateClubPage({
    required String clubId,
    required ClubPageSettings page,
    bool? publish,
  }) => _net.requestObject(
    'PATCH',
    '/clubs/$clubId/page',
    ClubPageSettings.fromJson,
    body: <String, dynamic>{
      'slug': page.slug,
      'tagline': page.tagline,
      'about': page.about,
      'ground': page.ground,
      'contact_email': page.contactEmail,
      'founded_year': page.foundedYear,
      // A JSON null means "not touched", so clearing the icon needs a value
      // the API can tell apart.
      'icon_player_id': page.iconPlayerId ?? ClubPageSettings.noIconPlayer,
      'public_page': publish,
    },
  );

  static Future<List<TeamMemberRow>> teamMembers({required String teamId}) =>
      _net.requestList('GET', '/teams/$teamId/members', TeamMemberRow.fromJson);

  static Future<SharedPlayerCard> sharedPlayerCard({required String token}) =>
      _net.requestObject('GET', '/players/card/$token', SharedPlayerCard.fromJson);

  /// An invite addressed to an account — it arrives as a notification and the
  /// player still has to accept it.
  static Future<void> invite({
    required String userId,
    String? toClub,
    String? toTeam,
  }) => _net.requestVoid(
    'POST',
    '/invites',
    body: toTeam != null
        ? <String, dynamic>{'target_type': 'team', 'target_id': toTeam, 'invited_user_id': userId}
        : <String, dynamic>{'target_type': 'club', 'target_id': toClub, 'invited_user_id': userId},
  );

  static Future<void> removeClubMember({required String clubId, required String userId}) =>
      _net.requestVoid('DELETE', '/clubs/$clubId/members/$userId');

  static Future<ClubSettings> clubSettings({required String clubId}) =>
      _net.requestObject('GET', '/clubs/$clubId/settings', ClubSettings.fromJson);

  static Future<ClubSettings> updateClubSettings({
    required String clubId,
    required ClubSettings settings,
  }) => _net.requestObject(
    'PATCH',
    '/clubs/$clubId/settings',
    ClubSettings.fromJson,
    body: settings.toJson(),
  );

  // MARK: Clubs

  static Future<List<Club>> clubs() => _net.requestList('GET', '/clubs', Club.fromJson);

  static Future<Club> createClub({
    required String name,
    required List<String> sports,
    bool informal = false,
    String visibility = 'invite_only',
    String? description,
  }) => _net.requestObject(
    'POST',
    '/clubs',
    Club.fromJson,
    body: <String, dynamic>{
      'name': name,
      'sport_types': sports,
      'is_informal_group': informal,
      'visibility': visibility,
      'description': description,
    },
  );

  static Future<Team> createTeam({
    required String clubId,
    required String name,
    required String sport,
  }) => _net.requestObject(
    'POST',
    '/clubs/$clubId/teams',
    Team.fromJson,
    body: <String, dynamic>{'name': name, 'sport': sport},
  );

  static Future<List<Team>> teams({required String clubId}) =>
      _net.requestList('GET', '/clubs/$clubId/teams', Team.fromJson);

  /// `GET /events` pages now, so the array has to be unwrapped. The app asks
  /// for a big first page rather than paging: a season's fixtures on one screen
  /// is what a phone shows, and 200 is the server's ceiling anyway.
  static Future<List<Event>> events({
    String? clubId,
    bool cricketSeason = false,
    int page = 1,
    int perPage = 200,
  }) async => (await eventPage(
    clubId: clubId,
    cricketSeason: cricketSeason,
    page: page,
    perPage: perPage,
  )).items;

  static Future<ApiPage<Event>> eventPage({
    String? clubId,
    bool cricketSeason = false,
    int page = 1,
    int perPage = 200,
  }) {
    // The trailing `&` is what iOS sends; kept so the two are byte-identical.
    String path = '/events?page=$page&per_page=$perPage&';
    if (clubId != null) path += 'club_id=$clubId&';
    if (cricketSeason) path += 'cricket_season=true&';
    return _net.requestDecoded(
      'GET',
      path,
      (Object? json) => ApiPage<Event>.fromJson(asMap(json), Event.fromJson),
    );
  }

  static Future<Event> createEvent(CreateEventBody body) =>
      _net.requestObject('POST', '/events', Event.fromJson, body: body.toJson());

  static Future<Event> event({required String id}) =>
      _net.requestObject('GET', '/events/$id', Event.fromJson);

  // MARK: Fixtures

  static Future<List<MyFixture>> myFixtures({
    required DateTime from,
    required DateTime to,
  }) => _net.requestList(
    'GET',
    // A `+` in a timestamp would be read as a space; these are written with Z.
    '/events/mine${_queryString(<String, String>{'from': encodeDate(from), 'to': encodeDate(to)})}',
    MyFixture.fromJson,
  );

  /// A whole set of days at once — "every Saturday this month".
  ///
  /// Swift overloads `setAvailability`; Dart cannot, so this is the bulk one.
  static Future<List<Availability>> setAvailabilityForDates({
    required List<String> dates,
    required AvailabilityStatus status,
  }) => _net.requestList(
    'POST',
    '/availability/bulk',
    Availability.fromJson,
    body: <String, dynamic>{'dates': dates, 'status': status.wire},
  );

  /// Recorded at the door: `cash` or `transfer`.
  static Future<void> markTicketPaid(String ticketId, {required String method}) => _net.requestVoid(
    'POST',
    '/tickets/$ticketId/mark-paid',
    body: <String, dynamic>{'method': method},
  );

  static Future<void> withdrawEntrant(String entrantId) =>
      _net.requestVoid('POST', '/entrants/$entrantId/withdraw');

  /// Fill empty places from the reserve list, in the captain's order.
  static Future<void> promoteReserves({required String eventId}) =>
      _net.requestVoid('POST', '/events/$eventId/selection/promote');

  static Future<void> rsvp({required String eventId, required RsvpStatus status}) => _net
      .requestVoid('POST', '/events/$eventId/rsvp', body: <String, dynamic>{'status': status.wire});

  static Future<List<AttendeeSummary>> attendees({required String eventId}) =>
      _net.requestList('GET', '/events/$eventId/attendees', AttendeeSummary.fromJson);

  static Future<List<Availability>> availability({required String from, required String to}) =>
      _net.requestList('GET', '/availability?from=$from&to=$to', Availability.fromJson);

  static Future<Availability> setAvailability({
    required String date,
    required AvailabilityStatus status,
  }) => _net.requestObject(
    'POST',
    '/availability',
    Availability.fromJson,
    body: <String, dynamic>{'date': date, 'status': status.wire},
  );

  static Future<List<Product>> products({required String clubId}) =>
      _net.requestList('GET', '/clubs/$clubId/products', Product.fromJson);

  static Future<Order> placeOrder({
    required String clubId,
    String? eventId,
    required List<({String productId, int quantity})> items,
  }) {
    return _net.requestDecoded(
      'POST',
      '/orders',
      // The reply wraps the order in `{"order": …}`.
      (Object? json) => Order.fromJson(asMap(asMap(json)['order'], key: 'order')),
      body: <String, dynamic>{
        'club_id': clubId,
        'event_id': eventId,
        'items': <Map<String, dynamic>>[
          for (final ({String productId, int quantity}) item in items)
            <String, dynamic>{'product_id': item.productId, 'quantity': item.quantity},
        ],
      },
    );
  }

  static Future<PaymentIntentDto> paymentIntent({
    required String eventId,
    required int amountCents,
  }) => _net.requestObject(
    'POST',
    '/payments/intent',
    PaymentIntentDto.fromJson,
    body: <String, dynamic>{'event_id': eventId, 'amount_cents': amountCents, 'currency': 'GBP'},
  );

  // MARK: Cricket scoring

  /// [matchId] is chosen on the device, so a match started with no signal
  /// registers under the id its local event log already uses.
  static Future<CricketMatchDto> createCricketMatch({
    required String eventId,
    String? matchId,
    required int oversLimit,
    required String homeName,
    required String awayName,
    String? opponentClubId,
  }) => _net.requestObject(
    'POST',
    '/events/$eventId/cricket-match',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{
      'match_id': matchId,
      'overs_limit': oversLimit,
      'home_name': homeName,
      'away_name': awayName,
      'opponent_club_id': opponentClubId,
    },
  );

  static Future<CricketMatchDto> cricketMatchForEvent({required String eventId}) =>
      _net.requestObject('GET', '/events/$eventId/cricket-match', CricketMatchDto.fromJson);

  static Future<CricketMatchDto> cricketMatch({required String id}) =>
      _net.requestObject('GET', '/cricket/matches/$id', CricketMatchDto.fromJson);

  /// Fixtures with their match state already joined on — score, status and
  /// result in the row.
  ///
  /// One request answers "what is happening right now", which the alternative
  /// could not: asking `/events` and then `/events/{id}/cricket-match` for
  /// every cricket fixture is a request per fixture, on a phone, at a ground.
  /// `state` is `live`, `upcoming` or `finished`.
  static Future<ApiPage<CricketFixtureRow>> cricketFixtures({
    String? clubId,
    String? state,
    String? search,
    bool newestFirst = false,
    int page = 1,
    int perPage = 20,
  }) {
    final Map<String, String> query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'order': newestFirst ? 'desc' : 'asc',
    };
    if (clubId != null) query['club_id'] = clubId;
    if (state != null) query['state'] = state;
    // One letter matches most of the table; the API refuses it anyway.
    final String trimmed = search?.trim() ?? '';
    if (trimmed.length >= 2) query['q'] = trimmed;
    return _net.requestDecoded(
      'GET',
      '/cricket/fixtures${_queryString(query)}',
      (Object? json) =>
          ApiPage<CricketFixtureRow>.fromJson(asMap(json), CricketFixtureRow.fromJson),
    );
  }

  /// `force` takes the match off a scorer whose phone has died mid-innings.
  static Future<CricketMatchDto> claimScorer({
    required String matchId,
    required String deviceId,
    bool force = false,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/claim-scorer',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{'device_id': deviceId, 'force': force},
  );

  static Future<CricketMatchDto> postCricketEvents({
    required String matchId,
    required String deviceId,
    required List<ScoringEvent> events,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/events',
    CricketMatchDto.fromJson,
    body: <String, dynamic>{
      'device_id': deviceId,
      'events': events.map((ScoringEvent e) => e.toJson()).toList(growable: false),
    },
  );

  static Future<MatchState> cricketScorecard({required String matchId}) =>
      _net.requestObject('GET', '/cricket/matches/$matchId/scorecard', MatchState.fromJson);

  /// Mint a secure live scoreboard link. Pass `postToChat: true` to also drop
  /// it into club chat; external WhatsApp/Mail shares usually leave it false.
  static Future<ScoreboardShareResponse> shareScoreboard({
    required String matchId,
    bool postToChat = false,
  }) => _net.requestObject(
    'POST',
    '/cricket/matches/$matchId/share',
    ScoreboardShareResponse.fromJson,
    body: <String, dynamic>{'post_to_chat': postToChat, 'ttl_hours': 48},
  );

  // MARK: Profile picture

  /// The server sniffs the real bytes and rejects anything that is not a JPEG,
  /// PNG or WebP, so the mime type sent here is a hint, not a claim it will be
  /// believed on.
  static Future<PublicUser> uploadAvatar(Uint8List data, {String mimeType = 'image/jpeg'}) =>
      _net.upload(
        path: '/me/avatar',
        fileName: 'avatar.${mimeType.endsWith("png") ? "png" : "jpg"}',
        mimeType: mimeType,
        data: data,
        decode: PublicUser.fromJson,
      );

  // MARK: Season stats (Play-Cricket)

  static Future<MeStatsResponse> mySeasonStats({int? season}) => _net.requestObject(
    'GET',
    season == null ? '/me/stats' : '/me/stats?season=$season',
    MeStatsResponse.fromJson,
  );

  static Future<ClubSeasonBoard> clubSeasonBoard({required String clubId, int season = 2026}) =>
      _net.requestObject('GET', '/clubs/$clubId/stats?season=$season', ClubSeasonBoard.fromJson);

  static Future<void> syncClubStats({required String clubId}) =>
      _net.requestVoid('POST', '/clubs/$clubId/stats/sync');

  /// `?a=1&b=2`, percent-encoded, or an empty string when there is nothing to
  /// ask for.
  static String _queryString(Map<String, String> query) {
    if (query.isEmpty) return '';
    final String encoded = query.entries
        .map(
          (MapEntry<String, String> e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '?$encoded';
  }
}

/// The body of `POST /events`.
class CreateEventBody {
  const CreateEventBody({
    required this.clubId,
    required this.sport,
    required this.eventSubtype,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.opponentClubId,
    this.teamId,
    this.venueId,
    this.recurrenceRule,
    this.capacity,
    this.feeAmountCents,
    this.metadata,
  });

  final String clubId;

  /// The other side, when they are a club on Fishers — their players are asked
  /// whether they can play too.
  final String? opponentClubId;
  final String? teamId;
  final String sport;
  final String eventSubtype;
  final String title;
  final String? venueId;
  final DateTime startAt;
  final DateTime endAt;
  final String? recurrenceRule;
  final int? capacity;
  final int? feeAmountCents;
  final Map<String, JsonValue>? metadata;

  JsonMap toJson() => <String, dynamic>{
    'club_id': clubId,
    'opponent_club_id': opponentClubId,
    'team_id': teamId,
    'sport': sport,
    'event_subtype': eventSubtype,
    'title': title,
    'venue_id': venueId,
    'start_at': encodeDate(startAt),
    'end_at': encodeDate(endAt),
    'recurrence_rule': recurrenceRule,
    'capacity': capacity,
    'fee_amount_cents': feeAmountCents,
    'metadata': JsonValue.mapToJson(metadata),
  };
}

/// `POST /payments/intent`.
class PaymentIntentDto {
  const PaymentIntentDto({
    required this.paymentId,
    required this.clientSecret,
    required this.amountCents,
    required this.currency,
    required this.status,
  });

  final String paymentId;
  final String clientSecret;
  final int amountCents;
  final String currency;
  final String status;

  factory PaymentIntentDto.fromJson(JsonMap json) => PaymentIntentDto(
    paymentId: asUuid(json['payment_id'], key: 'payment_id'),
    clientSecret: asString(json['client_secret'], key: 'client_secret'),
    amountCents: asInt(json['amount_cents'], key: 'amount_cents'),
    currency: asString(json['currency'], key: 'currency'),
    status: asString(json['status'], key: 'status'),
  );

  JsonMap toJson() => <String, dynamic>{
    'payment_id': paymentId,
    'client_secret': clientSecret,
    'amount_cents': amountCents,
    'currency': currency,
    'status': status,
  };

  @override
  bool operator ==(Object other) =>
      other is PaymentIntentDto &&
      other.paymentId == paymentId &&
      other.clientSecret == clientSecret &&
      other.amountCents == amountCents &&
      other.currency == currency &&
      other.status == status;

  @override
  int get hashCode => Object.hash(paymentId, clientSecret, amountCents, currency, status);
}
