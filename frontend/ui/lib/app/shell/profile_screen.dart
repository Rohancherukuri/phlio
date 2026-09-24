// A minimal profile screen: current user's identity plus a logout action.
// Editing a profile, followers/following, and a personal post grid are
// real features left for a later build stage — see the note in
// `activity_placeholder_screen.dart`, the same reasoning applies here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_button.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Profile', style: PhlioTypography.displayMedium)),
      body: user == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        PhlioAvatar(name: user.fullName, size: 88),
                        const SizedBox(height: PhlioSpacing.md),
                        Text(user.fullName, style: PhlioTypography.headline),
                        Text('@${user.username}', style: PhlioTypography.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.xl),
                  PhlioCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About', style: PhlioTypography.bodyStrong),
                        const SizedBox(height: PhlioSpacing.xs),
                        Text(
                          user.bio.isEmpty ? 'No bio yet.' : user.bio,
                          style: PhlioTypography.body,
                        ),
                        if (user.interests.isNotEmpty) ...[
                          const SizedBox(height: PhlioSpacing.md),
                          Wrap(
                            spacing: PhlioSpacing.xs,
                            runSpacing: PhlioSpacing.xs,
                            children: user.interests
                                .map((i) => Chip(
                                      label: Text(i, style: PhlioTypography.caption),
                                      backgroundColor: PhlioColors.surfaceElevated,
                                      side: BorderSide.none,
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  PhlioSecondaryButton(
                    label: 'Log out',
                    onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
    );
  }
}
