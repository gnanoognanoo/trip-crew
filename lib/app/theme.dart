import 'package:flutter/material.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// Central theme definition for TripCrew.
/// Visual Direction: Modern, social, adventurous, clean, premium, and mobile-first.
class AppTheme {
  AppTheme._();

  // Core Brand Colors
  static const Color primaryTeal = Color(0xFF0C6B7B);
  static const Color primaryTealLight = Color(0xFFE0F4F7);
  static const Color secondaryCoral = Color(0xFFE25B3E);
  static const Color secondaryCoralLight = Color(0xFFFFECE7);
  static const Color tertiaryAmber = Color(0xFFB57200);

  // Light Color Scheme
  static final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
    seedColor: primaryTeal,
    brightness: Brightness.light,
    primary: primaryTeal,
    secondary: secondaryCoral,
    tertiary: tertiaryAmber,
    surface: const Color(0xFFF9FBFC),
    onSurface: const Color(0xFF141D20),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF2F6F8),
    surfaceContainer: const Color(0xFFEAF0F3),
    surfaceContainerHigh: const Color(0xFFE3EAEE),
    outline: const Color(0xFFBFC9CD),
    outlineVariant: const Color(0xFFDEE5E8),
  );

  // Dark Color Scheme
  static final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
    seedColor: primaryTeal,
    brightness: Brightness.dark,
    primary: const Color(0xFF5DD5EC),
    secondary: const Color(0xFFFFB4A4),
    tertiary: const Color(0xFFFFB95E),
    surface: const Color(0xFF0F171A),
    onSurface: const Color(0xFFDEE5E8),
    surfaceContainerLowest: const Color(0xFF0A1012),
    surfaceContainerLow: const Color(0xFF151E22),
    surfaceContainer: const Color(0xFF1B2529),
    surfaceContainerHigh: const Color(0xFF212C31),
    outline: const Color(0xFF4A565B),
    outlineVariant: const Color(0xFF333E43),
  );

  /// Light theme
  static ThemeData get lightTheme {
    return _buildTheme(_lightColorScheme);
  }

  /// Dark theme
  static ThemeData get darkTheme {
    return _buildTheme(_darkColorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? colorScheme.surfaceContainerLow : Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceMd,
          ),
          side: BorderSide(color: colorScheme.outline, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      ),
    );
  }
}
