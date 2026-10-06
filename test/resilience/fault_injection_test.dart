import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/core/resilience/backoff_calculator.dart';
import 'package:offline_first_asset_app/core/resilience/fault_injection_interceptor.dart';
import 'package:offline_first_asset_app/core/resilience/resilience_interceptor.dart';
import 'package:offline_first_asset_app/core/sync/sync_engine.dart';
import 'package:offline_first_asset_app/database/app_database.dart';
import 'package:uuid/uuid.dart';

class FaultTolerantRemoteDataSource implements SyncRemoteDataSource {
  final Dio dio;

  FaultTolerantRemoteDataSource(this.dio);

  @override
  Future<SyncHttpResponse> pushMutation({
    required String aggregateId,
    required String action,
    required Map<String, dynamic> payload,
    required int baseVersion,
  }) async {
    try {
      final response = await dio.post<dynamic>(
        '/v1/sync',
        data: payload,
      );

      if (response.data is Map<String, dynamic>) {
        return SyncHttpResponse(
          statusCode: response.statusCode ?? 200,
          data: response.data as Map<String, dynamic>,
        );
      } else {
        return const SyncHttpResponse(
          statusCode: 500,
          errorMessage: 'Malformed payload received',
        );
      }
    } on DioException catch (e) {
      return SyncHttpResponse(
        statusCode: e.response?.statusCode ?? 500,
        errorMessage: e.message ?? e.toString(),
      );
    }
  }
}

class StaticMockAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  StaticMockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('Chaos & Network Resilience Testing', () {
    late Dio dio;
    late FaultInjectionInterceptor faultInjector;
    late AppDatabase db;
    const uuid = Uuid();

    setUp(() {
      dio = Dio(BaseOptions(
        baseUrl: 'https://api.offline-asset.internal',
      ));
      faultInjector = FaultInjectionInterceptor();
      db = AppDatabase(NativeDatabase.memory());

      // ResilienceInterceptor adicionado antes para interceptar erros em onError
      dio.interceptors.add(
        ResilienceInterceptor(
          dio: dio,
          maxRetries: 2,
          sleepFunction: (_) async {},
          backoffCalculator: BackoffCalculator(
            baseDelay: const Duration(milliseconds: 10),
            maxDelay: const Duration(milliseconds: 100),
          ),
        ),
      );
      dio.interceptors.add(faultInjector);

      dio.httpClientAdapter = StaticMockAdapter((options) {
        final bodyBytes = utf8.encode(jsonEncode({'status': 'ok', 'serverVersion': 2}));
        return ResponseBody(
          Stream.value(bodyBytes),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    });

    tearDown(() async {
      dio.close(force: true);
      await db.close();
    });

    test('FaultInjection: Intercepta e simula HTTP 503 com retentativa automatica resolvida', () async {
      faultInjector.currentFault = FaultType.serviceUnavailable;
      faultInjector.faultOccurrences = 1;

      final response = await dio.post<dynamic>('/v1/sync', data: {'test': true});

      expect(response.statusCode, equals(200));
      expect(faultInjector.triggeredCount, equals(1));
    });

    test('FaultInjection: Falha sustentada esgota retentativas e preserva fila Drift sem corrupção', () async {
      faultInjector.currentFault = FaultType.networkFailure;
      faultInjector.faultOccurrences = 5;

      final assetId = uuid.v4();
      final now = DateTime.now().toUtc();

      await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: assetId,
          assetTag: 'TAG-RESILIENCE-01',
          name: 'Critical Substation Transformer',
          status: 'OPERATIONAL',
          serverVersion: 1,
          localUpdatedAt: now,
          syncStatus: 'DIRTY',
        ),
      );

      final mutationId = uuid.v4();
      await db.into(db.pendingMutations).insert(
        PendingMutationsCompanion.insert(
          id: mutationId,
          aggregateId: assetId,
          aggregateType: 'ASSET',
          action: 'UPDATE',
          payload: jsonEncode({'id': assetId, 'name': 'Renamed Under Chaos'}),
          baseVersion: 1,
          clientTimestamp: now,
          createdAt: now,
        ),
      );

      final remoteSource = FaultTolerantRemoteDataSource(dio);
      final syncEngine = SyncEngine(db: db, remoteDataSource: remoteSource);

      await syncEngine.drainPendingMutationsFifo();

      final mutations = await db.select(db.pendingMutations).get();
      expect(mutations.length, equals(1));
      expect(mutations.first.id, equals(mutationId));
      expect(mutations.first.retryCount, equals(1));
      expect(mutations.first.lastError, isNotNull);

      final asset = await (db.select(db.assets)..where((t) => t.id.equals(assetId))).getSingle();
      expect(asset.syncStatus, equals('DIRTY'));
      expect(asset.serverVersion, equals(1));
    });

    test('FaultInjection: Detecta payload corrompido e incrementa contador de falha', () async {
      faultInjector.currentFault = FaultType.corruptedPayload;
      faultInjector.faultOccurrences = 1;

      final assetId = uuid.v4();
      final now = DateTime.now().toUtc();

      await db.into(db.pendingMutations).insert(
        PendingMutationsCompanion.insert(
          id: uuid.v4(),
          aggregateId: assetId,
          aggregateType: 'ASSET',
          action: 'UPDATE',
          payload: jsonEncode({'id': assetId, 'name': 'Corrupted Stream Test'}),
          baseVersion: 1,
          clientTimestamp: now,
          createdAt: now,
        ),
      );

      final remoteSource = FaultTolerantRemoteDataSource(dio);
      final syncEngine = SyncEngine(db: db, remoteDataSource: remoteSource);

      await syncEngine.drainPendingMutationsFifo();

      final mutations = await db.select(db.pendingMutations).get();
      expect(mutations.length, equals(1));
      expect(mutations.first.lastError, contains('Malformed payload received'));
    });
  });
}
