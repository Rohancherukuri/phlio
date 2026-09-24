// Shimmer loading skeletons.
//
// A hand-rolled shimmer (an `AnimationController` sweeping a gradient
// across a `ShaderMask`) rather than the `shimmer` pub package — the
// effect is genuinely this simple, and one fewer dependency to track is a
// fair trade for ~40 lines of animation code the team already owns and
// can tune freely (this is exactly the kind of "well defined animation"
// worth writing by hand rather than reaching for a package).
//
// Used wherever a list/grid's *shape* is predictable before the data
// arrives (the shop grid, featured sellers row) — replacing a bare
// spinner with a skeleton that already looks like the real content
// reduces perceived load time and avoids the whole screen "popping" once
// data resolves.

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/spacing.dart';

/// Wraps [child] with a moving highlight sweep. If no [child] is given,
/// renders a plain rounded rectangle of [width]x[height] — the common case
/// for a skeleton placeholder.
class PhlioShimmer extends StatefulWidget {
  const PhlioShimmer(
      {super.key, this.child, this.width, this.height, this.borderRadius});

  final Widget? child;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<PhlioShimmer> createState() => _PhlioShimmerState();
}

class _PhlioShimmerState extends State<PhlioShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.child ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: PhlioColors.shimmerBase,
            borderRadius: widget.borderRadius ?? PhlioRadii.mdRadius,
          ),
          child: SizedBox(width: widget.width, height: widget.height),
        );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Sweep a highlight band from off-screen-left to off-screen-right,
        // looping. `-1..2` (rather than `0..1`) gives the band room to
        // fully enter and exit on each side.
        final sweep = -1.0 + (_controller.value * 3.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(sweep - 0.3, 0),
            end: Alignment(sweep + 0.3, 0),
            colors: const [
              PhlioColors.shimmerBase,
              PhlioColors.shimmerHighlight,
              PhlioColors.shimmerBase,
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: content,
    );
  }
}

/// A horizontal row of circular shimmer placeholders — matches the shape
/// of a featured-sellers/avatars strip.
class ShimmerRow extends StatelessWidget {
  const ShimmerRow({required this.itemCount, super.key, this.itemWidth = 56});

  final int itemCount;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(width: PhlioSpacing.lg),
      itemBuilder: (context, index) => PhlioShimmer(
        width: itemWidth,
        height: itemWidth,
        borderRadius: BorderRadius.circular(itemWidth / 2),
      ),
    );
  }
}

/// A grid of card-shaped shimmer placeholders — matches the shop/product
/// grid's layout so the loading state doesn't visually "jump" once real
/// cards replace it.
class ShimmerGrid extends StatelessWidget {
  const ShimmerGrid({
    required this.crossAxisCount,
    required this.itemCount,
    super.key,
    this.aspectRatio = 1,
  });

  final int crossAxisCount;
  final int itemCount;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: PhlioSpacing.lg,
        crossAxisSpacing: PhlioSpacing.lg,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, index) =>
          PhlioShimmer(borderRadius: PhlioRadii.xlRadius),
    );
  }
}

/// A vertical stack of line-shaped shimmer placeholders — matches a feed
/// of post/room cards.
class ShimmerList extends StatelessWidget {
  const ShimmerList({required this.itemCount, super.key, this.itemHeight = 88});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          PhlioShimmer(height: itemHeight, borderRadius: PhlioRadii.xlRadius),
          if (i != itemCount - 1) const SizedBox(height: PhlioSpacing.lg),
        ],
      ],
    );
  }
}
