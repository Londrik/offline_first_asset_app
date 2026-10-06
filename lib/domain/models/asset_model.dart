enum SyncStatus { synced, dirty, conflict }

class AssetModel {
  final String id;
  final String name;
  final String description;
  final SyncStatus syncStatus;
  final DateTime updatedAt;

  const AssetModel({
    required this.id,
    required this.name,
    required this.description,
    required this.syncStatus,
    required this.updatedAt,
  });

  AssetModel copyWith({
    String? id,
    String? name,
    String? description,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return AssetModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
