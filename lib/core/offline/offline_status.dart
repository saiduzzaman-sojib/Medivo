import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class OfflineState {
  const OfflineState({this.offline = false, this.savedAt});

  /// The last request could not reach the server.
  final bool offline;

  /// The oldest saved answer that was shown instead of fresh data.
  final DateTime? savedAt;
}

/// Tells the screens whether they are showing saved data.
class OfflineStatus extends ChangeNotifier {
  OfflineState _state = const OfflineState();

  OfflineState get state => _state;

  void markOffline([DateTime? savedAt]) {
    DateTime? at = _state.offline ? _state.savedAt : null;
    if (savedAt != null && (at == null || savedAt.isBefore(at))) at = savedAt;
    if (_state.offline && at == _state.savedAt) return;
    _state = OfflineState(offline: true, savedAt: at);
    notifyListeners();
  }

  void markOnline() {
    if (!_state.offline) return;
    _state = const OfflineState();
    notifyListeners();
  }
}

/// One shared instance, because the network client is created before the app starts.
final OfflineStatus offlineStatus = OfflineStatus();

final offlineStatusProvider = ChangeNotifierProvider<OfflineStatus>((ref) => offlineStatus);