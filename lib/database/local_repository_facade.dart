import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

class LocalRepositoryFacade {
  final AppDatabase db;
  final Uuid _uuid = const Uuid();

  LocalRepositoryFacade(this.db);

  Stream<List<Asset>> watchAllAssets() {
    return db.select(db.assets).watch();
  }

  Future<Asset?> getAssetById(String id) {
    return (db.select(db.assets)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<void> optimisticUpsertAsset({
    required String id,
    required String assetTag,
    required String name,
    required String status,
    required int baseVersion,
    required String action,
  }) async {
    final now = DateTime.now().toUtc();
    final delta = jsonEncode({
      'id': id,
      'assetTag': assetTag,
      'name': name,
      'status': status,
    });

    await db.transaction(() async {
      await db.into(db.assets).insertOnConflictUpdate(
            AssetsCompanion(
              id: Value(id),
              assetTag: Value(assetTag),
              name: Value(name),
              status: Value(status),
              serverVersion: Value(baseVersion),
              localUpdatedAt: Value(now),
              syncStatus: const Value('DIRTY'),
            ),
          );

      await db.into(db.pendingMutations).insert(
            PendingMutationsCompanion(
              id: Value(_uuid.v4()),
              aggregateId: Value(id),
              aggregateType: const Value('ASSET'),
              action: Value(action),
              payload: Value(delta),
              baseVersion: Value(baseVersion),
              clientTimestamp: Value(now),
              retryCount: const Value(0),
              createdAt: Value(now),
            ),
          );
    });
  }

  Future<List<PendingMutation>> getPendingMutationsFifo() {
    return (db.select(db.pendingMutations)
          ..orderBy([
            (t) => OrderingTerm(expression: t.clientTimestamp, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.retryCount, mode: OrderingMode.asc),
          ]))
        .get();
  }
}
