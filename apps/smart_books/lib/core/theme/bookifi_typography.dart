import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

TextTheme buildBookifiTextTheme(Brightness brightness, TextTheme base) {
  final onSurface = brightness == Brightness.dark
      ? const Color(0xFFF8FAFC)
      : AppTokens.text;
  final onMuted = brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : AppTokens.textMuted;
  final sans = GoogleFonts.sourceSans3;

  return sansTextTheme(base).copyWith(
    displaySmall: sans(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.03,
      height: 1.15,
      color: onSurface,
    ),
    headlineSmall: sans(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.03,
      height: 1.2,
      color: onSurface,
    ),
    titleMedium: sans(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.02,
      height: 1.25,
      color: onSurface,
    ),
    titleSmall: sans(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.02,
      height: 1.3,
      color: onSurface,
    ),
    bodyLarge: sans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: onSurface,
    ),
    bodyMedium: sans(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.48,
      color: onSurface,
    ),
    bodySmall: sans(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: onMuted,
    ),
    labelLarge: sans(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.04,
      color: onMuted,
    ),
    labelSmall: sans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.08,
      color: onMuted,
    ),
  );
}

TextTheme sansTextTheme(TextTheme base) =>
    GoogleFonts.sourceSans3TextTheme(base);
