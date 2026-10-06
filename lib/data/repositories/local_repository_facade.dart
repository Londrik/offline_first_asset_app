import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/asset_model.dart';

abstract class LocalRepositoryFacade {
  List<AssetModel> get currentAssets;
  Stream<List<AssetModel>> watchAssets();
  Future<void> saveAssetOptimistic(AssetModel asset);
  Future<void> deleteAssetOptimistic(String assetId);
}

class InMemoryLocalRepositoryFacade implements LocalRepositoryFacade {
  late final StreamController<List<AssetModel>> _assetsStreamController;
  final List<AssetModel> _storage = [];

  InMemoryLocalRepositoryFacade([List<AssetModel>? initialData]) {
    if (initialData != null) {
      _storage.addAll(initialData);
    }
    _assetsStreamController = StreamController<List<AssetModel>>.broadcast(
      onListen: () {
        _emit();
      },
    );
  }

  @override
  List<AssetModel> get currentAssets => List.unmodifiable(_storage);

  void _emit() {
    if (!_assetsStreamController.isClosed) {
      _assetsStreamController.add(List.unmodifiable(_storage));
    }
  }

  @override
  Stream<List<AssetModel>> watchAssets() {
    return _assetsStreamController.stream;
  }

  @override
  Future<void> saveAssetOptimistic(AssetModel asset) async {
    final index = _storage.indexWhere((a) => a.id == asset.id);
    final optimisticAsset = asset.copyWith(syncStatus: SyncStatus.dirty);

    if (index >= 0) {
      _storage[index] = optimisticAsset;
    } else {
      _storage.add(optimisticAsset);
    }
    _emit();
  }

  @override
  Future<void> deleteAssetOptimistic(String assetId) async {
    _storage.removeWhere((a) => a.id == assetId);
    _emit();
  }

  @visibleForTesting
  void markAsSynced(String assetId) {
    final index = _storage.indexWhere((a) => a.id == assetId);
    if (index >= 0) {
      _storage[index] = _storage[index].copyWith(syncStatus: SyncStatus.synced);
      _emit();
    }
  }

  void dispose() {
    _assetsStreamController.close();
  }
}
