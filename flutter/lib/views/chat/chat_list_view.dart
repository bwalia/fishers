import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/fishers_models.dart';
import '../../stores/chat_store.dart';
import '../../theme/fishers_theme.dart';
import 'chat_thread_view.dart';

/// Threads the member belongs to — a port of
/// `ios/Fishers/Views/Chat/ChatListView.swift`, with the unread count and the
/// badge for assistant proposals waiting on a captain.
class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatStore>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ChatStore store = context.watch<ChatStore>();
    final FishersColors colors = FishersColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: RefreshIndicator(
        onRefresh: store.loadConversations,
        child: Builder(
          builder: (BuildContext context) {
            if (store.conversations.isEmpty && store.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (store.conversations.isEmpty) {
              return ListView(
                children: <Widget>[
                  const SizedBox(height: 80),
                  Icon(
                    Icons.forum_outlined,
                    size: 40,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: FishersTheme.space2),
                  Center(
                    child: Text('No chats yet', style: FishersTheme.contentTitle(context)),
                  ),
                  const SizedBox(height: FishersTheme.space1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FishersTheme.space3),
                    child: Text(
                      store.errorMessage ??
                          'Start a thread for your club — availability and squads '
                              'get sorted here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: store.errorMessage != null ? colors.unavailable : null,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: store.conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final ConversationSummary c = store.conversations[index];
                return ListTile(
                  key: Key('chat.thread.${c.id}'),
                  leading: Icon(_iconFor(c.kind)),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: c.lastMessageBody == null
                      ? null
                      : Text(
                          c.lastMessageBody!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: _trailing(context, c),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatThreadView(conversation: c, store: store),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget? _trailing(BuildContext context, ConversationSummary c) {
    final FishersColors colors = FishersColors.of(context);
    final List<Widget> badges = <Widget>[
      if (c.pendingProposals > 0)
        Tooltip(
          message: 'Suggestions waiting on a captain',
          child: Icon(Icons.auto_awesome, size: 16, color: colors.maybe),
        ),
      if (c.unreadCount > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${c.unreadCount}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ),
    ];
    if (badges.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: badges,
    );
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'event' => Icons.event,
    'team' => Icons.groups,
    'direct' => Icons.person,
    _ => Icons.forum,
  };
}
