import 'package:flutter/foundation.dart';

import '../models/fishers_models.dart';
import '../services/fishers_api.dart';
import '../services/network_service.dart';

/// Chat state — a port of `ios/Fishers/ViewModels/ChatStore.swift`.
///
/// The thread list, the open thread's messages, and the assistant's proposals.
/// The proposals are read but not yet acted on: applying one is a captain's
/// decision and belongs with the rest of the assistant work, which has not
/// been ported.
class ChatStore extends ChangeNotifier {
  List<ConversationSummary> _conversations = <ConversationSummary>[];
  List<ChatMessage> _messages = <ChatMessage>[];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  String? _openConversationId;

  List<ConversationSummary> get conversations =>
      List<ConversationSummary>.unmodifiable(_conversations);

  /// Oldest at the top, as a thread reads. The API pages newest-first — "the
  /// latest 50" is a LIMIT on a descending query — so what arrives is upside
  /// down, and iOS reverses it for the same reason.
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get openConversationId => _openConversationId;

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();
    try {
      _conversations = await FishersAPI.conversations();
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } on Object catch (error) {
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> open(ConversationSummary conversation) async {
    _openConversationId = conversation.id;
    _messages = <ChatMessage>[];
    notifyListeners();
    await refreshThread();
    // Clearing the badge is best-effort; a failure here should not surface.
    try {
      await FishersAPI.markRead(conversationId: conversation.id);
    } on Object {
      // The count corrects itself on the next load.
    }
    await loadConversations();
  }

  Future<void> refreshThread() async {
    final String? id = _openConversationId;
    if (id == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final List<ChatMessage> page = await FishersAPI.messages(conversationId: id);
      _messages = page.reversed.toList(growable: false);
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } on Object catch (error) {
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Somebody else wrote in the open thread: show it, and it has been read.
  Future<void> threadChanged() async {
    final String? id = _openConversationId;
    if (id == null) return;
    await refreshThread();
    try {
      await FishersAPI.markRead(conversationId: id);
    } on Object {
      // As above.
    }
  }

  Future<void> send(String body) async {
    final String? id = _openConversationId;
    final String trimmed = body.trim();
    if (id == null || trimmed.isEmpty) return;
    _isSending = true;
    notifyListeners();
    try {
      final ChatMessage message = await FishersAPI.postMessage(conversationId: id, body: trimmed);
      _messages = <ChatMessage>[..._messages, message];
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } on Object catch (error) {
      _errorMessage = '$error';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void close() {
    _openConversationId = null;
    _messages = <ChatMessage>[];
  }
}
