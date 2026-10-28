import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device has a network interface. This does NOT guarantee
/// the API is reachable (spec §12); request failures are handled by retries.
abstract interface class ConnectivityMonitor {
  bool get isOnline;
  Stream<bool> get changes;
}

class PlusConnectivityMonitor implements ConnectivityMonitor {
  PlusConnectivityMonitor([Connectivity? connectivity]) : _connectivity = connectivity ?? Connectivity() {
    _sub = _connectivity.onConnectivityChanged.listen(_update);
    _connectivity.checkConnectivity().then(_update);
  }

  final Connectivity _connectivity;
  late final StreamSubscription<List<ConnectivityResult>> _sub;
  final _controller = StreamController<bool>.broadcast();
  bool _online = true;

  /// Debug-only switch so offline mode can be exercised on a simulator.
  bool forceOffline = false;
  bool _reported = true;

  void _update(List<ConnectivityResult> results) {
    _reported = results.any((r) => r != ConnectivityResult.none);
    _emit();
  }

  void setForceOffline(bool value) {
    forceOffline = value;
    _emit();
  }

  void _emit() {
    final next = _reported && !forceOffline;
    if (next == _online) return;
    _online = next;
    _controller.add(next);
  }

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get changes => _controller.stream;

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}
