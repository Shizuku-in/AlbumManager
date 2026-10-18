import 'package:flutter/material.dart';

/// Centered icon + message for an empty tab.
Widget emptySliver(BuildContext context, IconData icon, String text) {
  final t = Theme.of(context);
  return SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(children: [
        Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(text, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    ),
  );
}
