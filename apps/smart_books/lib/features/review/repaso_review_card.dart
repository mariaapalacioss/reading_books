import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import 'repaso_models.dart';
import 'repaso_source_text.dart';
import 'repaso_qa_store.dart';
import 'repaso_review_flow.dart';

(IconData, Color, Color) _visual(ReviewSourceType type) => switch (type) {
  ReviewSourceType.resaltado => (
    MargenLucide.bookmark,
    _ReviewColors.purple,
    _ReviewColors.purpleSoft,
  ),
  ReviewSourceType.tarjeta => (
    MargenLucide.notebookTabs,
    _ReviewColors.blue,
    _ReviewColors.blueSoft,
  ),
  ReviewSourceType.resumen => (
    MargenLucide.fileText,
    _ReviewColors.purple,
    _ReviewColors.purpleSoft,
  ),
  ReviewSourceType.punto => (
    MargenLucide.star,
    _ReviewColors.orange,
    _ReviewColors.orangeSoft,
  ),
  ReviewSourceType.fragmento => (
    MargenLucide.scanLine,
    _ReviewColors.cyan,
    _ReviewColors.cyanSoft,
  ),
};

abstract final class _ReviewColors {
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF11182A);
  static const muted = Color(0xFF66758F);
  static const border = Color(0xFFE1E5EF);

  static const purple = Color(0xFF6222E0);
  static const purpleSoft = Color(0xFFF1EAFE);

  static const blue = Color(0xFF228CF5);
  static const blueSoft = Color(0xFFEAF5FF);

  static const cyan = Color(0xFF0FCDEF);
  static const cyanSoft = Color(0xFFE4F9FD);

  static const orange = Color(0xFFE89200);
  static const orangeSoft = Color(0xFFFFF2DB);

  static const teal = Color(0xFF00A68F);
  static const tealSoft = Color(0xFFE4F8F2);

  static const danger = Color(0xFFF05252);
}

enum _MoreAction { openBook, origin, reviewed, pending, delete }

class RepasoReviewCard extends ConsumerStatefulWidget {
  const RepasoReviewCard({
    super.key,
    required this.entry,
    this.onReviewed,
    this.onRepasar,
    this.onDelete,
    this.onReviewedHighlight,
    this.onRepasarHighlight,
    this.onRepasoDataChanged,
  });

  final ReviewListEntry entry;

  final VoidCallback? onReviewed;
  final VoidCallback? onRepasar;
  final VoidCallback? onDelete;

  final VoidCallback? onReviewedHighlight;
  final VoidCallback? onRepasarHighlight;
  final VoidCallback? onRepasoDataChanged;

  @override
  ConsumerState<RepasoReviewCard> createState() => _RepasoReviewCardState();
}

