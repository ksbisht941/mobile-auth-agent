import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF19096A);
  static const Color text = Color(0xFF3B3B3B);
  static const Color background = Color(0xFFFFFFFF);
  static const Color shadow = Color(0x0A000000);
  static const Color secondaryBorder = Color(0x3319096A);
  static const Color panelBorder = Color(0x14000000);
  static const Color mutedText = Color(0x993B3B3B);
}

ThemeData buildAppTheme() {
  final baseTheme = ThemeData(useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    secondary: AppColors.primary,
    surface: AppColors.background,
  );
  final textTheme = GoogleFonts.sarabunTextTheme(
    baseTheme.textTheme,
  ).apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 4,
      shadowColor: AppColors.shadow,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.sarabun(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      toolbarTextStyle: GoogleFonts.sarabun(
        color: AppColors.text,
        fontSize: 14,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
        shadowColor: Colors.transparent,
        side: const BorderSide(color: AppColors.secondaryBorder),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.panelBorder,
      space: 1,
      thickness: 1,
    ),
  );
}