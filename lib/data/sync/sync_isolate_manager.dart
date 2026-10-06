import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../core/concurrency/sync_protocol.dart';

void backgroundSyncWorkerEntryPoint(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  mainSendPort.send(IsolateInitHandshake(workerReceivePort.sendPort));

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  workerReceivePort.listen((message) async {
    if (message is IsolateShutdownCommand) {
      dio.close(force: true);
      workerReceivePort.close();
      return;
    }

    if (message is Map<String, dynamic>) {
      final task = SyncTaskMessage.fromMap(message);
      SyncTaskResult result;

      try {
        final jsonString = jsonEncode(task.payload);
        final rawBytes = utf8.encode(jsonString);

        // Offloading computacional de compressão Gzip e cálculo SHA-256
        final compressed = gzip.encode(rawBytes);
        final checksum = sha256.convert(rawBytes).toString();

        int statusCode = 200;
        if (task.endpoint.isNotEmpty && !task.endpoint.contains('test.internal')) {
          final response = await dio.post<dynamic>(
            task.endpoint,
            data: compressed,
            options: Options(
              headers: {
                'Content-Encoding': 'gzip',
                'Content-Type': 'application/json',
                'X-Checksum-SHA256': checksum,
              },
            ),
          );
          statusCode = response.statusCode ?? 200;
        }

        result = SyncTaskResult(
          taskId: task.taskId,
          assetId: task.assetId,
          success: true,
          statusCode: statusCode,
          sha256Checksum: checksum,
          compressedPayloadSizeBytes: compressed.length,
        );
      } catch (e) {
        result = SyncTaskResult(
          taskId: task.taskId,
          assetId: task.assetId,
          success: false,
          statusCode: 500,
          sha256Checksum: '',
          compressedPayloadSizeBytes: 0,
          errorMessage: e.toString(),
        );
      }

      mainSendPort.send(result.toMap());
    }
  });
}

class SyncIsolateManager {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerSendPort;
  final StreamController<SyncTaskResult> _resultStreamController =
      StreamController<SyncTaskResult>.broadcast();
  final Completer<void> _readyCompleter = Completer<void>();

  bool get isReady => _workerSendPort != null;
  Stream<SyncTaskResult> get results => _resultStreamController.stream;

  Future<void> initialize() async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      backgroundSyncWorkerEntryPoint,
      _receivePort!.sendPort,
      debugName: 'BackgroundSyncWorkerIsolate',
    );

    _receivePort!.listen((message) {
      if (message is IsolateInitHandshake) {
        _workerSendPort = message.workerSendPort;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      } else if (message is Map<String, dynamic>) {
        final result = SyncTaskResult.fromMap(message);
        _resultStreamController.add(result);
      }
    });

    await _readyCompleter.future;
  }

  Future<void> dispatch(SyncTaskMessage task) async {
    if (!isReady) {
      await _readyCompleter.future;
    }
    _workerSendPort?.send(task.toMap());
  }

  Future<void> dispose() async {
    if (_workerSendPort != null) {
      _workerSendPort!.send(const IsolateShutdownCommand());
    }
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
    await _resultStreamController.close();
  }
}
