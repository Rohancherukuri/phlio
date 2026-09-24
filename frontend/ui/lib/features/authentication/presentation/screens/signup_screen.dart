// Signup screen — mirrors the reference "2. SIGN UP — Create your world."
// screen. Implemented as a two-step flow (account details, then interest
// picking) rather than the reference's three steps — date-of-birth capture
// is omitted for this build stage since nothing in the backend uses it yet
// (see `backend/app/domains/identity/entities.py::User`), and adding an
// unused field would be collecting data with no purpose behind it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../design_system/widgets/phlio_text_field.dart';
import '../controllers/auth_controller.dart';

const _availableInterests = [
  'Art', 'Tech', 'Gaming', 'Travel',
  'Food', 'Music', 'Sports', 'Learning',
  'Shopping', 'Communities',
];

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  int _step = 0;
  final Set<String> _selectedInterests = {};
  bool _isSubmitting = false;
  String? _formError;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goToInterestsStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final result = await ref.read(authControllerProvider.notifier).register(
          fullName: _fullNameController.text.trim(),
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          interests: _selectedInterests.map((i) => i.toLowerCase()).toList(),
        );

    if (!mounted) return;
    result.when(
      success: (_) => context.go('/home'),
      failure: (failure) {
        setState(() {
          _step = 0;
          _formError = failure.message;
        });
      },
    );
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => _step == 0 ? context.go('/login') : setState(() => _step = 0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: PhlioSpacing.xl),
              if (_step == 0) _buildAccountStep() else _buildInterestsStep(),
              const SizedBox(height: PhlioSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        for (var i = 0; i < 2; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == 0 ? PhlioSpacing.sm : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: i <= _step ? PhlioColors.brandGradient : null,
                color: i <= _step ? null : PhlioColors.surfaceElevated,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAccountStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step 1 of 2', style: PhlioTypography.caption),
                    const SizedBox(height: PhlioSpacing.xs),
                    Text("Let's get you started", style: PhlioTypography.displayMedium),
                    const SizedBox(height: PhlioSpacing.xs),
                    Text(
                      'Create your Phlio account and unlock a bigger world together.',
                      style: PhlioTypography.body,
                    ),
                  ],
                ),
              ),
              const PhlioFox(size: 72),
            ],
          ),
          const SizedBox(height: PhlioSpacing.xxl),
          PhlioTextField(
            controller: _fullNameController,
            hintText: 'Full name',
            semanticLabel: 'Full name',
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _usernameController,
            hintText: 'Choose a username',
            semanticLabel: 'Username',
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().length < 3) return 'At least 3 characters';
              if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(v.trim())) return 'Letters, numbers, . and _ only';
              return null;
            },
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _emailController,
            hintText: 'Email or phone number',
            semanticLabel: 'Email',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _passwordController,
            hintText: 'Create a password',
            semanticLabel: 'Password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
          ),
          if (_formError != null) ...[
            const SizedBox(height: PhlioSpacing.sm),
            Text(_formError!, style: PhlioTypography.caption.copyWith(color: PhlioColors.danger)),
          ],
          const SizedBox(height: PhlioSpacing.xl),
          PhlioPrimaryButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _goToInterestsStep),
        ],
      ),
    );
  }

  Widget _buildInterestsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 2 of 2', style: PhlioTypography.caption),
        const SizedBox(height: PhlioSpacing.xs),
        Text('What are you interested in?', style: PhlioTypography.displayMedium),
        const SizedBox(height: PhlioSpacing.xs),
        Text('Pick a few to personalize your experience.', style: PhlioTypography.body),
        const SizedBox(height: PhlioSpacing.xl),
        Wrap(
          spacing: PhlioSpacing.sm,
          runSpacing: PhlioSpacing.sm,
          children: _availableInterests.map((interest) {
            final selected = _selectedInterests.contains(interest);
            return InkWell(
              borderRadius: PhlioRadii.pillRadius,
              onTap: () => setState(() {
                selected ? _selectedInterests.remove(interest) : _selectedInterests.add(interest);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: PhlioRadii.pillRadius,
                  color: selected ? null : PhlioColors.surfaceElevated,
                  gradient: selected ? PhlioColors.brandGradientSoft : null,
                  border: Border.all(color: selected ? Colors.transparent : PhlioColors.border),
                ),
                child: Text(
                  interest,
                  style: PhlioTypography.body.copyWith(
                    color: selected ? PhlioColors.textOnBrand : PhlioColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: PhlioSpacing.xxl),
        PhlioPrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          isLoading: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