class _RepasoReviewCardState extends ConsumerState<RepasoReviewCard> {
  bool _expanded = false;
  int _persistedQaCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshQaCount();
  }

  @override
  void didUpdateWidget(covariant RepasoReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) _refreshQaCount();
  }

  Future<void> _refreshQaCount() async {
    final repo = ref.read(booksRepositoryProvider);
    final rows = await listPersistedQaForEntry(
      repo,
      entry: widget.entry,
      bookTitle: widget.entry.bookTitle,
      chapterTitle: widget.entry.chapterTitle,
    );
    if (!mounted) return;
    setState(() => _persistedQaCount = rows.length);
  }

  int get _flashcardCount {
    if (_persistedQaCount > 0) return _persistedQaCount;
    if (widget.entry.card != null && isPersistedQa(widget.entry.card!))
      return 1;
    return 0;
  }

  bool get _canRepasar {
    if (_persistedQaCount > 0) return true;
    if (widget.entry.card != null && isPersistedQa(widget.entry.card!))
      return true;
    if (widget.entry.highlight != null) return true;
    if (widget.entry.card != null) return true;
    if (widget.entry.point != null) return true;
    return false;
  }

  VoidCallback? get _reviewCallback {
    if (widget.entry.card != null) {
      return widget.onReviewed;
    }

    if (widget.entry.highlight != null) {
      return widget.onReviewedHighlight;
    }

    return null;
  }

  VoidCallback? get _repasarCallback {
    if (widget.entry.card != null) {
      return widget.onRepasar;
    }

    if (widget.entry.highlight != null) {
      return widget.onRepasarHighlight;
    }

    return null;
  }

  void _openSession() {
    runRepasoReviewFlow(
      context,
      ref,
      entry: widget.entry,
      onReviewedLegacy: () {
        _reviewCallback?.call();
        _refreshQaCount();
      },
      onRepasarLegacy: () {
        _repasarCallback?.call();
        _refreshQaCount();
      },
      onRepasoDataChanged: () {
        widget.onRepasoDataChanged?.call();
        _refreshQaCount();
      },
    );
  }

  void _openBook() {
    final page = widget.entry.pageNumber;

    if (page == null) return;

    context.push('/libro/${widget.entry.bookId}?page=$page');
  }

  Future<void> _handleMenuAction(_MoreAction action) async {
    switch (action) {
      case _MoreAction.openBook:
        _openBook();

      case _MoreAction.origin:
        // Preserva el comportamiento actual de "Ver origen".
        _openSession();

      case _MoreAction.reviewed:
        _reviewCallback?.call();

      case _MoreAction.pending:
        _repasarCallback?.call();

      case _MoreAction.delete:
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final preview = repasoDisplayExcerpt(entry).replaceAll('\n', ' ').trim();
    final displayTitle = repasoDisplayTitle(entry);

    final (icon, accent, softColor) = _visual(entry.sourceType);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop/tablet amplio = fila horizontal.
        final compact = constraints.maxWidth >= 820;

        if (compact) {
          return _DesktopReviewRow(
            entry: entry,
            icon: icon,
            accent: accent,
            softColor: softColor,
            preview: preview,
            displayTitle: displayTitle,
            flashcardCount: _flashcardCount,
            canRepasar: _canRepasar,
            onRepasar: _canRepasar ? _openSession : null,
            onOpenBook: entry.pageNumber != null ? _openBook : null,
            onMenuAction: _handleMenuAction,
            canMarkReviewed: _reviewCallback != null,
            canMarkPending: _repasarCallback != null,
            canDelete: widget.onDelete != null,
          );
        }

        return _MobileReviewCard(
          entry: entry,
          icon: icon,
          accent: accent,
          softColor: softColor,
          preview: preview,
          displayTitle: displayTitle,
          expanded: _expanded,
          flashcardCount: _flashcardCount,
          canRepasar: _canRepasar,
          onToggleExpanded: () {
            setState(() {
              _expanded = !_expanded;
            });
          },
          onRepasar: _canRepasar ? _openSession : null,
          onOpenBook: entry.pageNumber != null ? _openBook : null,
          onMenuAction: _handleMenuAction,
          canMarkReviewed: _reviewCallback != null,
          canMarkPending: _repasarCallback != null,
          canDelete: widget.onDelete != null,
        );
      },
    );
  }
}

class _DesktopReviewRow extends StatelessWidget {
  const _DesktopReviewRow({
    required this.entry,
    required this.icon,
    required this.accent,
    required this.softColor,
    required this.preview,
    required this.displayTitle,
    required this.flashcardCount,
    required this.canRepasar,
    required this.onRepasar,
    required this.onOpenBook,
    required this.onMenuAction,
    required this.canMarkReviewed,
    required this.canMarkPending,
    required this.canDelete,
  });

  final ReviewListEntry entry;

  final IconData icon;
  final Color accent;
  final Color softColor;

  final String preview;
  final String displayTitle;
  final int flashcardCount;
  final bool canRepasar;

  final VoidCallback? onRepasar;
  final VoidCallback? onOpenBook;

