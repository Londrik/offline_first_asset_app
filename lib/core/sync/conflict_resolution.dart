enum ConflictResolutionStrategy { lastWriteWins, fieldLevelMerge }

class ConflictResolutionResult {
  final Map<String, dynamic> resolvedPayload;
  final int resolvedVersion;
  final bool requiresUserIntervention;

  const ConflictResolutionResult({
    required this.resolvedPayload,
    required this.resolvedVersion,
    this.requiresUserIntervention = false,
  });
}

abstract class ConflictResolver {
  ConflictResolutionResult resolve({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> serverPayload,
    required DateTime localTimestamp,
    required DateTime serverTimestamp,
    required int baseVersion,
    required int serverVersion,
  });
}

class LastWriteWinsResolver implements ConflictResolver {
  @override
  ConflictResolutionResult resolve({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> serverPayload,
    required DateTime localTimestamp,
    required DateTime serverTimestamp,
    required int baseVersion,
    required int serverVersion,
  }) {
    // Se o cliente alterou mais recentemente ou no mesmo instante, o write local prevalece
    final bool clientWins = localTimestamp.isAfter(serverTimestamp) ||
        localTimestamp.isAtSameMomentAs(serverTimestamp);

    if (clientWins) {
      return ConflictResolutionResult(
        resolvedPayload: Map<String, dynamic>.from(localPayload),
        resolvedVersion: serverVersion + 1,
        requiresUserIntervention: false,
      );
    } else {
      return ConflictResolutionResult(
        resolvedPayload: Map<String, dynamic>.from(serverPayload),
        resolvedVersion: serverVersion,
        requiresUserIntervention: false,
      );
    }
  }
}

class FieldLevelMergeResolver implements ConflictResolver {
  @override
  ConflictResolutionResult resolve({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> serverPayload,
    required DateTime localTimestamp,
    required DateTime serverTimestamp,
    required int baseVersion,
    required int serverVersion,
  }) {
    final merged = Map<String, dynamic>.from(serverPayload);
    bool hasDirectSemanticConflict = false;

    for (final key in localPayload.keys) {
      if (serverPayload.containsKey(key)) {
        if (serverPayload[key] != localPayload[key]) {
          if (localTimestamp.isAfter(serverTimestamp)) {
            merged[key] = localPayload[key];
          } else {
            merged[key] = serverPayload[key];
          }
        }
      } else {
        merged[key] = localPayload[key];
      }
    }

    return ConflictResolutionResult(
      resolvedPayload: merged,
      resolvedVersion: serverVersion + 1,
      requiresUserIntervention: hasDirectSemanticConflict,
    );
  }
}
