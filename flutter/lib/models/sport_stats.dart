import 'package:flutter/foundation.dart';

import 'player_profile.dart';

/// Per-sport stat catalogs — a port of `ios/Fishers/Models/SportStats.swift`.
///
/// Values are stored as strings on `SportProfile.stats` so the backend can keep
/// them in one JSONB column per sport, and the catalog below drives the stats
/// form during profile setup, so adding a sport needs no new UI.

/// A single stat a player can record for a sport.
@immutable
class StatField {
  const StatField({required this.key, required this.label, required this.kind, this.footnote});

  final String key;
  final String label;
  final StatFieldKind kind;
  final String? footnote;

  String get id => key;

  static StatField choice(String key, String label, List<String> options, {String? footnote}) =>
      StatField(key: key, label: label, kind: StatChoice(options), footnote: footnote);

  static StatField integer(
    String key,
    String label, {
    int min = 0,
    int max = 999,
    String? footnote,
  }) => StatField(
    key: key,
    label: label,
    kind: StatInteger(min: min, max: max),
    footnote: footnote,
  );

  static StatField decimal(
    String key,
    String label, {
    String placeholder = '0.0',
    String? footnote,
  }) => StatField(key: key, label: label, kind: StatDecimal(placeholder), footnote: footnote);

  static StatField text(String key, String label, {String placeholder = '', String? footnote}) =>
      StatField(key: key, label: label, kind: StatText(placeholder), footnote: footnote);

  @override
  bool operator ==(Object other) =>
      other is StatField &&
      other.key == key &&
      other.label == label &&
      other.kind == kind &&
      other.footnote == footnote;

  @override
  int get hashCode => Object.hash(key, label, kind, footnote);
}

@immutable
sealed class StatFieldKind {
  const StatFieldKind();
}

@immutable
class StatChoice extends StatFieldKind {
  const StatChoice(this.options);
  final List<String> options;
  @override
  bool operator ==(Object other) => other is StatChoice && listEquals(other.options, options);
  @override
  int get hashCode => Object.hashAll(options);
}

@immutable
class StatInteger extends StatFieldKind {
  const StatInteger({required this.min, required this.max});
  final int min;
  final int max;
  @override
  bool operator ==(Object other) => other is StatInteger && other.min == min && other.max == max;
  @override
  int get hashCode => Object.hash(min, max);
}

@immutable
class StatDecimal extends StatFieldKind {
  const StatDecimal(this.placeholder);
  final String placeholder;
  @override
  bool operator ==(Object other) => other is StatDecimal && other.placeholder == placeholder;
  @override
  int get hashCode => placeholder.hashCode;
}

@immutable
class StatText extends StatFieldKind {
  const StatText(this.placeholder);
  final String placeholder;
  @override
  bool operator ==(Object other) => other is StatText && other.placeholder == placeholder;
  @override
  int get hashCode => placeholder.hashCode;
}

