import 'package:flutter/material.dart';
import '../../domain/models/asset_model.dart';
import '../controllers/asset_controller.dart';
import '../widgets/asset_form_widget.dart';
import '../widgets/sync_status_badge.dart';
import 'asset_detail_screen.dart';

class AssetListScreen extends StatelessWidget {
  final AssetController controller;

  const AssetListScreen({super.key, required this.controller});

  void _openCreateModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AssetFormWidget(
        onSave: (name, desc) {
          final newId = DateTime.now().millisecondsSinceEpoch.toString();
          controller.saveAsset(id: newId, name: name, description: desc);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ativos (Offline-First)'),
      ),
      body: ValueListenableBuilder<List<AssetModel>>(
        valueListenable: controller.assetsNotifier,
        builder: (context, assets, _) {
          if (assets.isEmpty) {
            return const Center(
              key: Key('empty_state_text'),
              child: Text('Nenhum ativo cadastrado.'),
            );
          }

          return ListView.separated(
            itemCount: assets.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final asset = assets[index];
              return Dismissible(
                key: Key('dismissible_${asset.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  controller.deleteAsset(asset.id);
                },
                child: ListTile(
                  key: Key('asset_tile_${asset.id}'),
                  title: Text(asset.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(asset.description),
                  trailing: SyncStatusBadge(status: asset.syncStatus),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AssetDetailScreen(
                          assetId: asset.id,
                          controller: controller,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_asset_fab'),
        onPressed: () => _openCreateModal(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
