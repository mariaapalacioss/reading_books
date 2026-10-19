import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_controller.dart';

AppThemePreference themePreferenceFromMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => AppThemePreference.light,
    ThemeMode.dark => AppThemePreference.dark,
    ThemeMode.system => AppThemePreference.system,
  };
}

/// Selector visible de tema: sistema / claro / oscuro (sin cambiar la lógica de persistencia).
class AppThemeModeControl extends ConsumerWidget {
  const AppThemeModeControl({
    super.key,
    this.dense = false,
    this.showLabels = true,
  });

  final bool dense;
  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final selected = themePreferenceFromMode(themeMode);
    final width = MediaQuery.sizeOf(context).width;
    final labels = showLabels && !dense && width >= 1024;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(dense ? 2 : 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThemeModeSegment(
              tooltip: 'Tema del sistema',
              label: labels ? 'Sistema' : null,
              icon: Icons.brightness_auto_rounded,
              selected: selected == AppThemePreference.system,
              dense: dense,
              onTap: () => ref
                  .read(themeControllerProvider.notifier)
                  .setPreference(AppThemePreference.system),
            ),
            _ThemeModeSegment(
              tooltip: 'Tema claro',
              label: labels ? 'Claro' : null,
              icon: Icons.light_mode_outlined,
              selected: selected == AppThemePreference.light,
              dense: dense,
              onTap: () => ref
                  .read(themeControllerProvider.notifier)
                  .setPreference(AppThemePreference.light),
            ),
            _ThemeModeSegment(
              tooltip: 'Tema oscuro',
              label: labels ? 'Oscuro' : null,
              icon: Icons.dark_mode_outlined,
              selected: selected == AppThemePreference.dark,
              dense: dense,
              onTap: () => ref
                  .read(themeControllerProvider.notifier)
                  .setPreference(AppThemePreference.dark),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.dense,
    required this.onTap,
    this.label,
  });

  final String tooltip;
  final String? label;
  final IconData icon;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected
        ? (isDark ? Colors.white : const Color(0xFF1E1B4B))
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = selected
        ? (isDark
              ? const Color(0xFF6366F1).withValues(alpha: 0.45)
              : Colors.white)
        : Colors.transparent;

    final child = Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : (label != null ? 10 : 8),
            vertical: dense ? 6 : 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 18 : 19, color: fg),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Tooltip(message: tooltip, child: child);
  }
}
