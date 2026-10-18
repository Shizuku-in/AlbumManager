import 'package:flutter/material.dart';

/// Top-level page with an M3 medium top app bar.
class AppPage extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> slivers;
  final ScrollController? controller;
  const AppPage({super.key, required this.title, this.actions = const [], required this.slivers, this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: controller,
        slivers: [
          SliverAppBar.medium(title: Text(title), actions: [...actions, const SizedBox(width: 12)]),
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
