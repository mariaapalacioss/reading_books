import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../data/models/chapter.dart';

/// Layout del lector: capítulos | PDF | asistencia (solo UI).
class ReaderLayout extends StatelessWidget {
  const ReaderLayout({
    super.key,
    required this.isWide,
    required this.chapters,
    required this.currentPage,
    required this.onChapter,
    required this.onAssist,
    required this.readerTop,
    required this.readerBottom,
    required this.body,
    this.statusDetail,
    this.assistPanel,
    this.immersive = false,
  });

  final bool isWide;
  final bool immersive;
  final List<Chapter> chapters;
  final int currentPage;
  final ValueChanged<Chapter> onChapter;
  final VoidCallback onAssist;
  final Widget readerTop;
  final Widget readerBottom;
  final Widget body;
  final String? statusDetail;
  final Widget? assistPanel;

  @override
  Widget build(BuildContext context) {
    final readerColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        readerTop,
        if (statusDetail != null && statusDetail!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _StatusStrip(text: statusDetail!),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: readerBottom,
        ),
      ],
    );

    if (immersive) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _ReaderSurface(child: readerColumn),
      );
    }

    if (!isWide) {
      return Column(
        children: [
          Expanded(child: readerColumn),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAssist,
                  icon: const MIcon(
                    MargenLucide.sparkles,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text('Asistencia'),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final chapterSidebar = ChapterSidebar(
      chapters: chapters,
      currentPage: currentPage,
      onChapter: onChapter,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 260, child: chapterSidebar),
          const SizedBox(width: 16),
          Expanded(child: _ReaderSurface(child: readerColumn)),
          const SizedBox(width: 16),
          SizedBox(
            width: 340,
            child: _ReaderSurface(
              subtle: true,
              child:
                  assistPanel ??
                  Center(
                    child: Text(
                      'Asistencia',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChapterSidebar extends StatelessWidget {
  const ChapterSidebar({
    super.key,
    required this.chapters,
    required this.currentPage,
    required this.onChapter,
  });

  final List<Chapter> chapters;
  final int currentPage;
  final ValueChanged<Chapter> onChapter;

  @override
  Widget build(BuildContext context) {
    return _ReaderSurface(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Capítulos',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          for (final ch in chapters)
            _ChapterTile(
              ch: ch,
              selected:
                  currentPage >= ch.startPage && currentPage <= ch.endPage,
              onTap: () => onChapter(ch),
            ),
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.ch,
    required this.selected,
    required this.onTap,
  });

  final Chapter ch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppTokens.purple.withValues(alpha: isDark ? 0.22 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MIconBox(
                  icon: MargenLucide.fileText,
                  selected: selected,
                  size: 38,
                  iconSize: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PDF ${ch.startPage}–${ch.endPage} · ${ch.analysisStatus}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSurface extends StatelessWidget {
  const _ReaderSurface({required this.child, this.subtle = false});

  final Widget child;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.65)
            : Colors.white,
        border: Border.all(
          color: Theme.of(
            context,
          ).dividerColor.withValues(alpha: subtle ? 0.35 : 0.55),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: child,
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        color: AppTokens.teal.withValues(alpha: 0.12),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTokens.teal),
      ),
    );
  }
}
