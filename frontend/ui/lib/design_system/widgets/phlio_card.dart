import '../../app/config/app_config.dart';
// Phlio design system — cards and avatars.
//
// [PhlioCard] is the one surface elevation the whole app uses for grouped
// content (post cards, room list rows, product cards, plan items). Keeping
// a single implementation — rather than each feature rolling its own
// `Container` + `BoxDecoration` — is what keeps radius/border/padding
// consistent across five different feature teams' screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../colors.dart';
import '../radii.dart';
import '../spacing.dart';
import '../typography.dart';

class PhlioCard extends StatelessWidget {
  const PhlioCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(PhlioSpacing.lg),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? PhlioColors.surface,
        borderRadius: PhlioRadii.xlRadius,
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: PhlioRadii.xlRadius,
      child: InkWell(
        borderRadius: PhlioRadii.xlRadius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A circular avatar with a deterministic gradient background and initial,
/// used whenever a user has no `avatar_url` yet (which is every seeded
/// user in this build stage) — this keeps the UI feeling designed rather
/// than showing a generic grey-circle placeholder everywhere.
class PhlioAvatar extends StatelessWidget {
  const PhlioAvatar({
    required this.name,
    super.key,
    this.imageUrl,
    this.profileId,
    this.size = 40,
  });

  final String name;
  final String? imageUrl;

  /// Stable user ID or handle, never a display name.
  final String? profileId;
  final double size;

  // A small, fixed palette of gradient pairs, picked by a hash of the
  // name so the same person always gets the same colors across the app
  // without needing to store a color choice server-side.
  static const List<List<Color>> _palettes = [
    [PhlioColors.brandBlue, PhlioColors.brandPurple],
    [PhlioColors.brandPurple, PhlioColors.brandPink],
    [PhlioColors.brandPink, PhlioColors.brandOrange],
    [PhlioColors.domainRooms, PhlioColors.brandBlue],
    [PhlioColors.domainNews, PhlioColors.domainRooms],
  ];

  @override
  Widget build(BuildContext context) {
    final avatar = _picture();
    if (profileId == null || profileId!.isEmpty) return avatar;
    return Semantics(
      button: true,
      label: 'View $name profile',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () =>
            context.push('/creator/${Uri.encodeComponent(profileId!)}'),
        child: avatar,
      ),
    );
  }

  Widget _picture() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          AppConfig.mediaUrl(imageUrl!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    final palette = _palettes[name.hashCode.abs() % _palettes.length];
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: palette,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: PhlioTypography.bodyStrong
            .copyWith(fontSize: size * 0.4, color: Colors.white),
      ),
    );
  }
}

/// A left-title / right-action row used above nearly every horizontal list
/// in the app ("For you", "Upcoming plan", "Featured creators" — see the
/// reference Home and Shop screens).
class PhlioSectionHeader extends StatelessWidget {
  const PhlioSectionHeader({
    required this.title,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: PhlioTypography.headline),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: PhlioTypography.label
                  .copyWith(color: PhlioColors.brandPurple),
            ),
          ),
      ],
    );
  }
}
