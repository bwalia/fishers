import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/fishers_models.dart';
import '../../stores/chat_store.dart';
import '../../theme/fishers_theme.dart';
import 'man_of_the_match_card.dart';

/// One thread — a port of `ios/Fishers/Views/Chat/ChatThreadView.swift`.
///
/// The assistant's proposal cards are not here yet: applying one is a
/// captain's decision and belongs with the rest of the assistant work, which
/// has not been ported. Everything else a member does in a thread is.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({required this.conversation, required this.store, super.key});

  final ConversationSummary conversation;
  final ChatStore store;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  final TextEditingController _draft = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // After the frame, not during it: `open` notifies its listeners as soon
    // as it sets the thread, and a notifier that fires inside `initState`
    // marks the provider dirty while the framework is still building it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.store.open(widget.conversation).then((_) => _scrollToEnd());
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    widget.store.close();
    super.dispose();
  }

  /// Opening a thread lands at the bottom of it, as every other chat app does.
  ///
  /// A beat first: the list builds its rows as they come into view, so asking
  /// in the same frame as the messages arrive scrolls to where the list used
  /// to end. The iOS card had the same problem and the same answer.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final String body = _draft.text;
    if (body.trim().isEmpty) return;
    _draft.clear();
    await widget.store.send(body);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final ChatStore store = context.watch<ChatStore>();
    final FishersColors colors = FishersColors.of(context);
    final List<ChatMessage> messages = store.messages;

    return Scaffold(
      appBar: AppBar(title: Text(widget.conversation.title)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: messages.isEmpty && store.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: FishersTheme.space2),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatMessage message = messages[index];
                      final String? poll = _motmPollId(message);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _Bubble(message: message),
                          // A vote the server opened when the game ended.
                          // Rendered under the message that announced it, so
                          // it reads as part of the conversation rather than
                          // a screen somebody has to go and find.
                          if (poll != null) ManOfTheMatchCard(pollId: poll),
                        ],
                      );
                    },
                  ),
          ),
          if (store.errorMessage != null)
            Container(
              width: double.infinity,
              color: colors.unavailable,
              padding: const EdgeInsets.all(FishersTheme.space1),
              child: Text(
                store.errorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(FishersTheme.space1),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('chat.composer'),
                      controller: _draft,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: FishersTheme.space1),
                  IconButton.filled(
                    key: const Key('chat.send'),
                    tooltip: 'Send',
                    onPressed: store.isSending ? null : _send,
                    icon: store.isSending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The vote a message opened, if it opened one.
  ///
  /// Only the message that *opened* the vote carries a card. The server also
  /// posts the result when voting closes, and a correction when a super over
  /// changes it — both carry the same poll id, and honouring them would put
  /// three identical cards in the thread.
  static String? _motmPollId(ChatMessage message) {
    final Map<String, JsonValue>? metadata = message.metadata;
    if (metadata == null) return null;
    // Strings only, as Swift's `case let .string(...)` is — a number that
    // stringifies to the right thing is not the right thing.
    final String? kind = switch (metadata['kind']) {
      JsonString(:final String value) => value,
      _ => null,
    };
    if (kind != 'motm_poll') return null;
    return switch (metadata['motm_poll_id']) {
      JsonString(:final String value) => value,
      _ => null,
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final FishersColors colors = FishersColors.of(context);
    final bool fromAgent = message.isFromAgent;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FishersTheme.space2,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (fromAgent)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.auto_awesome, size: 12, color: colors.accent),
                ),
              Text(
                message.authorLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fromAgent ? colors.accent : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                TimeOfDay.fromDateTime(message.createdAt.toLocal()).format(context),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fromAgent
                  ? colors.accent.withValues(alpha: 0.12)
                  : colors.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message.body, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
