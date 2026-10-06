import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/repositories/local_repository_facade.dart';
import '../../domain/models/asset_model.dart';

class AssetController {
  final LocalRepositoryFacade _repository;
  StreamSubscription<List<AssetModel>>? _subscription;

  late final ValueNotifier<List<AssetModel>> assetsNotifier;

  AssetController({required LocalRepositoryFacade repository}) : _repository = repository {
    assetsNotifier = ValueNotifier<List<AssetModel>>(_repository.currentAssets);
    _init();
  }

  void _init() {
    _subscription = _repository.watchAssets().listen((data) {
      assetsNotifier.value = data;
    });
  }

  Future<void> saveAsset({
    required String id,
    required String name,
    required String description,
  }) async {
    final asset = AssetModel(
      id: id,
      name: name,
      description: description,
      syncStatus: SyncStatus.dirty,
      updatedAt: DateTime.now(),
    );
    await _repository.saveAssetOptimistic(asset);
  }

  Future<void> deleteAsset(String id) async {
    await _repository.deleteAssetOptimistic(id);
  }

  void dispose() {
    _subscription?.cancel();
    assetsNotifier.dispose();
  }
}
