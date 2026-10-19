import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';

/// Contexto del libro bajo el navbar global (no es un ítem del navbar).
class BookContextBar extends StatelessWidget {
  const BookContextBar({
    super.key,
    required this.title,
    required this.onBackToLibrary,
    required this.page,
    required this.pageCount,
    required this.onPrevPage,
    required this.onNextPage,
    this.bookmarked = false,
    this.onToggleBookmark,
    this.onOpenAssist,
  });

  final String title;
  final VoidCallback onBackToLibrary;
  final int page;
  final int pageCount;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onOpenAssist;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? const Color(0xFF0B1220).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.96),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            _LibraryBackPill(onTap: onBackToLibrary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (onToggleBookmark != null)
              IconButton(
                tooltip: 'Marcador',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleBookmark,
                icon: MIcon(
                  MargenLucide.bookmark,
                  size: 20,
                  color: bookmarked
                      ? AppTokens.purple
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            IconButton(
              tooltip: 'Página anterior',
              visualDensity: VisualDensity.compact,
              onPressed: page > 1 ? onPrevPage : null,
              icon: const MIcon(MargenLucide.chevronLeft, size: 20),
            ),
            Text(
              'PDF $page / $pageCount',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Página siguiente',
              visualDensity: VisualDensity.compact,
              onPressed: page < pageCount ? onNextPage : null,
              icon: const MIcon(MargenLucide.chevronRight, size: 20),
            ),
            if (onOpenAssist != null) ...[
              const SizedBox(width: 4),
              _IaPill(onTap: onOpenAssist!),
            ],
          ],
        ),
      ),
    );
  }
}

class _LibraryBackPill extends StatefulWidget {
  const _LibraryBackPill({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_LibraryBackPill> createState() => _LibraryBackPillState();
}

class _LibraryBackPillState extends State<_LibraryBackPill> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppTokens.purple.withValues(alpha: _hover ? 0.75 : 0.45),
          ),
          color: _hover
              ? AppTokens.purple.withValues(alpha: isDark ? 0.12 : 0.06)
              : Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MIcon(MargenLucide.back, size: 16, color: AppTokens.purple),
                  const SizedBox(width: 6),
                  Text(
                    'Biblioteca',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTokens.purple,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IaPill extends StatefulWidget {
  const _IaPill({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_IaPill> createState() => _IaPillState();
}

class _IaPillState extends State<_IaPill> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppTokens.purple.withValues(alpha: _hover ? 0.8 : 0.5),
          ),
          color: _hover
              ? AppTokens.purple.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MIcon(
                    MargenLucide.sparkles,
                    size: 14,
                    color: AppTokens.purple,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'IA',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppTokens.purple,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
