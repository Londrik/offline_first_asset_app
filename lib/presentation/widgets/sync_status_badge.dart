import 'package:flutter/material.dart';
import '../../domain/models/asset_model.dart';

class SyncStatusBadge extends StatelessWidget {
  final SyncStatus status;

  const SyncStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    final String label;

    switch (status) {
      case SyncStatus.synced:
        badgeColor = Colors.green;
        label = 'SYNCED';
        break;
      case SyncStatus.dirty:
        badgeColor = Colors.amber.shade800;
        label = 'DIRTY';
        break;
      case SyncStatus.conflict:
        badgeColor = Colors.red;
        label = 'CONFLICT';
        break;
    }

    return Container(
      key: Key('sync_badge_${status.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
