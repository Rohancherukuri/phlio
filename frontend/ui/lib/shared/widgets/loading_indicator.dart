// A single, consistent loading spinner used across every feature instead
// of each screen instantiating its own `CircularProgressIndicator` with
// slightly different sizing/coloring.

import 'package:flutter/material.dart';
import '../../design_system/colors.dart';

class PhlioLoadingIndicator extends StatelessWidget {
  const PhlioLoadingIndicator({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          strokeWidth: 2.6,
          valueColor: AlwaysStoppedAnimation(PhlioColors.brandPurple),
        ),
      ),
    );
  }
}
