import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/sync/domain/op_state.dart';
import 'outbox_dao.dart';

part 'app_database.g.dart';

/// Durable outbox. A row is written BEFORE the UI says an action is queued (spec §2).
@DataClassName('OutboxOp')
class OutboxOperations extends Table {
  /// Insertion order = submission order; preserves dependency order across restarts.
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get clientOperationId => text().unique()();
  TextColumn get idempotencyKey => text()();
  TextColumn get storeId => text()();
  TextColumn get module => text()();
  TextColumn get operationType => text()();

  /// Human-readable label, e.g. "Sale S-1042".
  TextColumn get label => text()();
  TextColumn get entityId => text().nullable()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get payloadJson => text()();
  TextColumn get dependsOnJson => text().withDefault(const Constant('[]'))();
  TextColumn get state => textEnum<OpState>()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// True once the op left the device at least once; it may have committed server-side.
  BoolColumn get everSent => boolean().withDefault(const Constant(false))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  TextColumn get serverResourceId => text().nullable()();
  IntColumn get serverVersion => integer().nullable()();
  TextColumn get conflictJson => text().nullable()();

  /// For an op created to resolve a conflict: the conflicted op's id.
  TextColumn get resolutionOf => text().nullable()();

  /// How this op ended if resolved/cancelled: KEEP_SERVER, KEEP_DEVICE, USER_CANCELLED.
  TextColumn get resolution => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

/// Small key/value store: device id, pull cursor, last successful sync.
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Read-only mirror of server-canonical records received through `/sync/pull`.
/// Local pending changes live in the outbox and are labelled separately.
@DataClassName('LocalEntity')
class LocalEntities extends Table {
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  IntColumn get version => integer()();
  TextColumn get dataJson => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entity, entityId};
}

@DriftDatabase(tables: [OutboxOperations, SyncMeta, LocalEntities], daos: [OutboxDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ??
            driftDatabase(
              name: 'medical_store',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_state_seq ON outbox_operations (state, seq)',
          );
        },
      );
}
