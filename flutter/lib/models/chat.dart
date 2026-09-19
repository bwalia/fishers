import 'package:flutter/foundation.dart';

import 'json.dart';
import 'models.dart';

/// A port of `ios/Fishers/Models/Chat.swift`.

/// A chat thread. Threads hang off a club, a team or a single fixture.
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.updatedAt,
    required this.unreadCount,
    required this.pendingProposals,
    this.clubId,
    this.teamId,
    this.eventId,
    this.lastMessageBody,
    this.lastMessageAt,
  });

  final String id;
  final String? clubId;
  final String? teamId;
  final String? eventId;
  final String kind;
  final String title;
  final DateTime updatedAt;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Agent proposals waiting on a captain's decision.
  final int pendingProposals;

  factory ConversationSummary.fromJson(JsonMap json) => ConversationSummary(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    eventId: asUuidOrNull(json['event_id'], key: 'event_id'),
    kind: asString(json['kind'], key: 'kind'),
    title: asString(json['title'], key: 'title'),
    updatedAt: asDate(json['updated_at'], key: 'updated_at'),
    lastMessageBody: asStringOrNull(json['last_message_body'], key: 'last_message_body'),
    lastMessageAt: asDateOrNull(json['last_message_at'], key: 'last_message_at'),
    unreadCount: asInt(json['unread_count'], key: 'unread_count'),
    pendingProposals: asInt(json['pending_proposals'], key: 'pending_proposals'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'team_id': teamId,
    'event_id': eventId,
    'kind': kind,
    'title': title,
    'updated_at': encodeDate(updatedAt),
    'last_message_body': lastMessageBody,
    'last_message_at': encodeDateOrNull(lastMessageAt),
    'unread_count': unreadCount,
    'pending_proposals': pendingProposals,
  };

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.id == id &&
      other.clubId == clubId &&
      other.teamId == teamId &&
      other.eventId == eventId &&
      other.kind == kind &&
      other.title == title &&
      other.updatedAt == updatedAt &&
      other.lastMessageBody == lastMessageBody &&
      other.lastMessageAt == lastMessageAt &&
      other.unreadCount == unreadCount &&
      other.pendingProposals == pendingProposals;

  @override
  int get hashCode => Object.hash(
    id,
    clubId,
    teamId,
    eventId,
    kind,
    title,
    updatedAt,
    lastMessageBody,
    lastMessageAt,
    unreadCount,
    pendingProposals,
  );
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.title,
    this.clubId,
    this.teamId,
    this.eventId,
  });

  final String id;
  final String? clubId;
  final String? teamId;
  final String? eventId;
  final String kind;
  final String title;

  factory Conversation.fromJson(JsonMap json) => Conversation(
    id: asUuid(json['id'], key: 'id'),
    clubId: asUuidOrNull(json['club_id'], key: 'club_id'),
    teamId: asUuidOrNull(json['team_id'], key: 'team_id'),
    eventId: asUuidOrNull(json['event_id'], key: 'event_id'),
    kind: asString(json['kind'], key: 'kind'),
    title: asString(json['title'], key: 'title'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'club_id': clubId,
    'team_id': teamId,
    'event_id': eventId,
    'kind': kind,
    'title': title,
  };

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.id == id &&
      other.clubId == clubId &&
      other.teamId == teamId &&
      other.eventId == eventId &&
      other.kind == kind &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, clubId, teamId, eventId, kind, title);
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.senderName,
    this.metadata,
  });

  final String id;
  final String conversationId;

  /// Nil when the assistant wrote it.
  final String? senderId;
  final String? senderName;

  /// `text` | `system` | `agent`
  final String kind;
  final String body;
  final Map<String, JsonValue>? metadata;
  final DateTime createdAt;

  factory ChatMessage.fromJson(JsonMap json) => ChatMessage(
    id: asUuid(json['id'], key: 'id'),
    conversationId: asUuid(json['conversation_id'], key: 'conversation_id'),
    senderId: asUuidOrNull(json['sender_id'], key: 'sender_id'),
    senderName: asStringOrNull(json['sender_name'], key: 'sender_name'),
    kind: asString(json['kind'], key: 'kind'),
    body: asString(json['body'], key: 'body'),
    metadata: JsonValue.mapFrom(json['metadata']),
    createdAt: asDate(json['created_at'], key: 'created_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'sender_name': senderName,
    'kind': kind,
    'body': body,
    'metadata': JsonValue.mapToJson(metadata),
    'created_at': encodeDate(createdAt),
  };

  bool get isFromAgent => kind == 'agent';

  String get authorLabel => senderName ?? 'Assistant';

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.conversationId == conversationId &&
      other.senderId == senderId &&
      other.senderName == senderName &&
      other.kind == kind &&
      other.body == body &&
      mapEquals(other.metadata, metadata) &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, conversationId, senderId, senderName, kind, body, createdAt);
}