abstract final class SportStats {
  static List<StatField> fields(Sport sport) => switch (sport) {
    Sport.cricket => <StatField>[
      StatField.choice('batting_style', 'Batting', <String>['Right-hand', 'Left-hand']),
      StatField.choice('bowling_style', 'Bowling', <String>[
        'Right-arm fast',
        'Right-arm medium',
        'Off-spin',
        'Leg-spin',
        'Left-arm seam',
        'Left-arm orthodox',
        "Doesn't bowl",
      ]),
      StatField.integer('batting_number', 'Usual batting position', min: 1, max: 11),
      StatField.decimal('batting_average', 'Batting average', placeholder: '24.5'),
      StatField.decimal('bowling_average', 'Bowling average', placeholder: '18.2'),
      StatField.integer('high_score', 'Highest score'),
      StatField.integer('wickets', 'Career wickets'),
      StatField.integer('catches', 'Catches'),
      StatField.integer('matches', 'Matches played'),
    ],
    Sport.paddle => <StatField>[
      StatField.choice('side', 'Preferred side', <String>[
        'Right side',
        'Left side',
        'Either side',
      ]),
      StatField.decimal(
        'padel_level',
        'Padel level',
        placeholder: '3.5',
        footnote: '0–7 scale used by most clubs and Playtomic.',
      ),
      StatField.choice('play_style', 'Style', <String>['Attacking', 'Defensive', 'Balanced']),
      StatField.integer('matches', 'Matches played'),
      StatField.integer('win_rate', 'Win rate', min: 0, max: 100),
      StatField.text('partner', 'Regular partner'),
    ],
    Sport.badminton => <StatField>[
      StatField.choice('discipline', 'Main discipline', <String>[
        'Singles',
        'Doubles',
        'Mixed doubles',
      ]),
      StatField.choice('racket_hand', 'Racket hand', <String>['Right', 'Left']),
      StatField.choice('club_grade', 'Club grade', <String>[
        'Social',
        'Club league',
        'County',
        'National',
      ]),
      StatField.integer('ladder_position', 'Club ladder position', min: 1, max: 200),
      StatField.integer('matches', 'Matches played'),
      StatField.integer('win_rate', 'Win rate', min: 0, max: 100),
    ],
    Sport.football => <StatField>[
      StatField.choice('foot', 'Preferred foot', <String>['Right', 'Left', 'Both']),
      StatField.integer('shirt_number', 'Shirt number', min: 1, max: 99),
      StatField.integer('appearances', 'Appearances'),
      StatField.integer('goals', 'Goals'),
      StatField.integer('assists', 'Assists'),
      StatField.integer('clean_sheets', 'Clean sheets', footnote: 'Goalkeepers and defenders.'),
    ],
    Sport.rugby => <StatField>[
      StatField.integer('shirt_number', 'Usual shirt number', min: 1, max: 23),
      StatField.integer('appearances', 'Appearances'),
      StatField.integer('tries', 'Tries'),
      StatField.integer('points', 'Points scored'),
      StatField.choice('kicker', 'Goal kicker', <String>['Yes', 'No']),
    ],
    Sport.tennis => <StatField>[
      StatField.decimal('rating', 'LTA / NTRP rating', placeholder: '4.0'),
      StatField.choice('hand', 'Racket hand', <String>['Right', 'Left']),
      StatField.choice('surface', 'Preferred surface', <String>['Hard', 'Clay', 'Grass', 'Indoor']),
      StatField.integer('matches', 'Matches played'),
      StatField.integer('win_rate', 'Win rate', min: 0, max: 100),
    ],
    Sport.hockey => <StatField>[
      StatField.integer('shirt_number', 'Shirt number', min: 1, max: 99),
      StatField.integer('appearances', 'Appearances'),
      StatField.integer('goals', 'Goals'),
      StatField.choice('penalty_corner', 'Penalty corner role', <String>[
        'Injector',
        'Stopper',
        'Striker',
        'None',
      ]),
    ],
    Sport.netball => <StatField>[
      StatField.integer('appearances', 'Appearances'),
      StatField.integer('goals', 'Goals scored'),
      StatField.integer('intercepts', 'Intercepts'),
      StatField.choice('bib_flexibility', 'Can cover', <String>[
        'One position',
        'Two positions',
        'Anywhere',
      ]),
    ],
    Sport.basketball => <StatField>[
      StatField.integer('shirt_number', 'Shirt number', min: 0, max: 99),
      StatField.decimal('points_per_game', 'Points per game', placeholder: '8.5'),
      StatField.decimal('rebounds_per_game', 'Rebounds per game', placeholder: '4.0'),
      StatField.decimal('assists_per_game', 'Assists per game', placeholder: '2.5'),
      StatField.integer('games', 'Games played'),
    ],
    Sport.pickleball => <StatField>[
      StatField.choice('discipline', 'Main discipline', <String>[
        'Singles',
        'Doubles',
        'Mixed doubles',
      ]),
      StatField.choice('side', 'Preferred side', <String>[
        'Right side',
        'Left side',
        'Either side',
      ]),
      StatField.decimal(
        'dupr_rating',
        'DUPR rating',
        placeholder: '3.5',
        footnote: '2.0–8.0, the rating most leagues ask for.',
      ),
      StatField.integer('matches', 'Matches played'),
      StatField.integer('win_rate', 'Win rate', min: 0, max: 100),
      StatField.text('partner', 'Regular partner'),
    ],
    // Whatever the club plays that this app has no catalog for. Enough to say
    // something on a profile rather than showing an empty card.
    Sport.other => <StatField>[
      StatField.text('discipline', 'What you play'),
      StatField.integer('matches', 'Matches played'),
      StatField.integer('win_rate', 'Win rate', min: 0, max: 100),
    ],
  };

  /// Non-empty stats in catalog order, ready to render on the profile.
  static List<({String label, String value})> summary(SportProfile profile) {
    final Sport? sport = Sport.named(profile.sport);
    if (sport == null) return const <({String label, String value})>[];
    return <({String label, String value})>[
      for (final StatField field in fields(sport))
        if (profile.stats[field.key] case final String raw when raw.isNotEmpty)
          (label: field.label, value: _formatted(raw, field)),
    ];
  }

  static String _formatted(String raw, StatField field) =>
      field.key.endsWith('win_rate') ? '$raw%' : raw;
}
