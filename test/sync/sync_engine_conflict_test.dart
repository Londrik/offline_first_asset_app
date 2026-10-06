import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/core/sync/conflict_resolution.dart';
import 'package:offline_first_asset_app/core/sync/sync_engine.dart';
import 'package:offline_first_asset_app/database/app_database.dart';
import 'package:uuid/uuid.dart';

class MockRemoteDataSource implements SyncRemoteDataSource {
  final Map<String, SyncHttpResponse Function(Map<String, dynamic>)> handlers = {};

  @override
  Future<SyncHttpResponse> pushMutation({
    required String aggregateId,
    required String action,
    required Map<String, dynamic> payload,
    required int baseVersion,
  }) async {
    if (handlers.containsKey(aggregateId)) {
      return handlers[aggregateId]!(payload);
    }
    return const SyncHttpResponse(statusCode: 200, data: {'serverVersion': 2});
  }
}

void main() {
  late AppDatabase db;
  late MockRemoteDataSource remoteDataSource;
  const uuid = Uuid();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remoteDataSource = MockRemoteDataSource();
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncEngine & Conflict Resolution Unit Tests', () {
    test('LWW Resolver: Local wins when local timestamp is newer', () {
      final resolver = LastWriteWinsResolver();
      final now = DateTime.now();

      final result = resolver.resolve(
        localPayload: {'name': 'Turbine Alpha (Client Win)', 'status': 'OPERATIONAL'},
        serverPayload: {'name': 'Turbine Alpha (Server Old)', 'status': 'MAINTENANCE'},
        localTimestamp: now.add(const Duration(minutes: 5)),
        serverTimestamp: now,
        baseVersion: 1,
        serverVersion: 2,
      );

      expect(result.resolvedPayload['name'], equals('Turbine Alpha (Client Win)'));
      expect(result.resolvedVersion, equals(3));
      expect(result.requiresUserIntervention, isFalse);
    });

    test('LWW Resolver: Server wins when server timestamp is newer', () {
      final resolver = LastWriteWinsResolver();
      final now = DateTime.now();

      final result = resolver.resolve(
        localPayload: {'name': 'Client Change', 'status': 'OPERATIONAL'},
        serverPayload: {'name': 'Server Change', 'status': 'MAINTENANCE'},
        localTimestamp: now,
        serverTimestamp: now.add(const Duration(minutes: 5)),
        baseVersion: 1,
        serverVersion: 2,
      );

      expect(result.resolvedPayload['name'], equals('Server Change'));
      expect(result.resolvedVersion, equals(2));
      expect(result.requiresUserIntervention, isFalse);
    });

    test('FieldLevelMergeResolver: Merges non-colliding fields accurately', () {
      final resolver = FieldLevelMergeResolver();
      final now = DateTime.now();

      final result = resolver.resolve(
        localPayload: {'name': 'Local Field Name'},
        serverPayload: {'status': 'MAINTENANCE', 'name': 'Old Name'},
        localTimestamp: now.add(const Duration(seconds: 10)),
        serverTimestamp: now,
        baseVersion: 1,
        serverVersion: 2,
      );

      expect(result.resolvedPayload['name'], equals('Local Field Name'));
      expect(result.resolvedPayload['status'], equals('MAINTENANCE'));
      expect(result.resolvedVersion, equals(3));
    });

    test('SyncEngine: Processes 200 OK mutation, removes mutation and updates asset to SYNCED', () async {
      final assetId = uuid.v4();
      final now = DateTime.now().toUtc();

      await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: assetId,
          assetTag: 'TAG-001',
          name: 'Hydro Generator',
          status: 'OPERATIONAL',
          serverVersion: 1,
          localUpdatedAt: now,
          syncStatus: 'DIRTY',
        ),
      );

      await db.into(db.pendingMutations).insert(
        PendingMutationsCompanion.insert(
          id: uuid.v4(),
          aggregateId: assetId,
          aggregateType: 'ASSET',
          action: 'UPDATE',
          payload: jsonEncode({'id': assetId, 'name': 'Hydro Generator Renovated'}),
          baseVersion: 1,
          clientTimestamp: now,
          createdAt: now,
        ),
      );

      final engine = SyncEngine(db: db, remoteDataSource: remoteDataSource);
      await engine.drainPendingMutationsFifo();

      final remainingMutations = await db.select(db.pendingMutations).get();
      expect(remainingMutations, isEmpty);

      final asset = await (db.select(db.assets)..where((t) => t.id.equals(assetId))).getSingle();
      expect(asset.syncStatus, equals('SYNCED'));
      expect(asset.serverVersion, equals(2));
    });

    test('SyncEngine: Resolves HTTP 409 Conflict deterministically via LWW and updates SQLite', () async {
      final assetId = uuid.v4();
      final clientTimestamp = DateTime.now().toUtc().add(const Duration(minutes: 10));

      await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: assetId,
          assetTag: 'TAG-CONFLICT-01',
          name: 'Pressure Valve Local',
          status: 'OPERATIONAL',
          serverVersion: 1,
          localUpdatedAt: clientTimestamp,
          syncStatus: 'DIRTY',
        ),
      );

      await db.into(db.pendingMutations).insert(
        PendingMutationsCompanion.insert(
          id: uuid.v4(),
          aggregateId: assetId,
          aggregateType: 'ASSET',
          action: 'UPDATE',
          payload: jsonEncode({'id': assetId, 'name': 'Pressure Valve Local Winning'}),
          baseVersion: 1,
          clientTimestamp: clientTimestamp,
          createdAt: clientTimestamp,
        ),
      );

      remoteDataSource.handlers[assetId] = (payload) {
        return SyncHttpResponse(
          statusCode: 409,
          data: {
            'serverVersion': 3,
            'serverUpdatedAt': DateTime.now().toUtc().toIso8601String(),
            'serverPayload': {
              'id': assetId,
              'name': 'Pressure Valve Server Overridden',
              'status': 'MAINTENANCE',
            },
          },
        );
      };

      final engine = SyncEngine(db: db, remoteDataSource: remoteDataSource);
      await engine.drainPendingMutationsFifo();

      final remainingMutations = await db.select(db.pendingMutations).get();
      expect(remainingMutations, isEmpty);

      final asset = await (db.select(db.assets)..where((t) => t.id.equals(assetId))).getSingle();
      expect(asset.name, equals('Pressure Valve Local Winning'));
      expect(asset.serverVersion, equals(4));
      expect(asset.syncStatus, equals('SYNCED'));
    });

    test('SyncEngine: Increments retryCount and saves lastError on server failure (500)', () async {
      final assetId = uuid.v4();
      final now = DateTime.now().toUtc();

      await db.into(db.pendingMutations).insert(
        PendingMutationsCompanion.insert(
          id: uuid.v4(),
          aggregateId: assetId,
          aggregateType: 'ASSET',
          action: 'UPDATE',
          payload: jsonEncode({'id': assetId, 'name': 'Will Fail'}),
          baseVersion: 1,
          clientTimestamp: now,
          createdAt: now,
        ),
      );

      remoteDataSource.handlers[assetId] = (_) {
        return const SyncHttpResponse(statusCode: 500, errorMessage: 'Internal Server Error');
      };

      final engine = SyncEngine(db: db, remoteDataSource: remoteDataSource);
      await engine.drainPendingMutationsFifo();

      final mutations = await db.select(db.pendingMutations).get();
      expect(mutations.length, equals(1));
      expect(mutations.first.retryCount, equals(1));
      expect(mutations.first.lastError, contains('Internal Server Error'));
    });
  });
}
