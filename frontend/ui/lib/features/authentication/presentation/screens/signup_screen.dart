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
  'Art',
  'Tech',
  'Gaming',
  'Travel',
  'Food',
  'Music',
  'Sports',
  'Learning',
  'Shopping',
  'Communities',
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

  final _phoneController = TextEditingController();
  final _birthdayController = TextEditingController();
  DateTime? _birthday;

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
    _phoneController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _birthday ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today.subtract(const Duration(days: 1)),
      helpText: 'Date of birth',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _birthday = selected;
      _birthdayController.text =
          MaterialLocalizations.of(context).formatMediumDate(selected);
    });
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
          phoneNumber:
              _phoneController.text.replaceAll(RegExp(r'[\s()\-]'), ''),
          dateOfBirth: _birthday!.toIso8601String().split('T').first,
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
      backgroundColor: PhlioColors.backgroundDeep,
      appBar: AppBar(
        backgroundColor: PhlioColors.backgroundDeep,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () =>
              _step == 0 ? context.go('/login') : setState(() => _step = 0),
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
                    Text("Let's get you started",
                        style: PhlioTypography.displayMedium),
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
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Enter your full name'
                : null,
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _usernameController,
            hintText: 'Choose a username',
            semanticLabel: 'Username',
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().length < 3)
                return 'At least 3 characters';
              if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(v.trim()))
                return 'Letters, numbers, . and _ only';
              return null;
            },
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _emailController,
            hintText: 'Email address',
            semanticLabel: 'Email',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _phoneController,
            hintText: 'Phone number with country code',
            semanticLabel: 'Phone number with country code',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (v) => RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(
              (v ?? '').replaceAll(RegExp(r'[\s()\-]'), ''),
            )
                ? null
                : 'Include your country code, e.g. +919876543210',
          ),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _birthdayController,
            hintText: 'Date of birth',
            semanticLabel: 'Date of birth',
            prefixIcon: Icons.cake_outlined,
            readOnly: true,
            onTap: _pickBirthday,
            validator: (_) =>
                _birthday == null ? 'Choose your date of birth' : null,
          ),
          const SizedBox(height: PhlioSpacing.sm),
          Text('Your phone number and birthday stay private.',
              style: PhlioTypography.caption),
          const SizedBox(height: PhlioSpacing.md),
          PhlioTextField(
            controller: _passwordController,
            hintText: 'Create a password',
            semanticLabel: 'Password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: (v) =>
                (v == null || v.length < 8) ? 'At least 8 characters' : null,
          ),
          if (_formError != null) ...[
            const SizedBox(height: PhlioSpacing.sm),
            Text(_formError!,
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.danger)),
          ],
          const SizedBox(height: PhlioSpacing.xl),
          PhlioPrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: _goToInterestsStep),
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
        Text('What are you interested in?',
            style: PhlioTypography.displayMedium),
        const SizedBox(height: PhlioSpacing.xs),
        Text('Pick a few to personalize your experience.',
            style: PhlioTypography.body),
        const SizedBox(height: PhlioSpacing.xl),
        Wrap(
          spacing: PhlioSpacing.sm,
          runSpacing: PhlioSpacing.sm,
          children: _availableInterests.map((interest) {
            final selected = _selectedInterests.contains(interest);
            return InkWell(
              borderRadius: PhlioRadii.pillRadius,
              onTap: () => setState(() {
                selected
                    ? _selectedInterests.remove(interest)
                    : _selectedInterests.add(interest);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: PhlioRadii.pillRadius,
                  color: selected ? null : PhlioColors.surfaceElevated,
                  gradient: selected ? PhlioColors.brandGradientSoft : null,
                  border: Border.all(
                      color:
                          selected ? Colors.transparent : PhlioColors.border),
                ),
                child: Text(
                  interest,
                  style: PhlioTypography.body.copyWith(
                    color: PhlioColors.textPrimary,
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