  final ValueChanged<_MoreAction> onMenuAction;

  final bool canMarkReviewed;
  final bool canMarkPending;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          // =========================================
          // ICON
          // =========================================
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: MIcon(icon, size: 20, color: accent),
          ),

          const SizedBox(width: 12),

          // =========================================
          // TYPE
          // =========================================
          SizedBox(
            width: 92,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _TypeBadge(
                label: entry.sourceType.label,
                accent: accent,
                background: softColor,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // =========================================
          // TITLE + PREVIEW
          // =========================================
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 16),

          // =========================================
          // SOURCE / PDF
          // =========================================
          SizedBox(width: 100, child: _SourceInfo(entry: entry)),

          const SizedBox(width: 12),

          // =========================================
          // STATUS
          // =========================================
          SizedBox(
            width: 105,
            child: Align(
              alignment: Alignment.center,
              child: _StatusPill(
                reviewed: entry.reviewed,
                pending: entry.pending && !entry.reviewed,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // =========================================
          // PRIMARY ACTION
          // =========================================
          SizedBox(
            width: 142,
            child: Align(
              alignment: Alignment.centerRight,
              child: _PrimaryAction(
                entry: entry,
                canRepasar: canRepasar,
                flashcardCount: flashcardCount,
                onRepasar: onRepasar,
                onOpenBook: onOpenBook,
                accent: accent,
              ),
            ),
          ),

          const SizedBox(width: 6),

          // =========================================
          // MORE
          // =========================================
          _MoreMenu(
            entry: entry,
            canRepasar: canRepasar,
            canMarkReviewed: canMarkReviewed,
            canMarkPending: canMarkPending,
            canDelete: canDelete,
            onSelected: onMenuAction,
          ),
        ],
      ),
    );
  }
}

class _MobileReviewCard extends StatelessWidget {
  const _MobileReviewCard({
    required this.entry,
    required this.icon,
    required this.accent,
    required this.softColor,
    required this.preview,
    required this.displayTitle,
    required this.expanded,
    required this.flashcardCount,
    required this.canRepasar,
    required this.onToggleExpanded,
    required this.onRepasar,
    required this.onOpenBook,
    required this.onMenuAction,
    required this.canMarkReviewed,
    required this.canMarkPending,
    required this.canDelete,
  });

  final ReviewListEntry entry;

  final IconData icon;
  final Color accent;
  final Color softColor;

  final String preview;
  final String displayTitle;
  final bool expanded;

  final int flashcardCount;
  final bool canRepasar;

  final VoidCallback onToggleExpanded;
  final VoidCallback? onRepasar;
  final VoidCallback? onOpenBook;

  final ValueChanged<_MoreAction> onMenuAction;

  final bool canMarkReviewed;
  final bool canMarkPending;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: softColor,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: MIcon(icon, size: 20, color: accent),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _TypeBadge(
                          label: entry.sourceType.label,
                          accent: accent,
                          background: softColor,
                        ),
                        _StatusPill(
                          reviewed: entry.reviewed,
                          pending: entry.pending && !entry.reviewed,
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(
                      displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              _MoreMenu(
                entry: entry,
                canRepasar: canRepasar,
                canMarkReviewed: canMarkReviewed,
                canMarkPending: canMarkPending,
                canDelete: canDelete,
                onSelected: onMenuAction,
              ),
            ],
          ),

