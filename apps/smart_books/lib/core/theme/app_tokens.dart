import 'package:flutter/material.dart';

/// Tokens alineados con `src/styles/global.css` (Bookifi / Smart Books web).
abstract final class AppTokens {
  static const purple = Color(0xFF6222E0);
  static const purpleDeep = Color(0xFF5C16CB);
  static const teal = Color(0xFF00BABA);
  static const cyan = Color(0xFF0FCDEF);
  static const logoCyan = Color(0xFF4EE3F0);
  static const paper = Color(0xFFF0F0F7);

  static const text = Color(0xFF0F172A);
  static const textSoft = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  static const success = Color(0xFF12B76A);
  static const warning = Color(0xFFF79009);
  static const danger = Color(0xFFF04438);

  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 18.0;
  static const radiusXl = 24.0;

  static const pageMaxWidth = 1180.0;

  static BoxDecoration deskBackground(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF08111F) : paper;
    return BoxDecoration(
      color: bg,
      gradient: RadialGradient(
        center: const Alignment(-1, -1),
        radius: 1.2,
        colors: [
          purple.withValues(alpha: isDark ? 0.28 : 0.16),
          Colors.transparent,
        ],
        stops: const [0, 0.6],
      ),
    );
  }

  static List<BoxShadow> cardShadow(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return [
        BoxShadow(
          color: const Color(0xFF020617).withValues(alpha: 0.42),
          blurRadius: 44,
          offset: const Offset(0, 18),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
        blurRadius: 26,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
