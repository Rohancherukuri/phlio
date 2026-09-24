// A minimal placeholder for the Activity tab.
//
// Notifications/activity aggregation (likes, comments, room invites, agent
// plan updates) is real product surface area that deserves its own
// backend endpoint and domain design rather than a rushed addition here —
// left for a future build stage. This screen is honest about that instead
// of silently omitting the tab the reference UI shows.

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

class ActivityPlaceholderScreen extends StatelessWidget {
  const ActivityPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Activity', style: PhlioTypography.displayMedium)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(PhlioSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_none_rounded, size: 40, color: PhlioColors.textMuted),
              const SizedBox(height: PhlioSpacing.lg),
              Text('Nothing here yet', style: PhlioTypography.headline),
              const SizedBox(height: PhlioSpacing.xs),
              Text(
                'Likes, comments, and room activity will show up here.',
                textAlign: TextAlign.center,
                style: PhlioTypography.body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