enum ProposalKind {
  availability('availability'),
  squad('squad'),
  announcement('announcement'),
  paymentChase('payment_chase');

  const ProposalKind(this.wire);

  final String wire;

  String get label => switch (this) {
    ProposalKind.availability => 'Availability',
    ProposalKind.squad => 'Squad',
    ProposalKind.announcement => 'Announcement',
    ProposalKind.paymentChase => 'Match fees',
  };

  static ProposalKind? named(String? raw) =>
      enumFromRaw(ProposalKind.values, raw, (ProposalKind k) => k.wire);
}

/// Something the assistant thinks needs doing. Applied only by a captain.
@immutable
class AgentProposal {
  const AgentProposal({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.payload,
    required this.rationale,
    required this.confidence,
    required this.status,
    required this.createdAt,
    this.subjectUserId,
    this.eventId,
  });

  final String id;
  final String conversationId;
  final String kind;
  final String? subjectUserId;
  final String? eventId;
  final ProposalPayload payload;
  final String rationale;
  final String confidence;
  final String status;
  final DateTime createdAt;

  factory AgentProposal.fromJson(JsonMap json) => AgentProposal(
    id: asUuid(json['id'], key: 'id'),
    conversationId: asUuid(json['conversation_id'], key: 'conversation_id'),
    kind: asString(json['kind'], key: 'kind'),
    subjectUserId: asUuidOrNull(json['subject_user_id'], key: 'subject_user_id'),
    eventId: asUuidOrNull(json['event_id'], key: 'event_id'),
    payload: ProposalPayload.fromJson(asMap(json['payload'], key: 'payload')),
    rationale: asString(json['rationale'], key: 'rationale'),
    confidence: asString(json['confidence'], key: 'confidence'),
    status: asString(json['status'], key: 'status'),
    createdAt: asDate(json['created_at'], key: 'created_at'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'conversation_id': conversationId,
    'kind': kind,
    'subject_user_id': subjectUserId,
    'event_id': eventId,
    'payload': payload.toJson(),
    'rationale': rationale,
    'confidence': confidence,
    'status': status,
    'created_at': encodeDate(createdAt),
  };

  ProposalKind? get proposalKind => ProposalKind.named(kind);

  bool get isPending => status == 'pending';

  @override
  bool operator ==(Object other) =>
      other is AgentProposal &&
      other.id == id &&
      other.conversationId == conversationId &&
      other.kind == kind &&
      other.subjectUserId == subjectUserId &&
      other.eventId == eventId &&
      other.payload == payload &&
      other.rationale == rationale &&
      other.confidence == confidence &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    kind,
    subjectUserId,
    eventId,
    payload,
    rationale,
    confidence,
    status,
    createdAt,
  );
}

@immutable
class ProposalPayload {
  const ProposalPayload({
    this.date,
    this.availabilityStatus,
    this.note,
    this.userIds,
    this.message,
  });

