import 'package:flutter/material.dart';

/// Design tokens for spacing, radius and motion.
/// Keep values centralized to avoid per-page drift.
final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  const AppSpacing._();
}

final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double xxxl = 32;
  static const double pill = 999;

  const AppRadius._();
}

final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration routeTransition = Duration(milliseconds: 260);
  static const Duration gallerySync = Duration(milliseconds: 140);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubic;

  const AppMotion._();
}
