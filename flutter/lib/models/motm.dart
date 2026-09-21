import 'package:flutter/foundation.dart';

import 'json.dart';

/// A port of `ios/Fishers/Models/ManOfTheMatch.swift`.

/// The club's man-of-the-match vote.
///
/// Distinct from the scorer's award, which one person gives from the scoring
/// screen. This one opens on its own when the game ends and everybody in
/// either club votes in it — including the people who watched rather than
/// played, which on most Saturdays is most of the club.
@immutable
class MotmPoll {
  const MotmPoll({
    required this.id,
    required this.clubId,
    required this.eventId,
    required this.title,
    required this.status,
    required this.closesAt,
    required this.createdAt,
    this.matchId,
    this.conversationId,
    this.messageId,
    this.result,
    this.winnerUserId,
    this.closedAt,
  });

  final String id;
  final String clubId;
  final String eventId;
  final String? matchId;
  final String? conversationId;
  final String? messageId;
  final String title;

  /// The match result as it stood when the card went up. A later completion —
  /// a super over settling a tie — moves it, and the thread is told.
  final String? result;

  /// `open` | `closed`
  final String status;
  final DateTime closesAt;
  final String? winnerUserId;
  final DateTime createdAt;
  final DateTime? closedAt;

  /// The server decides whether a vote counts; this is only for the label.
  ///
  /// A poll past its closing time is over whether or not anything has run the
  /// close yet — the sweeper runs quarterly-hourly, so there is always a
  /// window where the status column and the clock disagree.
  bool get isOpen => status == 'open' && closesAt.isAfter(DateTime.now());

  factory MotmPoll.fromJson(JsonMap json) => MotmPoll(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuid(json['club_id'], key: 'club_id'),
    eventId: asUuid(json['event_id'], key: 'event_id'),
    matchId: asUuidOrNull(json['match_id'], key: 'match_id'),
    conversationId: asUuidOrNull(json['conversation_id'], key: 'conversation_id'),
    messageId: asUuidOrNull(json['message_id'], key: 'message_id'),
    title: asString(json['title'], key: 'title'),
    result: asStringOrNull(json['result'], key: 'result'),
    status: asString(json['status'], key: 'status'),
    closesAt: asDate(json['closes_at'], key: 'closes_at'),
    winnerUserId: asUuidOrNull(json['winner_user_id'], key: 'winner_user_id'),
    createdAt: asDate(json['created_at'], key: 'created_at'),
    closedAt: asDateOrNull(json['closed_at'], key: 'closed_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'event_id': eventId,
    'match_id': matchId,
    'conversation_id': conversationId,
    'message_id': messageId,
    'title': title,
    'result': result,
    'status': status,
    'closes_at': encodeDate(closesAt),
    'winner_user_id': winnerUserId,
    'created_at': encodeDate(createdAt),
    'closed_at': encodeDateOrNull(closedAt),
  };

  @override
  bool operator ==(Object other) =>
      other is MotmPoll &&
      other.id == id &&
      other.clubId == clubId &&
      other.eventId == eventId &&
      other.matchId == matchId &&
      other.conversationId == conversationId &&
      other.messageId == messageId &&
      other.title == title &&
      other.result == result &&
      other.status == status &&
      other.closesAt == closesAt &&
      other.winnerUserId == winnerUserId &&
      other.createdAt == createdAt &&
      other.closedAt == closedAt;

  @override
  int get hashCode => Object.hash(
    id,
    clubId,
    eventId,
    matchId,
    conversationId,
    messageId,
    title,
    result,
    status,
    closesAt,
    winnerUserId,
    createdAt,
    closedAt,
  );
}

/// Somebody who can be voted for: everyone named on either team sheet.
@immutable
class MotmCandidate {
  const MotmCandidate({
    required this.userId,
    required this.displayName,
    required this.side,
    required this.votes,
  });

  final String userId;
  final String displayName;

  /// `home` | `away`
  final String side;

  /// Zero for everybody until the tally is visible.
  final int votes;

  factory MotmCandidate.fromJson(JsonMap json) => MotmCandidate(
    userId: asUuid(json['user_id'], key: 'user_id'),
    displayName: asString(json['display_name'], key: 'display_name'),
    side: asString(json['side'], key: 'side'),
    votes: asInt(json['votes'], key: 'votes'),
  );

  JsonMap toJson() => <String, dynamic>{
    'user_id': userId,
    'display_name': displayName,
    'side': side,
    'votes': votes,
  };

