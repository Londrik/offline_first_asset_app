import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/core/concurrency/sync_protocol.dart';
import 'package:offline_first_asset_app/data/sync/sync_isolate_manager.dart';

void main() {
  group('SyncIsolateManager Concurrency & Message Passing Tests', () {
    late SyncIsolateManager isolateManager;

    setUp(() async {
      isolateManager = SyncIsolateManager();
      await isolateManager.initialize();
    });

    tearDown(() async {
      await isolateManager.dispose();
    });

    test('deve inicializar o isolate e receber o handshake da porta mensageira', () {
      expect(isolateManager.isReady, isTrue);
    });

    test('deve processar compressao gzip e calculo SHA-256 no isolate sem bloquear a main thread', () async {
      final payload = {
        'id': 'asset-concurrency-01',
        'name': 'Industrial Turbine Generator',
        'description': 'Heavy machinery vibration & temperature telemetry',
        'timestamp': DateTime.now().toIso8601String(),
        'metrics': List.generate(100, (i) => {'index': i, 'val': i * 1.5}),
      };

      final expectedRawBytes = utf8.encode(jsonEncode(payload));
      final expectedChecksum = sha256.convert(expectedRawBytes).toString();
      final expectedCompressedSize = gzip.encode(expectedRawBytes).length;

      final message = SyncTaskMessage(
        taskId: 'task-test-01',
        assetId: 'asset-concurrency-01',
        action: SyncAction.upsert,
        payload: payload,
        endpoint: 'https://test.internal/sync',
      );

      final expectation = expectLater(
        isolateManager.results,
        emits(predicate<SyncTaskResult>((result) {
          return result.taskId == 'task-test-01' &&
              result.assetId == 'asset-concurrency-01' &&
              result.success == true &&
              result.statusCode == 200 &&
              result.sha256Checksum == expectedChecksum &&
              result.compressedPayloadSizeBytes == expectedCompressedSize;
        })),
      );

      await isolateManager.dispatch(message);
      await expectation;
    });

    test('deve descartar adequadamente a memoria do isolate apos dispose', () async {
      final isolatedLocalManager = SyncIsolateManager();
      await isolatedLocalManager.initialize();
      expect(isolatedLocalManager.isReady, isTrue);

      await isolatedLocalManager.dispose();
      expect(isolatedLocalManager.isReady, isFalse);
    });
  });
}
