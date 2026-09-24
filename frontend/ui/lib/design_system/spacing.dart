// Phlio design system — spacing scale.
//
// A single 4px-based scale used for every margin/padding/gap in the app.
// Reaching for `PhlioSpacing.md` instead of a bare `16` keeps rhythm
// consistent across screens built at different times and makes a global
// density change (e.g. a future tablet layout) a one-file edit.

abstract final class PhlioSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double massive = 64;
}
