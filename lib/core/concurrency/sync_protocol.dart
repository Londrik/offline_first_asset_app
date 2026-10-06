import 'dart:isolate';

enum SyncAction { upsert, delete }

class SyncTaskMessage {
  final String taskId;
  final String assetId;
  final SyncAction action;
  final Map<String, dynamic> payload;
  final String endpoint;

  const SyncTaskMessage({
    required this.taskId,
    required this.assetId,
    required this.action,
    required this.payload,
    required this.endpoint,
  });

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'assetId': assetId,
        'action': action.name,
        'payload': payload,
        'endpoint': endpoint,
      };

  factory SyncTaskMessage.fromMap(Map<String, dynamic> map) {
    return SyncTaskMessage(
      taskId: map['taskId'] as String,
      assetId: map['assetId'] as String,
      action: SyncAction.values.byName(map['action'] as String),
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      endpoint: map['endpoint'] as String,
    );
  }
}

class SyncTaskResult {
  final String taskId;
  final String assetId;
  final bool success;
  final int statusCode;
  final String sha256Checksum;
  final int compressedPayloadSizeBytes;
  final String? errorMessage;

  const SyncTaskResult({
    required this.taskId,
    required this.assetId,
    required this.success,
    required this.statusCode,
    required this.sha256Checksum,
    required this.compressedPayloadSizeBytes,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'assetId': assetId,
        'success': success,
        'statusCode': statusCode,
        'sha256Checksum': sha256Checksum,
        'compressedPayloadSizeBytes': compressedPayloadSizeBytes,
        'errorMessage': errorMessage,
      };

  factory SyncTaskResult.fromMap(Map<String, dynamic> map) {
    return SyncTaskResult(
      taskId: map['taskId'] as String,
      assetId: map['assetId'] as String,
      success: map['success'] as bool,
      statusCode: map['statusCode'] as int,
      sha256Checksum: map['sha256Checksum'] as String,
      compressedPayloadSizeBytes: map['compressedPayloadSizeBytes'] as int,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

class IsolateInitHandshake {
  final SendPort workerSendPort;
  const IsolateInitHandshake(this.workerSendPort);
}

class IsolateShutdownCommand {
  const IsolateShutdownCommand();
}
