import 'package:fishers/models/fishers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Every model, against real JSON captured from a running Fishers API.
///
/// The check is decode → encode → decode, plus an assertion that no wire key
/// the server sent is silently dropped. Keys listed under `ignoredWireKeys` are
/// ones the iOS `Codable` does not model either — `CodingKeys` omits them — and
/// each one carries the reason.
void main() {
  test('the fixtures are real captures, and say where from', () {
    final Map<String, String> manifest = loadManifest();
    expect(manifest, isNotEmpty);
    // Every entry names an HTTP method and path, not a hand-written shape.
    for (final MapEntry<String, String> e in manifest.entries) {
      expect(
        e.value,
        matches(RegExp(r'^(GET|POST|PATCH|DELETE) /')),
        reason: '${e.key} does not record which endpoint it came from',
      );
    }
  });

  group('Models.swift', () {
    test('PublicUser', () {
      expectRoundTrip<PublicUser>(
        'public_user',
        PublicUser.fromJson,
        (PublicUser u) => u.toJson(),
        // The API computes this for its own screens; iOS's `PublicUser` has no
        // key for it either and reads `ProfileStrength` from the user instead.
        ignoredWireKeys: <String>{'profile_strength'},
      );
    });

    test('PublicUser, with the profile filled in', () {
      expectRoundTrip<PublicUser>(
        'public_user_full',
        PublicUser.fromJson,
        (PublicUser u) => u.toJson(),
        ignoredWireKeys: <String>{'profile_strength'},
      );
      final PublicUser user = PublicUser.fromJson(loadFixture('public_user_full'));
      expect(user.profiles, hasLength(2));
      expect(user.primaryProfile?.sport, 'cricket');
      expect(user.primaryProfile?.tier, SkillTier.club);
      expect(user.location?.transport, TransportMode.driverWithSeats);
      expect(user.location?.weekdays, <Weekday>[Weekday.sunday, Weekday.saturday]);
      expect(user.playedSports, <Sport>[Sport.cricket, Sport.football]);
      expect(user.initials, 'DF');
    });

    test('AuthTokens', () {
      expectRoundTrip<AuthTokens>('auth_tokens', AuthTokens.fromJson, (AuthTokens t) => t.toJson());
      final AuthTokens tokens = AuthTokens.fromJson(loadFixture('auth_tokens'));
      expect(tokens.tokenType, 'Bearer');
      expect(tokens.expiresIn, greaterThan(0));
    });

    test('Club', () {
      expectRoundTrip<Club>(
        'club',
        Club.fromJson,
        (Club c) => c.toJson(),
        // Row bookkeeping and the membership numbers, which belong to
        // `ClubMembershipRow` (`GET /me/clubs`) and are not on `Club` on iOS.
        ignoredWireKeys: <String>{
          'created_at',
          'updated_at',
          'is_captain',
          'member_count',
          'team_count',
          'public_slug',
        },
      );
    });

    test('Team', () {
      expectRoundTrip<Team>(
        'team',
        Team.fromJson,
        (Team t) => t.toJson(),
        ignoredWireKeys: <String>{'created_at'},
      );
    });

    test('Venue', () {
      expectRoundTrip<Venue>(
        'venue',
        Venue.fromJson,
        (Venue v) => v.toJson(),
        ignoredWireKeys: <String>{'created_at'},
      );
    });

    test('Event', () {
      expectRoundTrip<Event>(
        'event',
        Event.fromJson,
        (Event e) => e.toJson(),
        // Server-side bookkeeping; `Event`'s CodingKeys omit them on iOS too.
        // Server bookkeeping, plus the ticket and call-off fields that live on
        // `TicketSummary` and the fixture-status endpoint rather than on
        // `Event` — the same split `Event`'s CodingKeys make on iOS.
        ignoredWireKeys: <String>{
          'created_at',
          'updated_at',
          'created_by',
          'recurrence_rule',
          'recurrence_parent_id',
          'ticket_capacity',
          'guests_allowed',
          'status_note',
          'rescheduled_to',
        },
      );
    });

    test('Availability', () {
      expectRoundTrip<Availability>(
        'availability',
        Availability.fromJson,
        (Availability a) => a.toJson(),
        ignoredWireKeys: <String>{'recurrence_rule', 'created_at', 'updated_at'},
      );
    });

    test('AttendeeSummary', () {
      expectRoundTrip<AttendeeSummary>(
        'attendee_summary',
        AttendeeSummary.fromJson,
        (AttendeeSummary a) => a.toJson(),
      );
    });

    test('Product', () {
      expectRoundTrip<Product>(
        'product',
        Product.fromJson,
        (Product p) => p.toJson(),
        // Stock control is a dashboard job; the phone only ever lists and buys.
        ignoredWireKeys: <String>{'stock', 'active', 'created_at'},
      );
      expect(Product.fromJson(loadFixture('product')).priceLabel, startsWith('£'));
    });

    test('Order', () {
      expectRoundTrip<Order>(
        'order',
        Order.fromJson,
        (Order o) => o.toJson(),
        ignoredWireKeys: <String>{'created_at', 'updated_at', 'items', 'note'},
      );
    });
  });

  group('RBAC.swift', () {
    test('ClubRoleInfo', () {
      expectRoundTrip<ClubRoleInfo>(
        'club_role_info',
        ClubRoleInfo.fromJson,
        (ClubRoleInfo r) => r.toJson(),
      );
    });

    test('every ClubRole raw value is the backend spelling', () {
      expect(ClubRole.values.map((ClubRole r) => r.wire), <String>[
        'super_admin',
        'club_admin',
        'team_captain',
        'team_vice_captain',
        'member',
        'guest',
      ]);
    });
  });

  group('Clubs.swift', () {
    test('ClubMembershipRow', () {
      expectRoundTrip<ClubMembershipRow>(
        'club_membership_row',
        ClubMembershipRow.fromJson,
        (ClubMembershipRow r) => r.toJson(),
        ignoredWireKeys: <String>{'created_at', 'updated_at'},
      );
    });

    test('ClubPageSettings', () {
      expectRoundTrip<ClubPageSettings>(
        'club_page_settings',
        ClubPageSettings.fromJson,
        (ClubPageSettings p) => p.toJson(),
        // The page editor never changes which sports a club plays.
        ignoredWireKeys: <String>{'sport_types'},
      );
    });

    test('TeamMemberRow', () {
      expectRoundTrip<TeamMemberRow>(
        'team_member_row',
        TeamMemberRow.fromJson,
        (TeamMemberRow r) => r.toJson(),
        ignoredWireKeys: <String>{'joined_at'},
      );
    });

    test('SharedPlayerCard', () {
      expectRoundTrip<SharedPlayerCard>(
        'shared_player_card',
        SharedPlayerCard.fromJson,
        (SharedPlayerCard c) => c.toJson(),
      );
    });
  });

  group('ClubAdmin.swift', () {
    test('ClubMemberDetail', () {
      expectRoundTrip<ClubMemberDetail>(
        'club_member_detail',
        ClubMemberDetail.fromJson,
        (ClubMemberDetail m) => m.toJson(),
      );
    });

    test('ClubInvite', () {
      expectRoundTrip<ClubInvite>(
        'club_invite',
        ClubInvite.fromJson,
        (ClubInvite i) => i.toJson(),
        ignoredWireKeys: <String>{
          'created_at',
          'expires_at',
          'invited_user_id',
          'accepted_at',
          'invited_by',
        },
      );
    });

    test('ClubSettings', () {
      expectRoundTrip<ClubSettings>(
        'club_settings',
        ClubSettings.fromJson,
        (ClubSettings s) => s.toJson(),
      );
    });

    test('AppNotification', () {
      expectRoundTrip<AppNotification>(
        'app_notification',
        AppNotification.fromJson,
        (AppNotification n) => n.toJson(),
        // Always the reader's own id — `GET /notifications` is scoped to them.
        ignoredWireKeys: <String>{'user_id'},
      );
      final AppNotification notification = AppNotification.fromJson(
        loadFixture('app_notification'),
      );
      expect(notification.line, isNotEmpty);
      expect(
        notification.line,
        isNot(contains('_')),
        reason: 'a player should never read a wire type name',
      );
    });

    test('NotificationFeed', () {
      expectRoundTrip<NotificationFeed>(
        'notification_feed',
        NotificationFeed.fromJson,
        (NotificationFeed f) => f.toJson(),
      );
      expect(NotificationFeed.fromJson(loadFixture('notification_feed')).items, isNotEmpty);
    });

    test('ApiPage', () {
      final ApiPage<ClubMembershipRow> page = ApiPage<ClubMembershipRow>.fromJson(
        loadFixture('club_membership_page'),
        ClubMembershipRow.fromJson,
      );
      expect(page.items, isNotEmpty);
      expect(page.page, 1);
      final ApiPage<ClubMembershipRow> again = ApiPage<ClubMembershipRow>.fromJson(
        page.toJson((ClubMembershipRow r) => r.toJson()),
        ClubMembershipRow.fromJson,
      );
      expect(again, page);
    });
  });

  group('Onboarding.swift', () {
    test('VerificationStatus', () {
      expectRoundTrip<VerificationStatus>(
        'verification_status',
        VerificationStatus.fromJson,
        (VerificationStatus v) => v.toJson(),
      );
      final VerificationStatus status = VerificationStatus.fromJson(
        loadFixture('verification_status'),
      );
      expect(status.channels, contains(VerificationChannel.email));
      expect(status[VerificationChannel.email].verified, isTrue);
    });

    test('PendingInvite', () {
      expectRoundTrip<PendingInvite>(
        'pending_invite',
        PendingInvite.fromJson,
        (PendingInvite i) => i.toJson(),
        // `invited_by_name` is the one the screen shows; the raw id and the
        // acceptance stamp are not on iOS's `PendingInvite` either.
        ignoredWireKeys: <String>{
          'invited_email',
          'invited_user_id',
          'expires_at',
          'invited_by',
          'accepted_at',
        },
      );
    });

    test('ShareLinkToken', () {
      expectRoundTrip<ShareLinkToken>(
        'share_link_token',
        ShareLinkToken.fromJson,
        (ShareLinkToken t) => t.toJson(),
        ignoredWireKeys: <String>{'url'},
      );
    });
  });

  group('Fixtures.swift', () {
    test('MyFixture', () {
      expectRoundTrip<MyFixture>('my_fixture', MyFixture.fromJson, (MyFixture f) => f.toJson());
    });
  });

  group('Chat.swift', () {
    test('ConversationSummary', () {
      expectRoundTrip<ConversationSummary>(
        'conversation_summary',
        ConversationSummary.fromJson,
        (ConversationSummary c) => c.toJson(),
      );
    });

    test('Conversation', () {
      expectRoundTrip<Conversation>(
        'conversation',
        Conversation.fromJson,
        (Conversation c) => c.toJson(),
      );
    });

    test('ChatMessage', () {
      expectRoundTrip<ChatMessage>(
        'chat_message',
        ChatMessage.fromJson,
        (ChatMessage m) => m.toJson(),
        // Neither client shows an edit marker yet; iOS's CodingKeys skip it too.
        ignoredWireKeys: <String>{'edited_at'},
      );
    });
  });

  group('Selection.swift', () {
    test('SelectionBoard', () {
      expectRoundTrip<SelectionBoard>(
        'selection_board',
        SelectionBoard.fromJson,
        (SelectionBoard b) => b.toJson(),
      );
      final SelectionBoard board = SelectionBoard.fromJson(loadFixture('selection_board'));
      expect(board.candidates, isNotEmpty);
      expect(board.requirements.positionQuotas, isNotEmpty);
      // The pool is ranked order, restricted to the undecided.
      expect(
        board.pool.map((SelectionCandidate c) => c.state).toSet(),
        anyOf(isEmpty, <SelectionState>{SelectionState.pool}),
      );
    });

    test('SquadProposal', () {
      expectRoundTrip<SquadProposal>(
        'squad_proposal',
        SquadProposal.fromJson,
        (SquadProposal p) => p.toJson(),
      );
    });

    test('OutstandingFees', () {
      expectRoundTrip<OutstandingFees>(
        'outstanding_fees',
        OutstandingFees.fromJson,
        (OutstandingFees f) => f.toJson(),
      );
    });
  });

  group('Tournament.swift', () {
    test('FixtureBlock', () {
      expectRoundTrip<FixtureBlock>(
        'fixture_block',
        FixtureBlock.fromJson,
        (FixtureBlock b) => b.toJson(),
        ignoredWireKeys: <String>{'created_at'},
      );
    });

    test('TournamentEntrant', () {
      expectRoundTrip<TournamentEntrant>(
        'tournament_entrant',
        TournamentEntrant.fromJson,
        (TournamentEntrant e) => e.toJson(),
        // An entrant may be a Fishers club, but the tournament screens work off
        // the name; iOS's CodingKeys leave both ids out too.
        ignoredWireKeys: <String>{'club_id', 'team_id'},
      );
    });

    test('ScheduleRow', () {
      expectRoundTrip<ScheduleRow>(
        'schedule_row',
        ScheduleRow.fromJson,
        (ScheduleRow r) => r.toJson(),
      );
    });

    test('Standing', () {
      expectRoundTrip<Standing>('standing', Standing.fromJson, (Standing s) => s.toJson());
    });

    test('EventTicket', () {
      expectRoundTrip<EventTicket>(
        'event_ticket',
        EventTicket.fromJson,
        (EventTicket t) => t.toJson(),
        ignoredWireKeys: <String>{'created_at', 'paid_at', 'payment_method'},
      );
    });

    test('TicketBooking', () {
      expectRoundTrip<TicketBooking>(
        'ticket_booking',
        TicketBooking.fromJson,
        (TicketBooking b) => b.toJson(),
      );
    });

    test('CricketFixtureRow', () {
      expectRoundTrip<CricketFixtureRow>(
        'cricket_fixture_row',
        CricketFixtureRow.fromJson,
        (CricketFixtureRow r) => r.toJson(),
      );
    });
  });

  group('ClubIdentity.swift', () {
    test('ClubIdentity', () {
      expectRoundTrip<ClubIdentity>(
        'club_identity',
        ClubIdentity.fromJson,
        (ClubIdentity i) => i.toJson(),
      );
    });

    test('ClubQrCode decodes the identity from the same object', () {
      expectRoundTrip<ClubQrCode>(
        'club_qr_code',
        ClubQrCode.fromJson,
        (ClubQrCode q) => q.toJson(),
        // The server offers a pre-rendered SVG; both clients draw the code
        // themselves from `payload`, so neither reads it.
        ignoredWireKeys: <String>{'svg'},
      );
      final ClubQrCode code = ClubQrCode.fromJson(loadFixture('club_qr_code'));
      expect(code.identity.qrToken, isNotEmpty);
      expect(code.payload, isNotEmpty);
    });

    test('MatchOfficialRow', () {
      expectRoundTrip<MatchOfficialRow>(
        'match_official_row',
        MatchOfficialRow.fromJson,
        (MatchOfficialRow r) => r.toJson(),
      );
    });

    test('ScorerHandover', () {
      expectRoundTrip<ScorerHandover>(
        'scorer_handover',
        ScorerHandover.fromJson,
        (ScorerHandover h) => h.toJson(),
      );
      expect(ScorerHandover.fromJson(loadFixture('scorer_handover')).summary, isNotEmpty);
    });

    test('BallCommentary', () {
      expectRoundTrip<BallCommentary>(
        'ball_commentary',
        BallCommentary.fromJson,
        (BallCommentary c) => c.toJson(),
      );
    });

    test('MatchSquads', () {
      expectRoundTrip<MatchSquads>(
        'match_squads',
        MatchSquads.fromJson,
        (MatchSquads s) => s.toJson(),
      );
      final MatchSquads squads = MatchSquads.fromJson(loadFixture('match_squads'));
      expect(squads.home.players, isNotEmpty);
      expect(squads.home.side, 'home');
      expect(squads.away.side, 'away');
    });
  });

  group('TeammateProfile.swift', () {
    test('TeammateProfile carries no contact details', () {
      expectRoundTrip<TeammateProfile>(
        'teammate_profile',
        TeammateProfile.fromJson,
        (TeammateProfile p) => p.toJson(),
      );
      final JsonMap raw = loadFixture('teammate_profile');
      for (final String forbidden in <String>['email', 'phone', 'emergency_contact', 'location']) {
        expect(
          raw.containsKey(forbidden),
          isFalse,
          reason: 'the server is sending $forbidden to a club-mate',
        );
      }
    });
  });

  group('SeasonStats.swift', () {
    test('MeStatsResponse', () {
      expectRoundTrip<MeStatsResponse>(
        'me_stats',
        MeStatsResponse.fromJson,
        (MeStatsResponse r) => r.toJson(),
      );
    });

    test('PlayerSeasonStats', () {
      expectRoundTrip<PlayerSeasonStats>(
        'player_season_stats',
        PlayerSeasonStats.fromJson,
        (PlayerSeasonStats s) => s.toJson(),
        ignoredWireKeys: <String>{'extras', 'updated_at'},
      );
    });

    test('ClubSeasonStats', () {
      expectRoundTrip<ClubSeasonStats>(
        'club_season_stats',
        ClubSeasonStats.fromJson,
        (ClubSeasonStats s) => s.toJson(),
        ignoredWireKeys: <String>{'extras', 'updated_at', 'team_id', 'sport'},
      );
    });

    test('ClubSeasonBoard', () {
      expectRoundTrip<ClubSeasonBoard>(
        'club_season_board',
        ClubSeasonBoard.fromJson,
        (ClubSeasonBoard b) => b.toJson(),
      );
    });

    test('a Play-Cricket deep link resolves to the real homepage', () {
      expect(
        PlayCricketLinks.resolve('https://hemel.play-cricket.com/website/nonsense'),
        PlayCricketLinks.home,
      );
      expect(PlayCricketLinks.resolve(null), isNull);
      expect(PlayCricketLinks.resolve('  '), isNull);
      expect(PlayCricketLinks.resolve('https://example.com/x')?.host, 'example.com');
    });
  });

  group('CricketTypes.swift', () {
    test('CricketMatchDto', () {
      expectRoundTrip<CricketMatchDto>(
        'cricket_match_dto',
        CricketMatchDto.fromJson,
        (CricketMatchDto d) => d.toJson(),
      );
    });

    test('MatchState', () {
      expectRoundTrip<MatchState>(
        'match_state',
        MatchState.fromJson,
        (MatchState s) => s.toJson(),
        // Declared outside `CodingKeys` on iOS, so Swift's encoder never writes
        // it either; it is read here and deliberately not written back.
        ignoredWireKeys: <String>{'abandoned'},
      );
    });

    test('MatchState from the scorecard endpoint', () {
      expectRoundTrip<MatchState>(
        'cricket_scorecard',
        MatchState.fromJson,
        (MatchState s) => s.toJson(),
        // `GET /scorecard` answers a MatchState plus a `dls` block. iOS decodes
        // the reply as `MatchState`, which has no key for it, so the DLS par
        // reaches both apps through `CricketMatchDTO.dls` instead.
        ignoredWireKeys: <String>{'abandoned', 'dls'},
      );
      final MatchState state = MatchState.fromJson(loadFixture('cricket_scorecard'));
      expect(state.innings, isNotEmpty);
      expect(state.scoreLine(), isNotEmpty);
      expect(state.currentInnings!.oversDisplay, matches(RegExp(r'^\d+\.\d$')));
    });

    test('InningsState', () {
      expectRoundTrip<InningsState>(
        'innings_state',
        InningsState.fromJson,
        (InningsState i) => i.toJson(),
      );
    });

    test('ScoreboardShareResponse', () {
      expectRoundTrip<ScoreboardShareResponse>(
        'scoreboard_share',
        ScoreboardShareResponse.fromJson,
        (ScoreboardShareResponse r) => r.toJson(),
      );
    });
  });
}
