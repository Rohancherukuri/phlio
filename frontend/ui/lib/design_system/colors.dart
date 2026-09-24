// Phlio design system — color tokens.
//
// Values are lifted directly from the reference screens (deep, near-black
// navy surfaces; a purple → pink → orange brand gradient shared by the
// logo, the fox mascot's accents, and every primary call-to-action). Every
// other part of the app should reference these tokens rather than hardcode
// a color literal, so a future rebrand is a one-file change.

import 'package:flutter/material.dart';

/// Static color tokens for Phlio's (currently dark-only) theme.
///
/// Deliberately a plain class of `static const` fields rather than a
/// `ThemeExtension` for this first pass — the product is dark-mode-only
/// today (see the reference screens), so there is no light/dark variant to
/// switch between yet. If/when a light theme is added, promote this to a
/// `ThemeExtension<PhlioColors>` so `Theme.of(context)` resolves the right
/// variant automatically instead of every call site branching on
/// `Brightness` itself.
abstract final class PhlioColors {
  // -- Surfaces, darkest to lightest --------------------------------------
  static const Color background = Color(0xFF0A0B14);
  static const Color surface = Color(0xFF13141F);
  static const Color surfaceElevated = Color(0xFF1B1D2B);
  static const Color surfaceInput = Color(0xFF191B28);
  static const Color border = Color(0xFF272A3B);
  static const Color borderSubtle = Color(0xFF1E2030);

  // -- Text -----------------------------------------------------------------
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFFA6A9BD);
  static const Color textMuted = Color(0xFF6E7186);
  static const Color textOnBrand = Color(0xFF150E24); // for text atop the gradient

  // -- Brand gradient (logo, primary buttons, the Agent's accents) --------
  static const Color brandBlue = Color(0xFF5C8DF6);
  static const Color brandPurple = Color(0xFF8B6CF6);
  static const Color brandPink = Color(0xFFDD6FC4);
  static const Color brandOrange = Color(0xFFFFA45C);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlue, brandPurple, brandPink, brandOrange],
    stops: [0.0, 0.4, 0.7, 1.0],
  );

  /// A softer, two-stop version of [brandGradient] for large surfaces
  /// (banners, the Agent's header) where the full four-stop gradient would
  /// be too busy.
  static const LinearGradient brandGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPurple, brandOrange],
  );

  // -- Domain accent colors -------------------------------------------------
  // Used for the Home screen's quick-action icons and anywhere a domain
  // needs a single identifying color. Matches the eight Phlio domains from
  // Phlio_Final_Product_Blueprint.md section 3, in that order.
  static const Color domainPay = Color(0xFF4C8DFF);
  static const Color domainSocial = Color(0xFF6E7CFF);
  static const Color domainRooms = Color(0xFF3DC9B0);
  static const Color domainBook = Color(0xFFFF6B8B);
  static const Color domainShop = Color(0xFFFF9F45);
  static const Color domainStream = Color(0xFFB57BFF);
  static const Color domainNews = Color(0xFF33C481);
  static const Color domainAgent = Color(0xFFDD6FC4);
  // Retained as an alias: the Shop domain's Art & Handmade category reuses
  // this color for its imagery accent (see `product_card.dart`), distinct
  // from the domain-level `domainShop` used on the Home grid.
  static const Color domainArt = Color(0xFFB57BFF);

  // -- Semantic ---------------------------------------------------------------
  static const Color success = Color(0xFF3ECF8E);
  static const Color warning = Color(0xFFF6B93B);
  static const Color danger = Color(0xFFF5636B);
  static const Color info = brandBlue;

  // -- Overlays -------------------------------------------------------------
  static const Color scrim = Color(0xB3000000); // 70% black, for sheets/dialogs
  static const Color shimmerBase = Color(0xFF191B28);
  static const Color shimmerHighlight = Color(0xFF24273A);
}
