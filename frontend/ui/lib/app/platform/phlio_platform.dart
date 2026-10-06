// Phlio platforms — the app-tray navigation model.
//
// Phlio is a super-app of eight platforms (blueprint section 3). The bottom
// nav is Home / Explore / (+) / Profile / Tray; the Tray opens a sheet of
// platform symbols and switching platform re-skins the Home and Explore
// tabs (and defaults the Activity filter) while Profile stays shared.
// Platform state lives in a plain Riverpod `StateProvider` — it survives
// tab switches inside the shell but intentionally resets on app restart
// (each session starts on Social, the product's front door).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/colors.dart';

enum PhlioPlatform {
  pay('Pay', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
  social('Social', Icons.groups_outlined, Icons.groups_rounded),
  rooms('Rooms', Icons.forum_outlined, Icons.forum_rounded),
  book('Book', Icons.confirmation_number_outlined, Icons.confirmation_number_rounded),
  shop('Shop', Icons.storefront_outlined, Icons.storefront_rounded),
  stream('Stream', Icons.play_circle_outline_rounded, Icons.play_circle_rounded),
  news('News', Icons.article_outlined, Icons.article_rounded),
  agent('Agent', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded);

  const PhlioPlatform(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// The domain accent color used across the tray, home grid and explore.
  Color get color => switch (this) {
        PhlioPlatform.pay => PhlioColors.domainPay,
        PhlioPlatform.social => PhlioColors.domainSocial,
        PhlioPlatform.rooms => PhlioColors.domainRooms,
        PhlioPlatform.book => PhlioColors.domainBook,
        PhlioPlatform.shop => PhlioColors.domainShop,
        PhlioPlatform.stream => PhlioColors.domainStream,
        PhlioPlatform.news => PhlioColors.domainNews,
        PhlioPlatform.agent => PhlioColors.brandOrange,
      };

  /// Stream and News are roadmap platforms (no backend domain yet) — the
  /// app still switches to them and shows an honest "coming soon" surface.
  bool get isAvailable => switch (this) {
        PhlioPlatform.stream || PhlioPlatform.news => false,
        _ => true,
      };
}

/// The platform the shell is currently showing. Defaults to Social —
/// Phlio's front door — on every fresh launch.
final currentPlatformProvider =
    StateProvider<PhlioPlatform>((ref) => PhlioPlatform.social);
