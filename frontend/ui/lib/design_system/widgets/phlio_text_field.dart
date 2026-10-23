// Phlio design system — text fields.
//
// Matches the reference auth screens: a filled, rounded field with a
// leading icon and no visible label above it (the hint text doubles as the
// label until the user starts typing — a deliberately minimal look, not an
// accessibility shortcut, so [PhlioTextField] still requires a
// `semanticLabel` for screen readers).

import 'package:flutter/material.dart';
import '../colors.dart';
import '../radii.dart';
import '../spacing.dart';
import '../typography.dart';

class PhlioTextField extends StatefulWidget {
  const PhlioTextField({
    required this.hintText,
    required this.semanticLabel,
    super.key,
    this.controller,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.autofillHints,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
  });

  final String hintText;
  final String semanticLabel;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<PhlioTextField> createState() => _PhlioTextFieldState();
}

class _PhlioTextFieldState extends State<PhlioTextField> {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      child: TextFormField(
        controller: widget.controller,
        obscureText: widget.obscureText && _obscured,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        validator: widget.validator,
        onChanged: widget.onChanged,
        autofillHints: widget.autofillHints,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        onTap: widget.onTap,
        style: PhlioTypography.bodyLarge,
        cursorColor: PhlioColors.brandPurple,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle:
              PhlioTypography.bodyLarge.copyWith(color: PhlioColors.textMuted),
          filled: true,
          fillColor: PhlioColors.surfaceInput,
          prefixIcon: widget.prefixIcon != null
              ? Icon(widget.prefixIcon, size: 20, color: PhlioColors.textMuted)
              : null,
          suffixIcon: widget.obscureText
              ? IconButton(
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: PhlioColors.textMuted,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: PhlioSpacing.lg,
            vertical: PhlioSpacing.lg,
          ),
          border: OutlineInputBorder(
            borderRadius: PhlioRadii.lgRadius,
            borderSide: const BorderSide(color: PhlioColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: PhlioRadii.lgRadius,
            borderSide: const BorderSide(color: PhlioColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: PhlioRadii.lgRadius,
            borderSide:
                const BorderSide(color: PhlioColors.brandPurple, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: PhlioRadii.lgRadius,
            borderSide: const BorderSide(color: PhlioColors.danger),
          ),
          errorStyle:
              PhlioTypography.caption.copyWith(color: PhlioColors.danger),
        ),
      ),
    );
  }
}
