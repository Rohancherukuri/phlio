// A consistent "something went wrong, here's why, try again" view for
// whenever a `Result` resolves to a `Failure` on a full-screen load —
// list/feed-level errors are usually better shown as a `SnackBar` instead
// (see `shared/widgets/error_snackbar.dart`), but a first load with
// nothing to show yet needs a dedicated state.

import 'package:flutter/material.dart';
import '../../core/result/result.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_button.dart';

class PhlioErrorView extends StatelessWidget {
  const PhlioErrorView({required this.failure, super.key, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PhlioSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: PhlioColors.textMuted),
            const SizedBox(height: PhlioSpacing.lg),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: PhlioTypography.body,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: PhlioSpacing.lg),
              PhlioSecondaryButton(label: 'Try again', expand: false, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
