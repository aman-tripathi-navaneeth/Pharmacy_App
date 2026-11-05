import 'package:drift/wasm.dart';

/// Compiled to web/drift_worker.js: dart compile js -O2 -o web/drift_worker.js tool/drift_worker.dart
void main() => WasmDatabase.workerMainForOpen();
