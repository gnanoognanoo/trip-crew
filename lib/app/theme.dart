import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// TripCrew Brand Colour System: Warm Espresso & Cream
/// Understated luxury with an adventurous personality.
///
/// Palette:
/// - Cream:      #F8F4EC (Main background - 70%)
/// - Warm Beige:  #EADCC8 (Cards and surfaces)
/// - Sand:        #D6C2A5 (Secondary surfaces & subtle borders)
/// - Espresso:    #4B2E21 (Primary brand colour - 20%, CTA, headings)
/// - Mocha:       #6F4A37 (Secondary text & muted UI)
/// - Caramel:     #B9855B (Accent - 10%, badges, links, active states)
///
/// Supporting colours:
/// - Sage:        #8FAE9D
/// - Terracotta:  #C97A5B
/// - Sunset:      #E6A86B
/// - Muted Blue:  #6B8FAA
class AppTheme {
  AppTheme._();

  // Core Brand Palette
  static const Color cream = Color(0xFFF8F4EC);
  static const Color warmBeige = Color(0xFFEADCC8);
  static const Color sand = Color(0xFFD6C2A5);
  static const Color espresso = Color(0xFF4B2E21);
  static const Color mocha = Color(0xFF6F4A37);
  static const Color caramel = Color(0xFFB9855B);

  // Supporting Colours
  static const Color sage = Color(0xFF8FAE9D);
  static const Color terracotta = Color(0xFFC97A5B);
  static const Color sunset = Color(0xFFE6A86B);
  static const Color mutedBlue = Color(0xFF6B8FAA);

  // Dark Canvas Palette (for subtle night mode support)
  static const Color espressoNight = Color(0xFF1E130D);
  static const Color espressoSurfaceDark = Color(0xFF2A1C14);
  static const Color espressoCardDark = Color(0xFF35241B);
  static const Color sandBorderDark = Color(0xFF4A3427);
  static const Color creamTextDark = Color(0xFFFAF6F0);
  static const Color mochaTextDark = Color(0xFFC2B0A4);

  // Compatibility aliases across screens
  static const Color espressoBrown = espresso;
  static const Color espressoSurface = espressoSurfaceDark;
  static const Color espressoBorder = sandBorderDark;
  static const Color espressoCard = espressoCardDark;
  static const Color warmBeigeLight = warmBeige;
  static const Color pine = espresso;
  static const Color ink = espresso;
  static const Color paperLight = cream;
  static const Color trailCoral = terracotta;
  static const Color goldenAmber = sunset;

  static const Color deepForest = espressoNight;
  static const Color raisedSurface = espressoSurfaceDark;
  static const Color softSage = sage;
  static const Color warmCoral = terracotta;

  static const Color skyBlue = mutedBlue;
  static const Color skyLight = sand;
  static const Color skyCloud = cream;
  static const Color sunYellow = sunset;
  static const Color warmAmber = sunset;
  static const Color deepNavy = espressoNight;
  static const Color softSlate = mocha;
  static const Color mutedText = mocha;
  static const Color freshSage = sage;
  static const Color sunsetOrange = terracotta;

  static const Color primaryTerracotta = terracotta;
  static const Color primaryBlue = mutedBlue;
  static const Color primaryDark = espresso;
  static const Color secondaryCoral = terracotta;
  static const Color liveGreen = sage;
  static const Color accentAmber = sunset;
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color copper = caramel;

  // Light Canvas
  static const Color scaffoldLight = cream;
  static const Color cardLight = Colors.white;
  static const Color borderLight = sand;
  static const Color textPrimary = espresso;
  static const Color textSecondary = mocha;

  // Dark Canvas
  static const Color scaffoldDark = espressoNight;
  static const Color cardDark = espressoSurfaceDark;
  static const Color borderDark = sandBorderDark;
  static const Color textPrimaryDark = creamTextDark;
  static const Color textSecondaryDark = mochaTextDark;

  // Natural warm landscape gradients (restrained, no loud oranges)
  static const LinearGradient tripSunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4B2E21), Color(0xFF6F4A37)],
  );

  static const LinearGradient warmObsidianGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF35241B), Color(0xFF1E130D)],
  );

  static const LinearGradient cardHeaderGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF4B2E21), Color(0xFF35241B)],
  );

  static final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
    seedColor: espresso,
    brightness: Brightness.light,
    primary: espresso,
    onPrimary: Colors.white,
    primaryContainer: warmBeige,
    onPrimaryContainer: espresso,
    secondary: caramel,
    onSecondary: Colors.white,
    tertiary: terracotta,
    surface: cream,
    onSurface: espresso,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: warmBeige,
    surfaceContainer: sand,
    outline: sand,
    outlineVariant: warmBeige,
  );

  static final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
    seedColor: espresso,
    brightness: Brightness.dark,
    primary: caramel,
    onPrimary: Colors.white,
    primaryContainer: espressoCardDark,
    onPrimaryContainer: creamTextDark,
    secondary: sunset,
    onSecondary: Colors.white,
    tertiary: terracotta,
    surface: espressoNight,
    onSurface: creamTextDark,
    surfaceContainerLowest: Color(0xFF140C08),
    surfaceContainerLow: espressoSurfaceDark,
    surfaceContainer: espressoCardDark,
    outline: sandBorderDark,
    outlineVariant: sandBorderDark,
  );

  static ThemeData get lightTheme => _buildTheme(_lightColorScheme);
  static ThemeData get darkTheme => _buildTheme(_darkColorScheme);

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    // Base Inter text theme
    final baseInterTheme = isDark
        ? GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.interTextTheme(ThemeData.light().textTheme);

    // Apply Playfair Display to branding and headings; Inter for UI and body
    final customTextTheme = baseInterTheme.copyWith(
      displayLarge: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.displayLarge,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      displayMedium: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.displayMedium,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      displaySmall: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.displaySmall,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      headlineLarge: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.headlineLarge,
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
      ),
      headlineMedium: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.headlineMedium,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      headlineSmall: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.headlineSmall,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      titleLarge: GoogleFonts.playfairDisplay(
        textStyle: baseInterTheme.titleLarge,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        textStyle: baseInterTheme.titleMedium,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      titleSmall: GoogleFonts.inter(
        textStyle: baseInterTheme.titleSmall,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        textStyle: baseInterTheme.bodyLarge,
        color: colorScheme.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: baseInterTheme.bodyMedium,
        color: colorScheme.onSurface,
      ),
      bodySmall: GoogleFonts.inter(
        textStyle: baseInterTheme.bodySmall,
        color: isDark ? mochaTextDark : mocha,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: baseInterTheme.labelLarge,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: customTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? cardDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          side: BorderSide(color: isDark ? borderDark : borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? espressoSurfaceDark : cream,
        indicatorColor: espresso.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected
                ? espresso
                : (isDark ? mochaTextDark : mocha),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: isSelected
                ? espresso
                : (isDark ? mochaTextDark : mocha),
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: 14,
          ),
          backgroundColor: espresso,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: 14,
          ),
          backgroundColor: espresso,
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: 14,
          ),
          side: BorderSide(
            color: isDark ? borderDark : borderLight,
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? cardDark : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: isDark ? borderDark : borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: isDark ? borderDark : borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: const BorderSide(color: espresso, width: 1.5),
        ),
      ),
    );
  }
}