  @override
  bool operator ==(Object other) =>
      other is MotmCandidate &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.side == side &&
      other.votes == votes;

  @override
  int get hashCode => Object.hash(userId, displayName, side, votes);
}

/// A poll as this person sees it — the ballot, their vote, and whether they
/// are allowed to see the running total yet.
///
/// The API flattens the poll's own fields in beside the ballot
/// (`#[serde(flatten)]`), so this reads both out of the same object rather
/// than from a nested key. Swift does the same in its `init(from:)`.
@immutable
class MotmPollView {
  const MotmPollView({
    required this.poll,
    required this.candidates,
    required this.totalVotes,
    required this.tallyVisible,
    required this.canVote,
    this.myVote,
    this.scorerAwardUserId,
  });

  final MotmPoll poll;
  final List<MotmCandidate> candidates;
  final String? myVote;
  final int totalVotes;

  /// False until you have voted, so a running tally cannot nudge you towards
  /// whoever is already ahead.
  final bool tallyVisible;
  final bool canVote;

  /// What the scorer gave, when they gave one. Shown beside the vote so the
  /// two are never mistaken for each other.
  final String? scorerAwardUserId;

  factory MotmPollView.fromJson(JsonMap json) => MotmPollView(
    poll: MotmPoll.fromJson(json),
    candidates: <MotmCandidate>[
      for (final dynamic row in (json['candidates'] as List<dynamic>? ?? const <dynamic>[]))
        MotmCandidate.fromJson(asMap(row, key: 'candidates')),
    ],
    myVote: asUuidOrNull(json['my_vote'], key: 'my_vote'),
    totalVotes: asInt(json['total_votes'], key: 'total_votes'),
    tallyVisible: asBool(json['tally_visible'], key: 'tally_visible'),
    canVote: asBool(json['can_vote'], key: 'can_vote'),
    scorerAwardUserId: asUuidOrNull(json['scorer_award_user_id'], key: 'scorer_award_user_id'),
  );

  JsonMap toJson() => <String, dynamic>{
    ...poll.toJson(),
    'candidates': <JsonMap>[for (final MotmCandidate c in candidates) c.toJson()],
    'my_vote': myVote,
    'total_votes': totalVotes,
    'tally_visible': tallyVisible,
    'can_vote': canVote,
    'scorer_award_user_id': scorerAwardUserId,
  };

  MotmCandidate? get winner {
    final String? id = poll.winnerUserId;
    if (id == null) return null;
    for (final MotmCandidate c in candidates) {
      if (c.userId == id) return c;
    }
    return null;
  }

  /// Everybody level at the top of a closed vote with no winner — which is how
  /// a tie is recorded, because a captain picks between them.
  List<MotmCandidate> get tiedAtTheTop {
    if (poll.isOpen || poll.winnerUserId != null || !tallyVisible) {
      return const <MotmCandidate>[];
    }
    int best = 0;
    for (final MotmCandidate c in candidates) {
      if (c.votes > best) best = c.votes;
    }
    if (best == 0) return const <MotmCandidate>[];
    return <MotmCandidate>[
      for (final MotmCandidate c in candidates)
        if (c.votes == best) c,
    ];
  }

  /// The ballot split into the two team sheets, each in the order the API sent
  /// them — which holds still while the vote is open, and becomes a
  /// leaderboard once it closes.
  List<MotmCandidate> sheet(String side) => <MotmCandidate>[
    for (final MotmCandidate c in candidates)
      if (c.side == side) c,
  ];

  /// "Hemel Hempstead" and "Chesham" out of "Hemel Hempstead vs Chesham",
  /// falling back to Home and Away for a fixture titled some other way.
  ({String home, String away}) get sideNames {
    for (final String separator in const <String>[' vs ', ' v ', ' V ']) {
      final List<String> parts = poll.title.split(separator);
      if (parts.length == 2) {
        return (home: parts[0], away: parts[1]);
      }
    }
    return (home: 'Home', away: 'Away');
  }

  @override
  bool operator ==(Object other) =>
      other is MotmPollView &&
      other.poll == poll &&
      listEquals(other.candidates, candidates) &&
      other.myVote == myVote &&
      other.totalVotes == totalVotes &&
      other.tallyVisible == tallyVisible &&
      other.canVote == canVote &&
      other.scorerAwardUserId == scorerAwardUserId;

  @override
  int get hashCode => Object.hash(
    poll,
    Object.hashAll(candidates),
    myVote,
    totalVotes,
    tallyVisible,
    canVote,
    scorerAwardUserId,
  );
}