          if (preview.isNotEmpty) ...[
            const SizedBox(height: 12),

            Text(
              preview,
              maxLines: expanded ? null : 2,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),

            if (preview.length > 130)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onToggleExpanded,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(top: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    expanded ? 'Ver menos' : 'Ver más',
                    style: const TextStyle(
                      color: _ReviewColors.purple,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _SourceInfo(entry: entry)),

              const SizedBox(width: 10),

              _PrimaryAction(
                entry: entry,
                canRepasar: canRepasar,
                flashcardCount: flashcardCount,
                onRepasar: onRepasar,
                onOpenBook: onOpenBook,
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.accent,
    required this.background,
  });

  final String label;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SourceInfo extends StatelessWidget {
  const _SourceInfo({required this.entry});

  final ReviewListEntry entry;

  @override
  Widget build(BuildContext context) {
    final page = entry.pageNumber;

    if (page != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MIcon(
            MargenLucide.fileText,
            size: 14,
            color: _ReviewColors.muted,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'PDF $page',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ReviewColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (entry.chapterTitle != null && entry.chapterTitle!.trim().isNotEmpty) {
      return Text(
        entry.chapterTitle!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _ReviewColors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.reviewed, required this.pending});

  final bool reviewed;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    if (reviewed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _ReviewColors.tealSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MIcon(
              MargenLucide.checkCircle,
              size: 14,
              color: _ReviewColors.teal,
            ),
            SizedBox(width: 5),
            Text(
              'Revisado',
              style: TextStyle(
                color: _ReviewColors.teal,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (pending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _ReviewColors.orangeSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MIcon(MargenLucide.clock, size: 14, color: _ReviewColors.orange),
            SizedBox(width: 5),
            Text(
              'Pendiente',
              style: TextStyle(
                color: _ReviewColors.orange,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.entry,
    required this.canRepasar,
    required this.flashcardCount,
    required this.onRepasar,
    required this.onOpenBook,
    required this.accent,
  });

  final ReviewListEntry entry;
  final bool canRepasar;
  final int flashcardCount;

  final VoidCallback? onRepasar;
  final VoidCallback? onOpenBook;

  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (canRepasar && onRepasar != null) {
      return _OutlineActionButton(
        label: 'Repasar',
        icon: Icons.play_arrow_rounded,
        onPressed: onRepasar!,
      );
    }

    if (onOpenBook != null) {
      return _OutlineActionButton(
        label: 'Abrir en el libro',
        icon: Icons.menu_book_rounded,
        onPressed: onOpenBook!,
      );
    }

    return const SizedBox.shrink();
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ReviewColors.purple,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFB78BFC)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.entry,
    required this.canRepasar,
    required this.canMarkReviewed,
    required this.canMarkPending,
    required this.canDelete,
    required this.onSelected,
  });

  final ReviewListEntry entry;

  final bool canRepasar;
  final bool canMarkReviewed;
  final bool canMarkPending;
  final bool canDelete;

  final ValueChanged<_MoreAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MoreAction>(
      tooltip: 'Más opciones',
      onSelected: onSelected,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      itemBuilder: (context) {
        return [
          if (entry.pageNumber != null)
            const PopupMenuItem(
              value: _MoreAction.openBook,
              child: _MenuItem(
                icon: Icons.menu_book_rounded,
                label: 'Abrir en el libro',
              ),
            ),

          if (canRepasar)
            const PopupMenuItem(
              value: _MoreAction.origin,
              child: _MenuItem(
                icon: Icons.visibility_outlined,
                label: 'Ver origen',
              ),
            ),

          if (canMarkReviewed && !entry.reviewed)
            const PopupMenuItem(
              value: _MoreAction.reviewed,
              child: _MenuItem(
                icon: Icons.check_circle_outline_rounded,
                label: 'Marcar revisado',
              ),
            ),

          if (canMarkPending)
            const PopupMenuItem(
              value: _MoreAction.pending,
              child: _MenuItem(
                icon: Icons.refresh_rounded,
                label: 'Repasar después',
              ),
            ),

          if (canDelete)
            const PopupMenuItem(
              value: _MoreAction.delete,
              child: _MenuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Quitar',
                danger: true,
              ),
            ),
        ];
      },
      child: const SizedBox(
        width: 36,
        height: 38,
        child: Center(
          child: Icon(
            Icons.more_vert_rounded,
            size: 20,
            color: _ReviewColors.muted,
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? _ReviewColors.danger : _ReviewColors.text;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
