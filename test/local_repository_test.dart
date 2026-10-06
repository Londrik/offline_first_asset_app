import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/database/app_database.dart';
import 'package:offline_first_asset_app/database/local_repository_facade.dart';

void main() {
  late AppDatabase db;
  late LocalRepositoryFacade repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LocalRepositoryFacade(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Deve executar escrita dupla atomica: Atualizar Assets e gravar PendingMutations', () async {
    const assetId = 'e01a8f98-90dc-4f6c-8438-fb36214771e8';
    
    await repository.optimisticUpsertAsset(
      id: assetId,
      assetTag: 'TAG-1001',
      name: 'Bomba Hidraulica',
      status: 'OPERATIONAL',
      baseVersion: 1,
      action: 'UPDATE',
    );

    final asset = await repository.getAssetById(assetId);
    expect(asset, isNotNull);
    expect(asset!.name, equals('Bomba Hidraulica'));
    expect(asset.syncStatus, equals('DIRTY'));

    final mutations = await repository.getPendingMutationsFifo();
    expect(mutations.length, equals(1));
    expect(mutations.first.aggregateId, equals(assetId));
    expect(mutations.first.action, equals('UPDATE'));
    expect(mutations.first.retryCount, equals(0));
  });
}
