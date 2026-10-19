import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_tokens.dart';

/// Iconografía Lucide consistente (outline, trazo fino).
class MIcon extends StatelessWidget {
  const MIcon(this.icon, {super.key, this.size = 18, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Icon(icon, size: size, color: fg);
  }
}

/// Contenedor cuadrado redondeado como en el mockup del lector.
class MIconBox extends StatelessWidget {
  const MIconBox({
    super.key,
    required this.icon,
    this.selected = false,
    this.size = 38,
    this.iconSize = 18,
    this.color,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final bool selected;
  final double size;
  final double iconSize;
  final Color? color;

  /// Fondo e icono tintados (p. ej. morado resaltados, cyan tarjetas).
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    if (accent != null) {
      bg = accent!.withValues(alpha: isDark ? 0.28 : 0.14);
      fg = color ?? accent!;
    } else if (selected) {
      bg = AppTokens.purple.withValues(alpha: isDark ? 0.45 : 0.18);
      fg = color ?? Colors.white;
    } else {
      bg = isDark
          ? const Color(0xFF1E293B)
          : const Color(0xFFE2E8F0).withValues(alpha: 0.65);
      fg = color ?? (isDark ? AppTokens.textSoft : AppTokens.textMuted);
    }

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: selected
            ? Border.all(color: AppTokens.purple.withValues(alpha: 0.5))
            : null,
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );

    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: box,
      ),
    );
  }
}

/// Botón de acción del panel de asistencia (icono izquierda, chevron derecha).
class MargenAssistAction extends StatefulWidget {
  const MargenAssistAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.loading = false,
    this.iconAccent,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final Color? iconAccent;

  @override
  State<MargenAssistAction> createState() => _MargenAssistActionState();
}

class _MargenAssistActionState extends State<MargenAssistAction> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.loading;
    final disabled = widget.onPressed == null;

    Color bg;
    Color fg;
    BorderSide border;
    if (widget.primary && enabled) {
      bg = _hover ? AppTokens.purpleDeep : AppTokens.purple;
      fg = Colors.white;
      border = BorderSide.none;
    } else if (disabled) {
      bg = isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.black.withValues(alpha: 0.02);
      fg = Theme.of(context).disabledColor;
      border = BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
      );
    } else {
      bg = _hover
          ? AppTokens.purple.withValues(alpha: isDark ? 0.12 : 0.06)
          : (isDark
                ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                : Colors.white);
      fg = isDark ? AppTokens.textSoft : AppTokens.text;
      border = BorderSide(
        color: AppTokens.purple.withValues(alpha: _hover ? 0.55 : 0.35),
      );
    }

    final opacity = disabled ? 0.48 : 1.0;

    return Opacity(
      opacity: opacity,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border == BorderSide.none
                ? null
                : Border.fromBorderSide(border),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    if (widget.loading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.primary
                              ? Colors.white
                              : AppTokens.purple,
                        ),
                      )
                    else if (widget.iconAccent != null && !widget.primary)
                      MIconBox(
                        icon: widget.icon,
                        size: 32,
                        iconSize: 16,
                        accent: widget.iconAccent,
                      )
                    else
                      MIcon(
                        widget.icon,
                        size: 18,
                        color: widget.primary && enabled ? Colors.white : fg,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.primary && enabled ? Colors.white : fg,
                        ),
                      ),
                    ),
                    MIcon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: widget.primary && enabled
                          ? Colors.white.withValues(alpha: 0.85)
                          : (disabled
                                ? fg
                                : AppTokens.purple.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Atajos de iconos Lucide usados en Margen.
abstract final class MargenLucide {
  static const library = LucideIcons.libraryBig;
  static const search = LucideIcons.search;
  static const review = LucideIcons.graduationCap;
  static const themeLight = LucideIcons.sun;
  static const themeDark = LucideIcons.moon;
  static const profile = LucideIcons.circleUser;
  static const back = LucideIcons.arrowLeft;
  static const bookmark = LucideIcons.bookmark;
  static const bookmarkOutline = LucideIcons.bookmark;
  static const chevronLeft = LucideIcons.chevronLeft;
  static const chevronRight = LucideIcons.chevronRight;
  static const sparkles = LucideIcons.sparkles;
  static const fileText = LucideIcons.fileText;
  static const listChecks = LucideIcons.listChecks;
  static const messageCircle = LucideIcons.messageCircle;
  static const scanLine = LucideIcons.scanLine;
  static const star = LucideIcons.star;
  static const send = LucideIcons.send;
  static const minus = LucideIcons.minus;
  static const plus = LucideIcons.plus;
  static const fitPage = LucideIcons.panelsTopLeft;
  static const fullscreen = LucideIcons.maximize2;
  static const chapters = LucideIcons.fileText;
  static const circleHelp = LucideIcons.circleHelp;
  static const notebookTabs = LucideIcons.notebookTabs;
  static const checkCircle = LucideIcons.checkCircle2;
  static const clock = LucideIcons.clock3;
}
