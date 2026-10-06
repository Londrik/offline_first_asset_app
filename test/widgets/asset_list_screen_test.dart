import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/data/repositories/local_repository_facade.dart';
import 'package:offline_first_asset_app/domain/models/asset_model.dart';
import 'package:offline_first_asset_app/presentation/controllers/asset_controller.dart';
import 'package:offline_first_asset_app/presentation/screens/asset_list_screen.dart';

void main() {
  group('Optimistic UI & AssetListScreen Tests', () {
    late InMemoryLocalRepositoryFacade repository;
    late AssetController controller;

    setUp(() {
      repository = InMemoryLocalRepositoryFacade();
      controller = AssetController(repository: repository);
    });

    tearDown(() {
      controller.dispose();
      repository.dispose();
    });

    testWidgets('exibe tela vazia inicial e reage imediatamente ao cadastro otimista com DIRTY', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AssetListScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('empty_state_text')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_asset_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('asset_form_name_field')), 'Gerador 500kVA');
      await tester.enterText(find.byKey(const Key('asset_form_desc_field')), 'Setor de Emergência');
      await tester.tap(find.byKey(const Key('asset_form_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Gerador 500kVA'), findsOneWidget);
      expect(find.text('Setor de Emergência'), findsOneWidget);
      expect(find.text('DIRTY'), findsOneWidget);
      expect(find.byKey(const Key('sync_badge_dirty')), findsOneWidget);
    });

    testWidgets('transita status visual de DIRTY para SYNCED de forma reativa', (tester) async {
      final initialAsset = AssetModel(
        id: 'asset-100',
        name: 'Bomba Centrífuga',
        description: 'Circuito Primário',
        syncStatus: SyncStatus.dirty,
        updatedAt: DateTime.now(),
      );

      final repoWithItem = InMemoryLocalRepositoryFacade([initialAsset]);
      final activeController = AssetController(repository: repoWithItem);

      await tester.pumpWidget(
        MaterialApp(
          home: AssetListScreen(controller: activeController),
        ),
      );
      await tester.pump();

      expect(find.text('DIRTY'), findsOneWidget);
      expect(find.text('SYNCED'), findsNothing);

      repoWithItem.markAsSynced('asset-100');
      await tester.pumpAndSettle();

      expect(find.text('DIRTY'), findsNothing);
      expect(find.text('SYNCED'), findsOneWidget);

      activeController.dispose();
      repoWithItem.dispose();
    });

    testWidgets('remove item da tela instantaneamente em delete otimista', (tester) async {
      final initialAsset = AssetModel(
        id: 'asset-200',
        name: 'Compressor de Ar',
        description: 'Linha A',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime.now(),
      );

      final repoWithItem = InMemoryLocalRepositoryFacade([initialAsset]);
      final activeController = AssetController(repository: repoWithItem);

      await tester.pumpWidget(
        MaterialApp(
          home: AssetListScreen(controller: activeController),
        ),
      );
      await tester.pump();

      expect(find.text('Compressor de Ar'), findsOneWidget);

      await activeController.deleteAsset('asset-200');
      await tester.pumpAndSettle();

      expect(find.text('Compressor de Ar'), findsNothing);
      expect(find.byKey(const Key('empty_state_text')), findsOneWidget);

      activeController.dispose();
      repoWithItem.dispose();
    });
  });
}
