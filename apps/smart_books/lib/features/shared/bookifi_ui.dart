import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_tokens.dart';

class BookifiCard extends StatefulWidget {
  const BookifiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  State<BookifiCard> createState() => _BookifiCardState();
}

class _BookifiCardState extends State<BookifiCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;

    final radius = BorderRadius.circular(AppTokens.radiusLg);

    Widget inner = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      transform: _hover && widget.onTap != null
          ? (Matrix4.identity()..translate(0.0, -2.0))
          : Matrix4.identity(),
      padding: widget.padding,
      decoration: BoxDecoration(boxShadow: AppTokens.cardShadow(brightness)),
      child: widget.child,
    );

    Widget card = Material(
      color: surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
      child: widget.onTap != null
          ? InkWell(onTap: widget.onTap, borderRadius: radius, child: inner)
          : inner,
    );

    if (widget.onTap != null) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: card,
      );
    }
    return card;
  }
}

class BookifiPrimaryButton extends StatefulWidget {
  const BookifiPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  State<BookifiPrimaryButton> createState() => _BookifiPrimaryButtonState();
}

class _BookifiPrimaryButtonState extends State<BookifiPrimaryButton> {
  var _hover = false;

  ButtonStyle _buttonStyle(bool hover) {
    return FilledButton.styleFrom(
      backgroundColor: hover ? AppTokens.purpleDeep : AppTokens.purple,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: enabled && _hover
            ? (Matrix4.identity()..translate(0.0, -1.0))
            : Matrix4.identity(),
        child: widget.icon != null || widget.loading
            ? FilledButton.icon(
                onPressed: enabled ? widget.onPressed : null,
                icon: widget.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(widget.icon),
                label: Text(widget.label),
                style: _buttonStyle(_hover && enabled),
              )
            : FilledButton(
                onPressed: enabled ? widget.onPressed : null,
                style: _buttonStyle(_hover && enabled),
                child: widget.loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.label),
              ),
      ),
    );
  }
}

class BookifiGhostButton extends StatelessWidget {
  const BookifiGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.danger = false,
    this.compact = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = danger
        ? AppTokens.danger
        : (isDark ? AppTokens.purple : AppTokens.purpleDeep);
    final enabled = onPressed != null && !loading;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: isDark ? null : Colors.white,
        side: BorderSide(
          color: danger
              ? color.withValues(alpha: 0.4)
              : (isDark ? color.withValues(alpha: 0.35) : AppTokens.border),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 8 : 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontSize: compact ? 12 : 13,
        ),
      ),
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: compact ? 14 : 16,
                  height: compact ? 14 : 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
                const SizedBox(width: 8),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}

class BookifiSectionLabel extends StatelessWidget {
  const BookifiSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class BookifiChip extends StatelessWidget {
  const BookifiChip(
    this.label, {
    super.key,
    this.teal = false,
    this.warn = false,
  });

  final String label;
  final bool teal;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bg;
    Color fg;
    if (warn) {
      bg = AppTokens.warning.withValues(alpha: isDark ? 0.22 : 0.18);
      fg = AppTokens.warning;
    } else if (teal) {
      bg = AppTokens.teal.withValues(alpha: isDark ? 0.22 : 0.18);
      fg = isDark ? AppTokens.logoCyan : const Color(0xFF065F5F);
    } else {
      bg = AppTokens.purple.withValues(alpha: isDark ? 0.22 : 0.12);
      fg = isDark ? AppTokens.logoCyan : AppTokens.purple;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.02,
          color: fg,
        ),
      ),
    );
  }
}

class BookifiProgressBar extends StatelessWidget {
  const BookifiProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.purple),
      ),
    );
  }
}

/// Acento púrpura a la izquierda con esquinas redondeadas.
///
/// Flutter no permite `borderRadius` junto a un [Border] con colores distintos por lado;
/// este widget evita el error *"A borderRadius can only be given on borders with uniform colors"*.
class BookifiLeftAccent extends StatelessWidget {
  const BookifiLeftAccent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.accentWidth = 4,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final double accentWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.45 : 0.65,
        );
    final borderColor = Theme.of(context).dividerColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: accentWidth, color: AppTokens.purple),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    top: BorderSide(color: borderColor),
                    right: BorderSide(color: borderColor),
                    bottom: BorderSide(color: borderColor),
                  ),
                ),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookifiCallout extends StatelessWidget {
  const BookifiCallout(
    this.text, {
    super.key,
    this.good = false,
    this.bad = false,
  });

  final String text;
  final bool good;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final border = bad
        ? AppTokens.danger.withValues(alpha: 0.45)
        : good
        ? AppTokens.teal.withValues(alpha: 0.5)
        : Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: border),
        color: isDark
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.85)
            : Colors.white,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class BookifiBrand extends StatelessWidget {
  const BookifiBrand({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/brand/logo-bookifi.svg',
          width: compact ? 72 : 92,
          height: 28,
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Smart Books',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.03,
                ),
              ),
              Text(
                'BY BOOKIFI',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.08,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class BookifiPage extends StatelessWidget {
  const BookifiPage({super.key, required this.child, this.scroll = true});

  final Widget child;

  /// Si es false, el hijo recibe altura acotada (p. ej. columnas con [Expanded]).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final compactTop = MediaQuery.viewPaddingOf(context).top > 20;
        Widget body = Padding(
          padding: EdgeInsets.fromLTRB(16, compactTop ? 12 : 28, 16, 64),
          child: child,
        );
        if (scroll) {
          body = SingleChildScrollView(child: body);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppTokens.pageMaxWidth,
              maxHeight: maxH,
            ),
            child: body,
          ),
        );
      },
    );
  }
}
