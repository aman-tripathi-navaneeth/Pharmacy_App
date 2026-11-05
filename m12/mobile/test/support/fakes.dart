import 'dart:async';

import 'package:medical_store/core/auth_session.dart';
import 'package:medical_store/core/connectivity_monitor.dart';

class FakeSession implements AuthSession {
  @override
  Future<String?> accessToken() async => 'token';
  @override
  String get storeId => 'store-1';
}

class FakeConnectivity implements ConnectivityMonitor {
  final _c = StreamController<bool>.broadcast();
  bool _online = true;
  @override
  bool get isOnline => _online;
  @override
  Stream<bool> get changes => _c.stream;
  set online(bool v) {
    _online = v;
    _c.add(v);
  }
}

