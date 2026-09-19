import 'package:flutter/foundation.dart';

import 'models.dart';
import 'player_profile.dart';

/// How much of a profile is filled in, and what is worth adding next.
/// A port of `ios/Fishers/Models/ProfileStrength.swift`.
///
/// Nothing here is required to use the app — a name and a sport are enough to
/// be picked and to start a match. The rest is what makes a player someone a
/// captain recognises, so it is counted and asked for, never demanded.
@immutable
class ProfileStrength {
  ProfileStrength(PublicUser user) : items = _items(user);

  final List<ProfileStrengthItem> items;

  static List<ProfileStrengthItem> _items(PublicUser user) {
    final SportProfile? main = user.primaryProfile;
    return <ProfileStrengthItem>[
      ProfileStrengthItem(
        id: 'name',
        title: 'Your name',
        weight: 10,
        done: user.name.trim().isNotEmpty,
      ),
      ProfileStrengthItem(id: 'sport', title: 'What you play', weight: 15, done: main != null),
      ProfileStrengthItem(
        id: 'phone',
        title: 'Your mobile number',
        weight: 10,
        done: _nonEmpty(user.phone),
      ),
      ProfileStrengthItem(
        id: 'photo',
        title: 'A photo',
        weight: 15,
        done: _nonEmpty(user.avatarUrl),
      ),
      ProfileStrengthItem(
        id: 'standard',
        title: 'The standard you play at',
        weight: 15,
        done: main?.tier != null,
      ),
      ProfileStrengthItem(
        id: 'position',
        title: 'Your position',
        weight: 10,
        done: _nonEmpty(main?.position),
      ),
      // Same order and weights as the API's count, so both say the same next
      // thing.
      ProfileStrengthItem(
        id: 'verified',
        title: 'A confirmed email or number',
        weight: 10,
        done: user.isVerified,
      ),
      ProfileStrengthItem(
        id: 'area',
        title: "Where you're based",
        weight: 5,
        done: _nonEmpty(user.location?.area) || _nonEmpty(user.location?.postcode),
      ),
      ProfileStrengthItem(
        id: 'travel',
        title: 'How you get to games',
        weight: 5,
        done: user.location?.transport != null,
      ),
      ProfileStrengthItem(
        id: 'emergency',
        title: 'An emergency contact',
        weight: 5,
        done: _nonEmpty(user.emergencyContact),
      ),
    ];
  }

  static bool _nonEmpty(String? value) => value != null && value.isNotEmpty;

  int get percent => items
      .where((ProfileStrengthItem i) => i.done)
      .fold(0, (int sum, ProfileStrengthItem i) => sum + i.weight);

  bool get isComplete => percent >= 100;

  List<ProfileStrengthItem> get missing =>
      items.where((ProfileStrengthItem i) => !i.done).toList(growable: false);

  /// "Add a photo, the standard you play at and your position" — the three that
  /// count most, in plain words.
  String get nextUp {
    final List<ProfileStrengthItem> sorted = missing.toList()
      ..sort((ProfileStrengthItem a, ProfileStrengthItem b) => b.weight.compareTo(a.weight));
    final List<String> top = sorted
        .take(3)
        .map((ProfileStrengthItem i) => i.title[0].toLowerCase() + i.title.substring(1))
        .toList(growable: false);
    return switch (top.length) {
      0 => '',
      1 => 'Add ${top[0]}',
      _ => 'Add ${top.sublist(0, top.length - 1).join(", ")} and ${top.last}',
    };
  }

  @override
  bool operator ==(Object other) => other is ProfileStrength && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

@immutable
class ProfileStrengthItem {
  const ProfileStrengthItem({
    required this.id,
    required this.title,
    required this.weight,
    required this.done,
  });

  final String id;
  final String title;
  final int weight;
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is ProfileStrengthItem &&
      other.id == id &&
      other.title == title &&
      other.weight == weight &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, title, weight, done);
}
