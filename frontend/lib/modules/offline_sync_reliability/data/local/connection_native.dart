import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor openDefaultConnection() {
  try {
    final file = File('${Directory.systemTemp.path}/medical_store_outbox.sqlite');
    return NativeDatabase.createInBackground(file);
  } catch (_) {
    return NativeDatabase.memory();
  }
}

