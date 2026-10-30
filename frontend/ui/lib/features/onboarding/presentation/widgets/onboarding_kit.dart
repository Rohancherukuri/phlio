// Shared pieces for the splash, log-in and sign-up flow.
//
// Kept deliberately small: one backdrop, one field, one link button and a
// stagger helper. Every onboarding screen is built from these so spacing,
// radii and motion read as one product.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';

/// The near-black onboarding canvas with two very faint brand glows that
/// drift slowly — enough depth to feel lit, never enough to read as a
/// gradient wallpaper.
class OnboardingBackdrop extends StatefulWidget {
  const OnboardingBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends State<OnboardingBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
      vsync: this, duration: const Duration(seconds: 18))
    ..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PhlioColors.backgroundDeep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                final t = _drift.value * 2 * math.pi;
                return Stack(fit: StackFit.expand, children: [
                  _glow(Alignment(-0.9 + math.sin(t) * 0.15, -0.85 + math.cos(t) * 0.08),
                      PhlioColors.brandViolet, 0.13),
                  _glow(Alignment(0.95 + math.cos(t) * 0.12, 0.9 + math.sin(t) * 0.1),
                      PhlioColors.brandPeach, 0.08),
                ]);
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _glow(Alignment at, Color color, double strength) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: at,
            radius: 0.9,
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      );
}

/// Instagram-style outlined input with a floating label.
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.autofillHints,
    this.errorText,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.error = false,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final String? errorText;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  /// Outline in red without an error line (Foxy says what's wrong).
  final bool error;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      readOnly: readOnly,
      onTap: onTap,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      autocorrect: false,
      enableSuggestions: !obscureText,
      cursorColor: PhlioColors.brandPeach,
      style: PhlioTypography.bodyLarge
          .copyWith(fontSize: 18.5, fontWeight: FontWeight.w600, height: 1.3),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: PhlioTypography.body
            .copyWith(fontSize: 16.5, color: PhlioColors.textMuted),
        floatingLabelStyle: PhlioTypography.label.copyWith(
            fontSize: 14, color: PhlioColors.textSecondary),
        filled: true,
        fillColor: PhlioColors.surface.withValues(alpha: 0.72),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        prefixIcon: prefix,
        suffixIcon: suffix,
        errorText: errorText,
        errorMaxLines: 3,
        errorStyle: PhlioTypography.caption
            .copyWith(fontSize: 13.5, color: PhlioColors.danger),
        enabledBorder: border(error
            ? PhlioColors.danger.withValues(alpha: 0.8)
            : PhlioColors.border.withValues(alpha: 0.9)),
        focusedBorder: border(
            error ? PhlioColors.danger : PhlioColors.brandLavender, 1.6),
        errorBorder: border(PhlioColors.danger.withValues(alpha: 0.8)),
        focusedErrorBorder: border(PhlioColors.danger, 1.4),
      ),
    );
  }
}

/// A plain, centred text action ("I already have an account").
class OnboardingLink extends StatelessWidget {
  const OnboardingLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: PhlioColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label,
          style: PhlioTypography.bodyStrong
              .copyWith(color: PhlioColors.textPrimary)),
    );
  }
}

/// Fades and lifts its child in after [delay] — used to stagger the
/// elements of a screen instead of showing everything at once.
class StaggerIn extends StatelessWidget {
  const StaggerIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    const run = Duration(milliseconds: 520);
    final total = delay + run;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (context, v, child) {
        final t = Curves.easeOutCubic
            .transform(((v - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, (1 - t) * offset), child: child),
        );
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Foxy's speech bubble

enum BubbleTail { left, bottom }

/// Foxy talking: a bubble that types its text out (and pops when the text
/// changes). [onTyping] reports when the words are coming out, so Foxy can
/// bob along while he "speaks".
class FoxyBubble extends StatefulWidget {
  const FoxyBubble({
    super.key,
    required this.text,
    this.tail = BubbleTail.left,
    this.onTyping,
    this.tone,
    this.style,
  });

  final String text;
  final BubbleTail tail;
  final ValueChanged<bool>? onTyping;

  /// Optional accent (e.g. danger red for an error).
  final Color? tone;
  final TextStyle? style;

  @override
  State<FoxyBubble> createState() => _FoxyBubbleState();
}

class _FoxyBubbleState extends State<FoxyBubble>
    with TickerProviderStateMixin {
  late AnimationController _type;
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420))
    ..forward();

  @override
  void initState() {
    super.initState();
    _type = _typer();
  }

