// Phlio design system — top app bar.

import 'package:flutter/material.dart';
import '../colors.dart';
import '../typography.dart';

class PhlioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PhlioAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions = const [],
    this.centerTitle = false,
  });

  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: PhlioColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: centerTitle,
      leading: leading,
      title: title != null ? Text(title!, style: PhlioTypography.headline) : null,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
