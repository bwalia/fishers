import 'package:flutter/foundation.dart';

import '../models/fishers_models.dart';
import '../services/fishers_api.dart';
import '../services/network_service.dart';

/// One man-of-the-match vote — a port of
/// `ios/Fishers/ViewModels/MotmStore.swift`.
///
/// Per-card rather than one store for the whole app: a thread can carry
/// several finished fixtures' votes at once, and they are independent.
class MotmStore extends ChangeNotifier {
  MotmStore({required this.pollId});

  final String pollId;

  MotmPollView? _view;
  bool _isLoading = false;
  bool _isVoting = false;
  String? _errorMessage;

  MotmPollView? get view => _view;
  bool get isLoading => _isLoading;
  bool get isVoting => _isVoting;
  String? get errorMessage => _errorMessage;

  List<MotmCandidate> get candidates => _view?.candidates ?? const <MotmCandidate>[];
  String? get myVote => _view?.myVote;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _view = await FishersAPI.motmPoll(pollId: pollId);
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

  /// Tapping the person you already voted for takes the vote back, so a
  /// mis-tap is undone by the tap that made it.
  Future<void> vote(String candidateUserId) async {
    if (_isVoting) return;
    _isVoting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _view = myVote == candidateUserId
          ? await FishersAPI.withdrawManOfTheMatchVote(pollId: pollId)
          : await FishersAPI.voteForManOfTheMatch(
              pollId: pollId,
              candidateUserId: candidateUserId,
            );
    } on ApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } on Object catch (error) {
      _errorMessage = '$error';
    } finally {
      _isVoting = false;
      notifyListeners();
    }
  }

  /// Captain or secretary. A refusal here is ordinary — most of a club cannot
  /// close a vote — so it is said plainly. The shared RBAC refusal answers
  /// with the permission's own name ("cannot manage_events"), which is the
  /// right sentence for an API and the wrong one for a card every member of
  /// the club is going to tap once out of curiosity.
  Future<void> close() async {
    if (_isVoting) return;
    _isVoting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _view = await FishersAPI.closeManOfTheMatchVote(pollId: pollId);
    } on ApiException catch (error) {
      _errorMessage = error.isForbidden
          ? 'Only a captain or club secretary can close the vote.'
          : error.friendlyMessage;
    } on Object catch (error) {
      _errorMessage = '$error';
    } finally {
      _isVoting = false;
      notifyListeners();
    }
  }
}