  AnimationController _typer() {
    final ms = (widget.text.length * 26).clamp(260, 2400);
    final c = AnimationController(
        vsync: this, duration: Duration(milliseconds: ms));
    c.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onTyping?.call(false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onTyping?.call(true);
      c.forward();
    });
    return c;
  }

  @override
  void didUpdateWidget(FoxyBubble old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text) {
      _type.dispose();
      _type = _typer();
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _type.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final style = (widget.style ??
            PhlioTypography.title.copyWith(fontSize: 19, height: 1.32))
        .copyWith(color: PhlioColors.textPrimary);
    return AnimatedBuilder(
      animation: Listenable.merge([_type, _pop]),
      builder: (context, _) {
        final pop = Curves.easeOutBack.transform(_pop.value.clamp(0.0, 1.0));
        final shown = (widget.text.length * _type.value).round();
        return Transform.scale(
          scale: 0.9 + 0.1 * pop,
          alignment: widget.tail == BubbleTail.left
              ? Alignment.centerLeft
              : Alignment.bottomCenter,
          child: Opacity(
            opacity: _pop.value.clamp(0.0, 1.0),
            child: CustomPaint(
              painter: _BubblePainter(
                tail: widget.tail,
                fill: tone == null
                    ? PhlioColors.surfaceElevated
                    : Color.alphaBlend(
                        tone.withValues(alpha: 0.14), PhlioColors.surfaceElevated),
                stroke: tone?.withValues(alpha: 0.6) ??
                    PhlioColors.border.withValues(alpha: 0.9),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    widget.tail == BubbleTail.left ? 26 : 18,
                    14,
                    18,
                    widget.tail == BubbleTail.bottom ? 24 : 15),
                // The whole sentence is laid out from the start (the
                // unrevealed part is transparent) so the bubble never jumps.
                child: Text.rich(
                  TextSpan(style: style, children: [
                    TextSpan(text: widget.text.substring(0, shown)),
                    TextSpan(
                      text: widget.text.substring(shown),
                      style: const TextStyle(color: Colors.transparent),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.tail, required this.fill, required this.stroke});

  final BubbleTail tail;
  final Color fill, stroke;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 20.0;
    final path = Path();
    if (tail == BubbleTail.left) {
      final body = RRect.fromLTRBR(10, 0, size.width, size.height,
          const Radius.circular(r));
      path.addRRect(body);
      final cy = math.min(size.height / 2, 34.0);
      path.moveTo(11, cy - 9);
      path.quadraticBezierTo(4, cy - 2, 0, cy + 2);
      path.quadraticBezierTo(6, cy + 6, 11, cy + 9);
      path.close();
    } else {
      final body = RRect.fromLTRBR(0, 0, size.width, size.height - 10,
          const Radius.circular(r));
      path.addRRect(body);
      final cx = size.width / 2;
      path.moveTo(cx - 10, size.height - 11);
      path.quadraticBezierTo(cx - 2, size.height - 4, cx + 2, size.height);
      path.quadraticBezierTo(cx + 6, size.height - 6, cx + 10, size.height - 11);
      path.close();
    }
    final merged = Path.combine(PathOperation.union, path, Path());
    canvas.drawShadow(merged, Colors.black, 6, false);
    canvas.drawPath(merged, Paint()..color = fill);
    canvas.drawPath(
        merged,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill || old.stroke != stroke || old.tail != tail;
}

// ---------------------------------------------------------------------------
// Confetti

/// A one-shot confetti burst in brand colours. Increment [trigger] to fire.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.trigger,
    this.origin = const Alignment(0, -0.2),
    this.count = 90,
  });

  final int trigger;
  final Alignment origin;
  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Bit {
  _Bit(math.Random r)
      : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * 2.2,
        speed = 520 + r.nextDouble() * 520,
        spin = (r.nextDouble() - 0.5) * 14,
        flip = 4 + r.nextDouble() * 8,
        size = 5 + r.nextDouble() * 6,
        shape = r.nextInt(3),
        color = const [
          PhlioColors.brandPeach,
          PhlioColors.brandViolet,
          PhlioColors.brandPink,
          Color(0xFF68D7CD),
          Color(0xFFFFCE54),
        ][r.nextInt(5)],
        delay = r.nextDouble() * 0.08;

  final double angle, speed, spin, flip, size, delay;
  final int shape;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
  List<_Bit> _bits = const [];

  @override
  void didUpdateWidget(ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      final r = math.Random();
      _bits = List.generate(widget.count, (_) => _Bit(r));
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_c, _bits, widget.origin),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.bits, this.origin) : super(repaint: anim);

  final Animation<double> anim;
  final List<_Bit> bits;
  final Alignment origin;

  @override
  void paint(Canvas canvas, Size size) {
    if (anim.value == 0 || anim.value == 1) return;
    final o = origin.alongSize(size);
    final secs = anim.value * 2.6;
    final paint = Paint();
    for (final b in bits) {
      final t = secs - b.delay;
      if (t <= 0) continue;
      // Ballistic with air drag: fast burst, slow drift down.
      const drag = 2.2, gravity = 900.0;
      final damp = (1 - math.exp(-drag * t)) / drag;
      final x = o.dx + math.cos(b.angle) * b.speed * damp;
      final y = o.dy + math.sin(b.angle) * b.speed * damp +
          gravity * (t / drag - damp / drag);
      final life = (1 - (t / 2.5)).clamp(0.0, 1.0);
      if (life <= 0) continue;
      paint.color = b.color.withValues(alpha: math.min(1.0, life * 2.5));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * t);
      canvas.scale(math.cos(b.flip * t), 1); // tumbling in 3D
      switch (b.shape) {
        case 0:
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 1.8),
                  const Radius.circular(1.5)),
              paint);
        case 1:
          canvas.drawCircle(Offset.zero, b.size * 0.45, paint);
        default:
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: b.size * 2.2, height: b.size * 0.7),
                  const Radius.circular(2)),
              paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.bits != bits;
}

// ---------------------------------------------------------------------------
// Progress

/// Duolingo-style chunky progress bar with a soft highlight.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, v, _) => SizedBox(
        height: 12,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Container(
                width: math.max(12.0, box.maxWidth * v.clamp(0.0, 1.0)),
                decoration: BoxDecoration(
                  gradient: PhlioColors.sunsetGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
