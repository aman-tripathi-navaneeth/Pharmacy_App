// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_dao.dart';

// ignore_for_file: type=lint
mixin _$OutboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutboxOperationsTable get outboxOperations =>
      attachedDatabase.outboxOperations;
  $SyncMetaTable get syncMeta => attachedDatabase.syncMeta;
  $LocalEntitiesTable get localEntities => attachedDatabase.localEntities;
  OutboxDaoManager get managers => OutboxDaoManager(this);
}

class OutboxDaoManager {
  final _$OutboxDaoMixin _db;
  OutboxDaoManager(this._db);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(
        _db.attachedDatabase,
        _db.outboxOperations,
      );
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db.attachedDatabase, _db.syncMeta);
  $$LocalEntitiesTableTableManager get localEntities =>
      $$LocalEntitiesTableTableManager(_db.attachedDatabase, _db.localEntities);
}
