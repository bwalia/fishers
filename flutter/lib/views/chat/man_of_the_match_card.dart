import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/fishers_models.dart';
import '../../stores/motm_store.dart';
import '../../theme/fishers_theme.dart';

/// The man-of-the-match vote, in the thread where it was announced — a port of
/// `ios/Fishers/Views/Chat/ManOfTheMatchCard.swift`.
///
/// Both team sheets are on the ballot: a man of the match is quite often the
/// opposition's opening bowler. Anybody in either club may vote, whether they
/// played or watched — that asymmetry is the feature, because the eleven who
/// played are not the eleven best placed to judge who played best.
class ManOfTheMatchCard extends StatelessWidget {
  const ManOfTheMatchCard({required this.pollId, super.key});

  final String pollId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<MotmStore>(
    create: (_) => MotmStore(pollId: pollId)..load(),
    child: const _Card(),
  );
}

class _Card extends StatelessWidget {
  const _Card();

  @override
  Widget build(BuildContext context) {
    final MotmStore store = context.watch<MotmStore>();
    final FishersColors colors = FishersColors.of(context);
    final MotmPollView? view = store.view;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: FishersTheme.space2,
        vertical: FishersTheme.space1,
      ),
      padding: const EdgeInsets.all(FishersTheme.space2),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FishersTheme.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(context, view),
          if (view == null && store.isLoading)
            const Padding(
              padding: EdgeInsets.all(FishersTheme.space2),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (view != null) ...<Widget>[
            const SizedBox(height: FishersTheme.space1),
            if (view.poll.isOpen) ..._ballot(context, store, view) else ..._result(context, view),
          ],
          if (store.errorMessage != null) ...<Widget>[
            const SizedBox(height: FishersTheme.space1),
            Text(
              store.errorMessage!,
              key: const Key('motm.error'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.unavailable),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, MotmPollView? view) => Row(
    children: <Widget>[
      const Icon(Icons.emoji_events, size: 18, color: FishersTheme.gold),
      const SizedBox(width: FishersTheme.space1),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Man of the match',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (view != null)
              Text(
                view.poll.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      if (view != null)
        Chip(
          label: Text(view.poll.isOpen ? _closingLabel(view.poll.closesAt) : 'Closed'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
    ],
  );

  List<Widget> _ballot(BuildContext context, MotmStore store, MotmPollView view) {
    final ({String away, String home}) names = view.sideNames;
    return <Widget>[
      Text(
        !view.canVote
            ? 'Only the two clubs who played can vote.'
            : view.myVote == null
            ? 'Who was your man of the match? Tap a name — you can change it until voting closes.'
            : 'Your vote is in. Tap another name to change it, or the same one to take it back.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: FishersTheme.space1),
      ..._sheet(context, store, view, 'home', names.home),
      ..._sheet(context, store, view, 'away', names.away),
      const SizedBox(height: FishersTheme.space1),
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              view.tallyVisible
                  ? '${view.totalVotes} ${view.totalVotes == 1 ? "vote" : "votes"} so far.'
                  : 'Votes are hidden until you have voted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // Offered to everyone, the same as on the dashboard, rather than
          // hidden behind this app's own guess at who counts as a captain —
          // the poll's club and the fixture's team decide that, and the
          // phone knows neither for certain.
          TextButton(
            key: const Key('motm.close'),
            onPressed: store.isVoting ? null : store.close,
            child: const Text('Close the vote'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _sheet(
    BuildContext context,
    MotmStore store,
    MotmPollView view,
    String side,
    String label,
  ) {
    final List<MotmCandidate> players = view.sheet(side);
    if (players.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: FishersTheme.space1, bottom: 2),
        child: Text(label.toUpperCase(), style: FishersTheme.overline(context)),
      ),
      for (final MotmCandidate player in players)
        _CandidateRow(
          player: player,
          isMine: view.myVote == player.userId,
          showsTally: view.tallyVisible,
          isScorersPick: view.scorerAwardUserId == player.userId,
          enabled: view.canVote && !store.isVoting,
          onTap: () => store.vote(player.userId),
        ),
    ];
  }

  List<Widget> _result(BuildContext context, MotmPollView view) {
    final MotmCandidate? winner = view.winner;
    final List<MotmCandidate> tied = view.tiedAtTheTop;
    final FishersColors colors = FishersColors.of(context);

    if (winner != null) {
      return <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.emoji_events, color: FishersTheme.gold),
            const SizedBox(width: FishersTheme.space1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(winner.displayName, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${winner.votes} of ${view.totalVotes} '
                    '${view.totalVotes == 1 ? "vote" : "votes"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ];
    }
    if (tied.isNotEmpty) {
      // Nobody is recorded as the winner when the vote ties: choosing between
      // two players who drew is a captain's call.
      return <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.balance, color: colors.maybe),
            const SizedBox(width: FishersTheme.space1),
            Expanded(
              child: Text(
                '${tied.map((MotmCandidate c) => c.displayName).join(", ")} '
                'finished level. A captain picks.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ];
    }
    return <Widget>[
      Text(
        'Voting closed with nobody voted for.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  static String _closingLabel(DateTime closesAt) {
    final Duration left = closesAt.difference(DateTime.now());
    if (left.isNegative) return 'Closing';
    if (left.inHours < 1) return '${left.inMinutes.clamp(1, 59)}m left';
    if (left.inDays < 1) return '${left.inHours}h left';
    return '${left.inDays}d left';
  }
}

/// One name on the ballot. A row rather than a picker: the point is to see
/// everybody who played at once and tap one.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.player,
    required this.isMine,
    required this.showsTally,
    required this.isScorersPick,
    required this.enabled,
    required this.onTap,
  });

  final MotmCandidate player;
  final bool isMine;
  final bool showsTally;
  final bool isScorersPick;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final FishersColors colors = FishersColors.of(context);
    return Semantics(
      button: true,
      selected: isMine,
      label: isMine ? '${player.displayName}, your vote' : 'Vote for ${player.displayName}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: FishersTheme.space1),
          child: Row(
            children: <Widget>[
              Icon(
                isMine ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isMine ? colors.available : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: FishersTheme.space1),
              Expanded(
                child: Text(
                  player.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (isScorersPick)
                Padding(
                  padding: const EdgeInsets.only(right: FishersTheme.space1),
                  // The scorer's own award. Shown so the two are never
                  // mistaken for each other.
                  child: Tooltip(
                    message: "The scorer's pick",
                    child: Icon(Icons.edit, size: 14, color: colors.maybe),
                  ),
                ),
              if (showsTally)
                Text(
                  '${player.votes}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
