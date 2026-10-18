import 'package:flutter/material.dart';

import 'package:album_manager/theme/app_colors.dart';

/// Compact non-interactive label on a custom-color container (M3 badge-like label).
class ToneLabel extends StatelessWidget {
  final String text;
  final CustomColor tone;
  final IconData? icon;
  const ToneLabel(this.text, {super.key, required this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: tone.onContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.container, borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: tone.onContainer), const SizedBox(width: 4)],
        Text(text, style: style),
      ]),
    );
  }
}
