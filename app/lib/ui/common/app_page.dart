import 'package:flutter/material.dart';

import 'package:album_manager/ui/common/collapsing_app_bar.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';

/// Top-level page with an collapsing M3 medium top app bar and smooth wheel scrolling.
class AppPage extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> slivers;
  const AppPage({
    super.key,
    required this.title,
    this.actions = const [],
    required this.slivers,
  });

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          collapsingAppBar(
            title: Text(widget.title),
            actions: [...widget.actions, const SizedBox(width: 12)],
          ),
          ...widget.slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
