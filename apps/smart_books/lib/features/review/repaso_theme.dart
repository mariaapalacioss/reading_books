import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Colores de Repaso alineados con el tema claro/oscuro de la app.
class RepasoUi {
  RepasoUi(this.context);

  final BuildContext context;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get surface => Theme.of(context).colorScheme.surface;

  Color get surfaceContainer =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  Color get text => Theme.of(context).colorScheme.onSurface;

  Color get muted => Theme.of(context).colorScheme.onSurfaceVariant;

  Color get border => Theme.of(context).dividerColor;

  Color get purple => AppTokens.purple;

  Color get purpleStrong => AppTokens.purple;

  Color get purpleSoft => isDark
      ? AppTokens.purple.withValues(alpha: 0.2)
      : const Color(0xFFF4EFFE);

  Color get blue => const Color(0xFF218BF4);

  Color get blueSoft =>
      isDark ? blue.withValues(alpha: 0.18) : const Color(0xFFEAF5FF);

  Color get cyan => AppTokens.cyan;

  Color get cyanSoft =>
      isDark ? cyan.withValues(alpha: 0.18) : const Color(0xFFE5FAFD);

  Color get teal => AppTokens.teal;

  Color get tealSoft =>
      isDark ? teal.withValues(alpha: 0.18) : const Color(0xFFE4F9F5);

  Color get orange => AppTokens.warning;

  Color get orangeSoft =>
      isDark ? orange.withValues(alpha: 0.2) : const Color(0xFFFFF3DF);
}

extension RepasoUiBuildContext on BuildContext {
  RepasoUi get repaso => RepasoUi(this);
}
