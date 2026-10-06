// Phlio design system — color tokens.
//
// Values are lifted directly from the brand reference sheets: near-black
// navy surfaces warmed by Foxy's fur — a sunset gradient (violet → peach)
// shared by the logo mark, the fox mascot's accents, and every primary
// call-to-action. Every other part of the app should reference these tokens
// rather than hardcode a color literal, so a future rebrand is a one-file
// change.

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
  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF12151F);
  static const Color surfaceElevated = Color(0xFF1A1F2E);
  static const Color surfaceInput = Color(0xFF161B26);
  static const Color border = Color(0xFF262D3D);
  static const Color borderSubtle = Color(0xFF1C2230);

  // Rooms uses a charcoal conversation and a lighter, sliding room panel.
  static const Color roomsChat = Color(0xFF24262B);
  static const Color roomsRail = Color(0xFF202127);
  static const Color roomsInput = Color(0xFF383A40);
  static const Color roomsSidebar = Color(0xFF303238);

  // -- Text -----------------------------------------------------------------
  static const Color textPrimary = Color(0xFFF5F5F4);
  static const Color textSecondary = Color(0xFFA8B0C2);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textOnBrand = Color(0xFF1A0F08); // text atop the gradient

  // -- Brand (Foxy's palette: ember orange + dusk violet) -------------------
  static const Color brandOrange = Color(0xFFFF8A4C);
  static const Color brandPeach = Color(0xFFFFB27A);
  static const Color brandViolet = Color(0xFF8B5CF6);
  static const Color brandLavender = Color(0xFFA78BFA);
  static const Color brandPink = Color(0xFFE879A6);

  /// Primary CTA gradient — violet melting into peach, left to right
  /// (the "Continue" pill from the reference screens).
  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [brandLavender, brandOrange],
  );

  /// Reverse ember gradient — orange → pink → violet (the "Book This Plan"
  /// pill). Use for highlights where the CTA should feel warmer.
  static const LinearGradient emberGradient = LinearGradient(
    colors: [brandOrange, brandPink, brandLavender],
  );

  /// Legacy alias kept for existing call sites (logo shading, avatars):
  /// the full sunset ramp used by the wordmark and mascot accents.
  static const LinearGradient brandGradient = sunsetGradient;

  // -- Legacy aliases -------------------------------------------------------
  // Older call sites referenced the first-pass palette by name. They resolve
  // to the closest new token so nothing breaks, but new code should prefer
  // the brand tokens above.
  static const Color brandPurple = brandViolet;
  static const Color brandBlue = Color(0xFF4C8DFF);

  /// A softer, two-stop version for large surfaces (banners, the Agent's
  /// header) where a hard gradient would be too busy.
  static const LinearGradient brandGradientSoft = LinearGradient(
    colors: [Color(0xFF2A2340), Color(0xFF3A2A28)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
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
  static const Color domainAgent = Color(0xFFFF8A4C);
  // Retained as an alias: the Shop domain's Art & Handmade category reuses
  // this color for its imagery accent (see `product_card.dart`), distinct
  // from the domain-level `domainShop` used on the Home grid.
  static const Color domainArt = Color(0xFFB57BFF);

  // -- Semantic ---------------------------------------------------------------
  static const Color success = Color(0xFF3ECF8E);
  static const Color warning = Color(0xFFF6B93B);
  static const Color danger = Color(0xFFF5636B);
  static const Color info = Color(0xFF4C8DFF);

  // -- Overlays -------------------------------------------------------------
  static const Color scrim = Color(0xB3000000); // 70% black, for sheets/dialogs
  static const Color shimmerBase = Color(0xFF161B26);
  static const Color shimmerHighlight = Color(0xFF232A3B);
}
