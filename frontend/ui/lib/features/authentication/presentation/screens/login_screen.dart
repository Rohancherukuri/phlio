// Login screen — mirrors the reference "1. LOGIN — Welcome to what's next."
// screen: a centered fox illustration with a speech-bubble greeting,
// identifier + password fields, a gradient "Continue" button, and social
// sign-in chips (visually present; wired to a "coming soon" snackbar since
// OAuth/passkey providers are out of scope for this build stage).

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: PhlioSpacing.xl),
                ShaderMask(
                  shaderCallback: (bounds) => PhlioColors.brandGradient.createShader(bounds),
                  child: Text('Phlio', style: PhlioTypography.displayLarge.copyWith(color: Colors.white)),
                ),
                Text(
                  'PEOPLE. PLACES. POSSIBILITIES.',
                  style: PhlioTypography.caption.copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: PhlioSpacing.huge),
                Center(
                  child: Column(
                    children: [
                      const PhlioFox(size: 120, pose: PhlioFoxPose.waving),
                      const SizedBox(height: PhlioSpacing.lg),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PhlioSpacing.lg,
                          vertical: PhlioSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: PhlioColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('Good to see you again!', style: PhlioTypography.bodyStrong),
                      ),
                    ],
                  ),
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
                const SizedBox(height: PhlioSpacing.lg),
                PhlioPrimaryButton(
                  label: 'Continue',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: PhlioSpacing.xxl),
                _buildDivider(),
                const SizedBox(height: PhlioSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _socialButton(Icons.g_mobiledata_rounded, 'Google'),
                    _socialButton(Icons.apple_rounded, 'Apple'),
                    _socialButton(Icons.key_rounded, 'Passkey'),
                  ],
                ),
                const SizedBox(height: PhlioSpacing.xxl),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('New to Phlio? ', style: PhlioTypography.body),
                      GestureDetector(
                        onTap: () => context.go('/signup'),
                        child: Text(
                          'Create an account',
                          style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.brandPurple),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PhlioSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label sign-in is coming soon.')),
      ),
      child: Container(
        width: 88,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PhlioColors.border),
        ),
        child: Icon(icon, color: PhlioColors.textPrimary),
      ),
    );
  }
}
