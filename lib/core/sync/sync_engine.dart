import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'conflict_resolution.dart';

abstract class SyncRemoteDataSource {
  Future<SyncHttpResponse> pushMutation({
    required String aggregateId,
    required String action,
    required Map<String, dynamic> payload,
    required int baseVersion,
  });
}

class SyncHttpResponse {
  final int statusCode;
  final Map<String, dynamic>? data;
  final String? errorMessage;

  const SyncHttpResponse({
    required this.statusCode,
    this.data,
    this.errorMessage,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isConflict => statusCode == 409;
}

class SyncEngine {
  final AppDatabase db;
  final SyncRemoteDataSource remoteDataSource;
  final ConflictResolver conflictResolver;

  SyncEngine({
    required this.db,
    required this.remoteDataSource,
    ConflictResolver? conflictResolver,
  }) : conflictResolver = conflictResolver ?? LastWriteWinsResolver();

  Future<void> drainPendingMutationsFifo() async {
    final mutations = await (db.select(db.pendingMutations)
          ..orderBy([
            (t) => OrderingTerm(expression: t.clientTimestamp, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.retryCount, mode: OrderingMode.asc),
          ]))
        .get();

    for (final mutation in mutations) {
      await _processSingleMutation(mutation);
    }
  }

  Future<void> _processSingleMutation(PendingMutation mutation) async {
    final payloadMap = jsonDecode(mutation.payload) as Map<String, dynamic>;

    try {
      final response = await remoteDataSource.pushMutation(
        aggregateId: mutation.aggregateId,
        action: mutation.action,
        payload: payloadMap,
        baseVersion: mutation.baseVersion,
      );

      if (response.isSuccess) {
        await _handleSuccess(mutation, response.data);
      } else if (response.isConflict) {
        await _handleConflict(mutation, payloadMap, response.data);
      } else {
        await _handleFailure(mutation, response.errorMessage ?? 'Status code: ${response.statusCode}');
      }
    } catch (e) {
      await _handleFailure(mutation, e.toString());
    }
  }

  Future<void> _handleSuccess(PendingMutation mutation, Map<String, dynamic>? responseData) async {
    final newVersion = (responseData?['serverVersion'] as int?) ?? (mutation.baseVersion + 1);

    await db.transaction(() async {
      // 1. Remove mutacao processada
      await (db.delete(db.pendingMutations)..where((t) => t.id.equals(mutation.id))).go();

      // 2. Atualiza asset para SYNCED
      await (db.update(db.assets)..where((t) => t.id.equals(mutation.aggregateId))).write(
        AssetsCompanion(
          serverVersion: Value(newVersion),
          syncStatus: const Value('SYNCED'),
          localUpdatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<void> _handleConflict(
    PendingMutation mutation,
    Map<String, dynamic> localPayload,
    Map<String, dynamic>? conflictData,
  ) async {
    final serverPayload = Map<String, dynamic>.from(conflictData?['serverPayload'] ?? {});
    final serverVersion = (conflictData?['serverVersion'] as int?) ?? (mutation.baseVersion + 1);
    final serverUpdatedAtStr = conflictData?['serverUpdatedAt'] as String?;
    final serverTimestamp = serverUpdatedAtStr != null
        ? DateTime.parse(serverUpdatedAtStr)
        : DateTime.now().toUtc();

    final resolution = conflictResolver.resolve(
      localPayload: localPayload,
      serverPayload: serverPayload,
      localTimestamp: mutation.clientTimestamp,
      serverTimestamp: serverTimestamp,
      baseVersion: mutation.baseVersion,
      serverVersion: serverVersion,
    );

    await db.transaction(() async {
      // 1. Remove a mutacao que colidiu
      await (db.delete(db.pendingMutations)..where((t) => t.id.equals(mutation.id))).go();

      // 2. Aplica resolucao deterministica
      final resolvedStatus = resolution.requiresUserIntervention ? 'CONFLICT' : 'SYNCED';

      await (db.update(db.assets)..where((t) => t.id.equals(mutation.aggregateId))).write(
        AssetsCompanion(
          name: resolution.resolvedPayload['name'] != null
              ? Value(resolution.resolvedPayload['name'] as String)
              : const Value.absent(),
          status: resolution.resolvedPayload['status'] != null
              ? Value(resolution.resolvedPayload['status'] as String)
              : const Value.absent(),
          serverVersion: Value(resolution.resolvedVersion),
          syncStatus: Value(resolvedStatus),
          localUpdatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<void> _handleFailure(PendingMutation mutation, String errorMessage) async {
    await (db.update(db.pendingMutations)..where((t) => t.id.equals(mutation.id))).write(
      PendingMutationsCompanion(
        retryCount: Value(mutation.retryCount + 1),
        lastError: Value(errorMessage),
      ),
    );
  }
}
