import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'bookifi_typography.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF0B1220) : Colors.white;
  final surfaceMuted = isDark
      ? const Color(0xFF111827)
      : const Color(0xFFF8FAFC);
  final onSurface = isDark ? const Color(0xFFF8FAFC) : AppTokens.text;
  final onMuted = isDark ? const Color(0xFF94A3B8) : AppTokens.textMuted;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? const Color(0xFF08111F) : AppTokens.paper,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: AppTokens.purple,
      onPrimary: Colors.white,
      secondary: AppTokens.teal,
      onSecondary: const Color(0xFF062A2A),
      tertiary: AppTokens.cyan,
      surface: surface,
      onSurface: onSurface,
      error: AppTokens.danger,
      onError: Colors.white,
    ),
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
    borderSide: BorderSide(color: isDark ? Colors.white12 : AppTokens.border),
  );

  final textTheme = buildBookifiTextTheme(brightness, base.textTheme);

  return base.copyWith(
    textTheme: textTheme,
    dividerColor: isDark ? Colors.white12 : AppTokens.border,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(color: isDark ? Colors.white12 : AppTokens.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? surface : const Color(0xFFF8FAFC),
      hintStyle: TextStyle(color: onMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(
        color: onMuted,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppTokens.purple, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? AppTokens.purple : AppTokens.purpleDeep,
        side: BorderSide(
          color: isDark
              ? AppTokens.purple.withValues(alpha: 0.35)
              : AppTokens.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: textTheme.labelLarge?.copyWith(
          color: isDark ? AppTokens.purple : AppTokens.purpleDeep,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      elevation: 8,
    ),
    colorScheme: base.colorScheme.copyWith(
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: onMuted,
    ),
  );
}
