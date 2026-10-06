// Login screen — mirrors the reference "1. LOGIN — Welcome to what's next."
// screen: the logo lockup up top, Foxy waving beside a "Good to see you
// again!" speech bubble, identifier + password fields, a gradient
// "Continue" button, labeled social sign-in chips (Google / Apple /
// Passkey — wired to a "coming soon" snackbar since OAuth providers are
// out of scope for this build stage), and a mountain-silhouette footer
// carrying the tagline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../design_system/widgets/phlio_text_field.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _formError;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final result = await ref.read(authControllerProvider.notifier).login(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    result.when(
      success: (_) => context.go('/home'),
      failure: (failure) => setState(() => _formError = failure.message),
    );
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xxl),
                  children: [
                    const SizedBox(height: PhlioSpacing.lg),
                    // Logo lockup.
                    Center(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 84,
                            child: Image.asset(
                              'assets/images/logo/logo_mark.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: PhlioSpacing.sm),
                          SizedBox(
                            height: 30,
                            child: Image.asset(
                              'assets/images/logo/logo_wordmark.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: PhlioSpacing.xs),
                          Text('PEOPLE. PLACES. POSSIBILITIES.', style: PhlioTypography.tagline),
                        ],
                      ),
                    ),
                    const SizedBox(height: PhlioSpacing.huge),
                    // Foxy + speech bubble, side by side.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const PhlioFoxAnimation(size: 104, animation: PhlioFoxLoop.wave),
                        Transform.translate(
                          offset: const Offset(0, -14),
                          child: _speechBubble(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: PhlioSpacing.huge),
                    PhlioTextField(
                      controller: _identifierController,
                      hintText: 'Email or phone number',
                      semanticLabel: 'Email or phone number',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Enter your email or phone number' : null,
                    ),
                    const SizedBox(height: PhlioSpacing.md),
                    PhlioTextField(
                      controller: _passwordController,
                      hintText: 'Password',
                      semanticLabel: 'Password',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) => setState(() => _formError = null),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Enter your password' : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {}, // Out of scope for this build stage.
                        child: Text('Forgot password?', style: PhlioTypography.label),
                      ),
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: PhlioSpacing.xs),
                      Text(_formError!, style: PhlioTypography.caption.copyWith(color: PhlioColors.danger)),
                    ],
                    const SizedBox(height: PhlioSpacing.sm),
                    PhlioPrimaryButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: PhlioSpacing.xl),
                    _buildDivider(),
                    const SizedBox(height: PhlioSpacing.lg),
                    // Labeled social sign-in chips.
                    Row(
                      children: [
                        _socialButton(Icons.g_mobiledata_rounded, 'Google'),
                        const SizedBox(width: PhlioSpacing.sm),
                        _socialButton(Icons.apple_rounded, 'Apple'),
                        const SizedBox(width: PhlioSpacing.sm),
                        _socialButton(Icons.key_rounded, 'Passkey'),
                      ],
                    ),
                    const SizedBox(height: PhlioSpacing.xl),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('New to Phlio? ', style: PhlioTypography.body),
                          GestureDetector(
                            onTap: () => context.go('/signup'),
                            child: Text(
                              'Create an account',
                              style:
                                  PhlioTypography.bodyStrong.copyWith(color: PhlioColors.brandOrange),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PhlioSpacing.xl),
                  ],
                ),
              ),
            ),
            // Mountain silhouette footer carrying the tagline.
            const _MountainFooter(),
          ],
        ),
      ),
    );
  }

  Widget _speechBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.sm),
      decoration: BoxDecoration(
        color: PhlioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Text('Good to\nsee you\nagain!',
          style: PhlioTypography.bodyStrong.copyWith(height: 1.25)),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: PhlioColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md),
          child: Text('or continue with', style: PhlioTypography.caption),
        ),
        const Expanded(child: Divider(color: PhlioColors.borderSubtle)),
      ],
    );
  }

  Widget _socialButton(IconData icon, String label) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label sign-in is coming soon.')),
        ),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PhlioColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PhlioColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: PhlioColors.textPrimary, size: 22),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: PhlioTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layered mountain silhouettes with the tagline on top — the reference
/// login's quiet footer.
class _MountainFooter extends StatelessWidget {
  const _MountainFooter();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      width: double.infinity,
      child: CustomPaint(
        painter: _MountainPainter(),
        child: Center(
          child: Text(
            'PEOPLE    PLACES    POSSIBILITIES',
            style: PhlioTypography.tagline.copyWith(fontSize: 10, letterSpacing: 4),
          ),
        ),
      ),
    );
  }
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Back range.
    final backPaint = Paint()..color = const Color(0xFF141824);
    final back = Path()
      ..moveTo(0, size.height * 0.75)
      ..lineTo(size.width * 0.18, size.height * 0.30)
      ..lineTo(size.width * 0.34, size.height * 0.62)
      ..lineTo(size.width * 0.52, size.height * 0.18)
      ..lineTo(size.width * 0.72, size.height * 0.58)
      ..lineTo(size.width * 0.88, size.height * 0.32)
      ..lineTo(size.width, size.height * 0.62)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, backPaint);

    // Front range (darker, lower).
    final frontPaint = Paint()..color = const Color(0xFF0E1119);
    final front = Path()
      ..moveTo(0, size.height * 0.92)
      ..lineTo(size.width * 0.22, size.height * 0.58)
      ..lineTo(size.width * 0.44, size.height * 0.88)
      ..lineTo(size.width * 0.66, size.height * 0.52)
      ..lineTo(size.width * 0.86, size.height * 0.84)
      ..lineTo(size.width, size.height * 0.66)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _MountainPainter oldDelegate) => false;
}
