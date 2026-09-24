// The persistent app chrome: bottom navigation wrapping Home, Explore
// (mapped to Rooms discovery — the closest fit among features built in
// this stage; see the router doc-comment for the reasoning), Activity, and
// Profile. Social and Art are reached from Home's quick actions/links as
// their own full-screen destinations rather than bottom-nav tabs — see
// `app/router/app_router.dart` for why.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/widgets/phlio_bottom_nav.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  // static const _tabPaths = ['/home', '/rooms', '/activity', '/profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: PhlioBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        onCreateTap: () => _showCreateSheet(context),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('New post'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/social');
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('New room'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/rooms');
              },
            ),
          ],
        ),
      ),
    );
  }
}
