import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';

/// Full-width conversation on phones, with a swipeable room drawer.
/// Larger windows keep both panes visible and allow divider resizing.
class RoomsLayout extends StatefulWidget {
  const RoomsLayout({
    required this.sidebarBuilder,
    required this.chatBuilder,
    required this.sidebarWidth,
    required this.onSidebarWidthChanged,
    this.composer,
    super.key,
  });

  final Widget Function(VoidCallback close) sidebarBuilder;
  final Widget Function(VoidCallback? open) chatBuilder;
  final Widget? composer;
  final double sidebarWidth;
  final ValueChanged<double> onSidebarWidthChanged;

  @override
  State<RoomsLayout> createState() => _RoomsLayoutState();
}

class _RoomsLayoutState extends State<RoomsLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  bool _acceptSwipe = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  void _open() {
    FocusManager.instance.primaryFocus?.unfocus();
    _slide.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _close() => _slide.animateTo(0, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _panes(context)),
        if (widget.composer != null) widget.composer!,
      ],
    );
  }

  Widget _panes(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          final maxWidth = math.min(360.0, constraints.maxWidth - 374);
          final width = widget.sidebarWidth.clamp(280.0, maxWidth).toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: width, child: widget.sidebarBuilder(() {})),
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      widget.onSidebarWidthChanged(
                    (width + details.delta.dx)
                        .clamp(280.0, maxWidth)
                        .toDouble(),
                  ),
                  child: SizedBox(
                    key: const ValueKey('rooms-divider'),
                    width: 14,
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _hovering
                              ? PhlioColors.brandViolet
                              : PhlioColors.borderSubtle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: widget.chatBuilder(null)),
            ],
          );
        }

        final drawerWidth = math.min(360.0, constraints.maxWidth - 40);
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, _) => PopScope(
            canPop: _slide.value == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _close();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragDown: (details) {
                _acceptSwipe =
                    _slide.value > 0 || details.localPosition.dx <= 32;
              },
              onHorizontalDragStart: (_) {
                if (_acceptSwipe) _slide.stop();
              },
              onHorizontalDragUpdate: (details) {
                if (!_acceptSwipe) return;
                _slide.value = (_slide.value + details.delta.dx / drawerWidth)
                    .clamp(0.0, 1.0);
              },
              onHorizontalDragEnd: (details) {
                if (!_acceptSwipe) return;
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() > 300 ? velocity > 0 : _slide.value > 0.5) {
                  _open();
                } else {
                  _close();
                }
                _acceptSwipe = false;
              },
              onHorizontalDragCancel: () {
                if (_acceptSwipe) _close();
                _acceptSwipe = false;
              },
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  ExcludeFocus(
                    excluding: _slide.value > 0,
                    child: ExcludeSemantics(
                      excluding: _slide.value > 0,
                      child: widget.chatBuilder(_open),
                    ),
                  ),
                  if (_slide.value > 0)
                    Positioned.fill(
                      child: Semantics(
                        button: true,
                        label: 'Close rooms panel',
                        child: GestureDetector(
                          onTap: _close,
                          child: ColoredBox(
                            key: const ValueKey('rooms-scrim'),
                            color: Colors.black
                                .withValues(alpha: 0.5 * _slide.value),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: -drawerWidth * (1 - _slide.value),
                    width: drawerWidth,
                    child: IgnorePointer(
                      ignoring: _slide.value == 0,
                      child: ExcludeFocus(
                        excluding: _slide.value == 0,
                        child: ExcludeSemantics(
                          excluding: _slide.value == 0,
                          child: Material(
                            color: PhlioColors.roomsSidebar,
                            elevation: 12 * _slide.value,
                            clipBehavior: Clip.antiAlias,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(24),
                            ),
                            child: widget.sidebarBuilder(_close),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
