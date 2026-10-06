import 'package:flutter/material.dart';
import '../../domain/models/asset_model.dart';
import '../controllers/asset_controller.dart';
import '../widgets/asset_form_widget.dart';
import '../widgets/sync_status_badge.dart';

class AssetDetailScreen extends StatelessWidget {
  final String assetId;
  final AssetController controller;

  const AssetDetailScreen({
    super.key,
    required this.assetId,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AssetModel>>(
      valueListenable: controller.assetsNotifier,
      builder: (context, assets, _) {
        final assetMatches = assets.where((a) => a.id == assetId);
        if (assetMatches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalhes do Ativo')),
            body: const Center(child: Text('Ativo não encontrado ou removido.')),
          );
        }

        final asset = assetMatches.first;

        return Scaffold(
          appBar: AppBar(
            title: Text(asset.name),
            actions: [
              IconButton(
                key: const Key('detail_edit_button'),
                icon: const Icon(Icons.edit),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AssetFormWidget(
                      initialAsset: asset,
                      onSave: (name, desc) {
                        controller.saveAsset(
                          id: asset.id,
                          name: name,
                          description: desc,
                        );
                      },
                    ),
                  );
                },
              ),
              IconButton(
                key: const Key('detail_delete_button'),
                icon: const Icon(Icons.delete),
                onPressed: () {
                  controller.deleteAsset(asset.id);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ID: ${asset.id}', style: Theme.of(context).textTheme.bodySmall),
                    SyncStatusBadge(status: asset.syncStatus),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Descrição:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(asset.description, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                Text(
                  'Última Modificação: ${asset.updatedAt.toIso8601String()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