  final String? date;
  final AvailabilityStatus? availabilityStatus;
  final String? note;
  final List<String>? userIds;
  final String? message;

  factory ProposalPayload.fromJson(JsonMap json) => ProposalPayload(
    date: asStringOrNull(json['date'], key: 'date'),
    availabilityStatus: AvailabilityStatus.fromJsonOrNull(json['availability_status']),
    note: asStringOrNull(json['note'], key: 'note'),
    userIds: json['user_ids'] == null
        ? null
        : asList(json['user_ids'], (Object? v) => asUuid(v, key: 'user_ids')),
    message: asStringOrNull(json['message'], key: 'message'),
  );

  JsonMap toJson() => <String, dynamic>{
    'date': date,
    'availability_status': availabilityStatus?.toJson(),
    'note': note,
    'user_ids': userIds,
    'message': message,
  };

  /// One line describing what applying this would do.
  String get summary {
    if (message case final String m) return m;
    if (date case final String d) {
      if (availabilityStatus case final AvailabilityStatus s) {
        return 'Set ${s.wire} for $d';
      }
    }
    if (userIds case final List<String> ids when ids.isNotEmpty) {
      return 'Invite ${ids.length} players';
    }
    return 'No details';
  }

  @override
  bool operator ==(Object other) =>
      other is ProposalPayload &&
      other.date == date &&
      other.availabilityStatus == availabilityStatus &&
      other.note == note &&
      listEquals(other.userIds, userIds) &&
      other.message == message;

  @override
  int get hashCode => Object.hash(
    date,
    availabilityStatus,
    note,
    userIds == null ? null : Object.hashAll(userIds!),
    message,
  );
}

@immutable
class AgentRun {
  const AgentRun({
    required this.id,
    required this.model,
    required this.status,
    this.inputTokens,
    this.outputTokens,
    this.error,
  });

  final String id;
  final String model;
  final String status;
  final int? inputTokens;
  final int? outputTokens;
  final String? error;

  factory AgentRun.fromJson(JsonMap json) => AgentRun(
    id: asUuid(json['id'], key: 'id'),
    model: asString(json['model'], key: 'model'),
    status: asString(json['status'], key: 'status'),
    inputTokens: asIntOrNull(json['input_tokens'], key: 'input_tokens'),
    outputTokens: asIntOrNull(json['output_tokens'], key: 'output_tokens'),
    error: asStringOrNull(json['error'], key: 'error'),
  );

  JsonMap toJson() => <String, dynamic>{
    'id': id,
    'model': model,
    'status': status,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'error': error,
  };

  bool get isDisabled => status == 'disabled';

  @override
  bool operator ==(Object other) =>
      other is AgentRun &&
      other.id == id &&
      other.model == model &&
      other.status == status &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.error == error;

  @override
  int get hashCode => Object.hash(id, model, status, inputTokens, outputTokens, error);
}

@immutable
class AgentAnalysis {
  const AgentAnalysis({required this.run, required this.proposals, this.summary});

  final AgentRun run;
  final List<AgentProposal> proposals;
  final String? summary;

  factory AgentAnalysis.fromJson(JsonMap json) => AgentAnalysis(
    run: AgentRun.fromJson(asMap(json['run'], key: 'run')),
    proposals: asList(
      json['proposals'],
      (Object? v) => AgentProposal.fromJson(asMap(v, key: 'proposals')),
    ),
    summary: asStringOrNull(json['summary'], key: 'summary'),
  );

  JsonMap toJson() => <String, dynamic>{
    'run': run.toJson(),
    'proposals': proposals.map((AgentProposal p) => p.toJson()).toList(growable: false),
    'summary': summary,
  };

  @override
  bool operator ==(Object other) =>
      other is AgentAnalysis &&
      other.run == run &&
      listEquals(other.proposals, proposals) &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(run, Object.hashAll(proposals), summary);
}
