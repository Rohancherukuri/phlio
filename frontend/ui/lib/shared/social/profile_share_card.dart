// A shared profile in a chat: `phlio://profile/<username>` renders as a
// card with the person's look (their profile background / wallpaper /
// effect), avatar, name, a lock for private accounts and a View profile
// button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/profile/presentation/widgets/profile_posts.dart'
    show publicProfileProvider;
import '../appearance/appearance.dart';

final _profileLink = RegExp(r'phlio://profile/([A-Za-z0-9_.\-%]+)');

/// The username of the first shared profile link in [text], if any.
String? sharedProfileName(String? text) {
  final match = _profileLink.firstMatch(text ?? '');
  if (match == null) return null;
  try {
    return Uri.decodeComponent(match[1]!);
  } on ArgumentError {
    return match[1];
  }
}

class ProfileShareCard extends ConsumerWidget {
  const ProfileShareCard({required this.username, required this.mine, super.key});
  final String username;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(username)).valueOrNull;
    final look =
        ref.watch(userAppearanceProvider(username)).valueOrNull ?? Appearance.plain;
    final name = profile?['full_name'] as String? ?? username;
    final followers = profile?['followers'] as int?;
    final isPrivate = profile?['is_private'] == true;
    final width = MediaQuery.sizeOf(context).width * 0.66;
    return GestureDetector(
      onTap: () => context.push('/creator/${Uri.encodeComponent(username)}'),
      child: Container(
        width: width.clamp(200.0, 264.0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: PhlioColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PhlioColors.borderSubtle),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 120,
            child: AppearanceBackdrop(
              appearance: look,
              decorate: false,
              fallback: PhlioColors.surfaceElevated,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      gradient: PhlioColors.sunsetGradient,
                      shape: BoxShape.circle),
                  child: PhlioAvatar(
                      name: name,
                      imageUrl: profile?['avatar_url'] as String?,
                      size: 72),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.bodyStrong),
                ),
                if (profile?['is_verified'] == true) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded,
                      size: 14, color: PhlioColors.brandViolet),
                ],
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (isPrivate) ...[
                  const Icon(Icons.lock_rounded,
                      size: 12, color: PhlioColors.textMuted),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    '@$username${followers == null ? '' : ' · $followers followers'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.caption,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('View profile', style: PhlioTypography.bodyStrong),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
