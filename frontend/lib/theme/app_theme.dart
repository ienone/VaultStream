import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AppTheme manages the application's visual identity using Material 3 Expressive principles.
class AppTheme {
  // Brand color - slightly more vibrant for "Expressive" feel
  static const _seedColor = Color(0xFF6750A4);

  static final _defaultLightColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.light,
  );

  static final _defaultDarkColorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  );

  static ThemeData light(ColorScheme? dynamicColorScheme) {
    return fromColorScheme(dynamicColorScheme ?? _defaultLightColorScheme, Brightness.light);
  }

  static ThemeData dark(ColorScheme? dynamicColorScheme) {
    return fromColorScheme(dynamicColorScheme ?? _defaultDarkColorScheme, Brightness.dark);
  }

  static ThemeData fromColorScheme(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textTheme = _buildTextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      textTheme: textTheme,

      // Surface & Background
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,

      // Enhanced AppBar for Expressive M3
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, // Usually used with glassmorphism or scrolledUnderElevation
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      // Expressive Navigation Rail
      navigationRailTheme: NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer, size: 28),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      // M3 Expressive Cards: Larger radii and subtle borders
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: isDark 
            ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))
            : BorderSide.none,
        ),
      ),

      // Dynamic Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        hoverElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      // Input Decoration (Textfields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        titleTextStyle: textTheme.headlineSmall,
      ),

      // Transitions - Using built-in physics
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Builds a text theme using Google Fonts for an expressive feel.
  /// Lexend is chosen for its clarity and geometric personality (Headings).
  /// Inter provides excellent legibility for body text.
  static TextTheme _buildTextTheme(Brightness brightness) {
    final baseTheme = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;

    return GoogleFonts.lexendTextTheme(baseTheme).copyWith(
      displayLarge: GoogleFonts.lexend(textStyle: baseTheme.displayLarge, fontWeight: FontWeight.bold),
      displayMedium: GoogleFonts.lexend(textStyle: baseTheme.displayMedium, fontWeight: FontWeight.bold),
      displaySmall: GoogleFonts.lexend(textStyle: baseTheme.displaySmall, fontWeight: FontWeight.bold),
      headlineLarge: GoogleFonts.lexend(textStyle: baseTheme.headlineLarge, fontWeight: FontWeight.bold),
      headlineMedium: GoogleFonts.lexend(textStyle: baseTheme.headlineMedium, fontWeight: FontWeight.bold),
      headlineSmall: GoogleFonts.lexend(textStyle: baseTheme.headlineSmall, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.lexend(textStyle: baseTheme.titleLarge, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.lexend(textStyle: baseTheme.titleMedium, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.lexend(textStyle: baseTheme.titleSmall, fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.inter(textStyle: baseTheme.bodyLarge),
      bodyMedium: GoogleFonts.inter(textStyle: baseTheme.bodyMedium),
      bodySmall: GoogleFonts.inter(textStyle: baseTheme.bodySmall),
      labelLarge: GoogleFonts.inter(textStyle: baseTheme.labelLarge, fontWeight: FontWeight.bold),
    );
  }
}
