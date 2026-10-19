import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../data/models/book.dart';
import '../shared/book_status_labels.dart';
import '../shared/bookifi_ui.dart';
import 'repaso_data.dart';
import 'repaso_generated_questions_page.dart';
import 'repaso_models.dart';
import 'repaso_session_page.dart';
import 'repaso_review_card.dart';
import 'repaso_source_text.dart';
import 'repaso_theme.dart';

abstract final class _RepasoColors {
  static const surface = Color(0xFFFFFFFF);

  static const text = Color(0xFF11182A);
  static const muted = Color(0xFF65738C);

  static const border = Color(0xFFE1E5EF);

  static const purple = Color(0xFF6222E0);
  static const purpleStrong = Color(0xFF601DE8);
  static const purpleSoft = Color(0xFFF4EFFE);

  static const blue = Color(0xFF218BF4);
  static const blueSoft = Color(0xFFEAF5FF);

  static const cyan = Color(0xFF0FCDEF);
  static const cyanSoft = Color(0xFFE5FAFD);

  static const teal = Color(0xFF00AAA5);
  static const tealSoft = Color(0xFFE4F9F5);

  static const orange = Color(0xFFE18A00);
  static const orangeSoft = Color(0xFFFFF3DF);
}

enum _RepasoContentFilter {
  todos,
  resaltados,
  tarjetas,
  resumenes,
  puntos,
  fragmentos,
}

enum _ReviewSort { recientes, antiguos, pendientes, revisados }

enum _StatusFilter { todos, revisado, pendiente }

class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final _searchCtrl = TextEditingController();

  _RepasoContentFilter _filter = _RepasoContentFilter.todos;
  _ReviewSort _sort = _ReviewSort.recientes;
  _StatusFilter _statusFilter = _StatusFilter.todos;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repasoReloadTickProvider);
    final booksAsync = ref.watch(_booksProvider);
    final search = _searchCtrl.text.trim().toLowerCase();

    final scheme = Theme.of(context).colorScheme;
    final body = booksAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: scheme.primary)),
      error: (error, _) => Center(child: Text('$error')),
      data: (books) {
        if (books.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repaso',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sube un libro y guarda contenido para comenzar a repasar.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              searchCtrl: _searchCtrl,
              onSearchChanged: () {
                setState(() {});
              },
            ),
            const SizedBox(height: 22),

            _GlobalReviewToolbar(
              filter: _filter,
              sort: _sort,
              statusFilter: _statusFilter,
              onFilter: (value) {
                setState(() {
                  _filter = value;
                });
              },
              onSort: (value) {
                setState(() {
                  _sort = value;
                });
              },
              onStatus: (value) {
                setState(() {
                  _statusFilter = value;
                });
              },
            ),

            const SizedBox(height: 20),

            _RepasoGeneratedQuestionsSection(books: books),

            const SizedBox(height: 20),

            for (var i = 0; i < books.length; i++)
              _BookReviewSection(
                key: ValueKey(
                  '${books[i].id}-${ref.watch(repasoReloadTickProvider)}',
                ),
                book: books[i],
                initiallyExpanded: i == 0,
                searchQuery: search,
                filter: _filter,
                sort: _sort,
                statusFilter: _statusFilter,
              ),
          ],
        );
      },
    );

    return BookifiPage(child: body);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.searchCtrl, required this.onSearchChanged});

  final TextEditingController searchCtrl;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final surface = scheme.surface;
    final border = Theme.of(context).dividerColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Repaso',
              style: TextStyle(
                color: onSurface,
                fontSize: 27,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Resaltados, tarjetas de estudio y puntos importantes por libro.',
              style: TextStyle(
                color: muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

        final search = SizedBox(
          width: stacked ? double.infinity : 360,
          height: 44,
          child: TextField(
            controller: searchCtrl,
            onChanged: (_) => onSearchChanged(),
            style: TextStyle(color: onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar en todos los repasos...',
              hintStyle: TextStyle(color: muted, fontSize: 14),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 14, right: 10),
                child: MIcon(
                  MargenLucide.search,
                  size: 20,
                  color: _RepasoColors.muted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: _RepasoColors.purple,
                  width: 1.4,
                ),
              ),
            ),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 16), search],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 24),
            search,
          ],
        );
      },
    );
  }
}

class _GlobalReviewToolbar extends StatelessWidget {
  const _GlobalReviewToolbar({
    required this.filter,
    required this.sort,
    required this.statusFilter,
    required this.onFilter,
    required this.onSort,
    required this.onStatus,
  });

  final _RepasoContentFilter filter;
  final _ReviewSort sort;
  final _StatusFilter statusFilter;

  final ValueChanged<_RepasoContentFilter> onFilter;
  final ValueChanged<_ReviewSort> onSort;
  final ValueChanged<_StatusFilter> onStatus;

  @override
  Widget build(BuildContext context) {
    const filters = [
      (_RepasoContentFilter.todos, 'Todos'),
      (_RepasoContentFilter.resaltados, 'Resaltados'),
      (_RepasoContentFilter.tarjetas, 'Tarjetas'),
      (_RepasoContentFilter.resumenes, 'Resúmenes'),
      (_RepasoContentFilter.puntos, 'Puntos importantes'),
      (_RepasoContentFilter.fragmentos, 'Fragmentos'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 920;

        final filterBar = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: _FilterPill(
                    label: item.$2,
                    selected: filter == item.$1,
                    onTap: () => onFilter(item.$1),
                  ),
                ),
            ],
          ),
        );

        final dropdowns = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarDropdown<_ReviewSort>(
              value: sort,
              width: 170,
              items: const {
                _ReviewSort.recientes: 'Más recientes',
                _ReviewSort.antiguos: 'Más antiguos',
                _ReviewSort.pendientes: 'Pendientes',
                _ReviewSort.revisados: 'Revisados',
              },
              onChanged: onSort,
            ),
            const SizedBox(width: 12),
            _ToolbarDropdown<_StatusFilter>(
              value: statusFilter,
              width: 180,
              items: const {
                _StatusFilter.todos: 'Todos los estados',
                _StatusFilter.revisado: 'Revisado',
                _StatusFilter.pendiente: 'Pendiente',
              },
              onChanged: onStatus,
            ),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filterBar,
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: dropdowns,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: filterBar),
            const SizedBox(width: 16),
            dropdowns,
          ],
        );
      },
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _RepasoColors.purple : surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? _RepasoColors.purple : border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarDropdown<T> extends StatelessWidget {
  const _ToolbarDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.width,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 44,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _RepasoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _RepasoColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: _RepasoColors.muted,
            ),
            style: const TextStyle(
              color: _RepasoColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            items: [
              for (final entry in items.entries)
                DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
          ),
        ),
      ),
    );
  }
}

final _booksProvider = FutureProvider<List<Book>>((ref) {
  return ref.watch(booksRepositoryProvider).listBooks();
});

class _BookReviewSection extends ConsumerStatefulWidget {
  const _BookReviewSection({
    super.key,
    required this.book,
    required this.initiallyExpanded,
    required this.searchQuery,
    required this.filter,
    required this.sort,
    required this.statusFilter,
  });

  final Book book;
  final bool initiallyExpanded;
  final String searchQuery;

  final _RepasoContentFilter filter;
  final _ReviewSort sort;
  final _StatusFilter statusFilter;

  @override
  ConsumerState<_BookReviewSection> createState() => _BookReviewSectionState();
}

class _BookReviewSectionState extends ConsumerState<_BookReviewSection> {
  late bool _expanded = widget.initiallyExpanded;

  bool _showAll = false;
  bool _loading = false;

  List<ReviewListEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BookReviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.filter != widget.filter ||
        oldWidget.sort != widget.sort ||
        oldWidget.statusFilter != widget.statusFilter ||
        oldWidget.searchQuery != widget.searchQuery) {
      _showAll = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final repo = ref.read(booksRepositoryProvider);

      final entries = await loadRepasoEntriesForBook(repo, widget.book);

      if (mounted) {
        setState(() {
          _entries = entries;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _patchCard(String id, Map<String, dynamic> patch) async {
    await ref.read(booksRepositoryProvider).patchStudyCard(id, patch);

    await _load();
  }

  Future<void> _patchHighlight(String id, Map<String, dynamic> patch) async {
    await ref.read(booksRepositoryProvider).patchHighlight(id, patch);

    await _load();
  }

  Future<void> _deleteCard(String id) async {
    await ref.read(booksRepositoryProvider).deleteStudyCard(id);

    await _load();
  }

  List<ReviewListEntry> _visibleEntries() {
    var list = List<ReviewListEntry>.from(_entries);

    if (widget.searchQuery.isNotEmpty) {
      list = list.where((entry) {
        return repasoDisplayTitle(
              entry,
            ).toLowerCase().contains(widget.searchQuery) ||
            repasoDisplayExcerpt(
              entry,
            ).toLowerCase().contains(widget.searchQuery) ||
            entry.bookTitle.toLowerCase().contains(widget.searchQuery);
      }).toList();
    }

    list = switch (widget.filter) {
      _RepasoContentFilter.todos => list,
      _RepasoContentFilter.resaltados =>
        list
            .where((entry) => entry.sourceType == ReviewSourceType.resaltado)
            .toList(),
      _RepasoContentFilter.tarjetas =>
        list
            .where((entry) => entry.sourceType == ReviewSourceType.tarjeta)
            .toList(),
      _RepasoContentFilter.resumenes =>
        list
            .where((entry) => entry.sourceType == ReviewSourceType.resumen)
            .toList(),
      _RepasoContentFilter.puntos =>
        list
            .where((entry) => entry.sourceType == ReviewSourceType.punto)
            .toList(),
      _RepasoContentFilter.fragmentos =>
        list
            .where((entry) => entry.sourceType == ReviewSourceType.fragmento)
            .toList(),
    };

    list = switch (widget.statusFilter) {
      _StatusFilter.todos => list,
      _StatusFilter.revisado => list.where((entry) => entry.reviewed).toList(),
      _StatusFilter.pendiente =>
        list.where((entry) => entry.pending && !entry.reviewed).toList(),
    };

    list = switch (widget.sort) {
      _ReviewSort.recientes =>
        list..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        ),
      _ReviewSort.antiguos =>
        list..sort(
          (a, b) => (a.createdAt ?? DateTime(1970)).compareTo(
            b.createdAt ?? DateTime(1970),
          ),
        ),
      _ReviewSort.pendientes =>
        list..sort((a, b) {
          final aValue = a.pending && !a.reviewed ? 0 : 1;
          final bValue = b.pending && !b.reviewed ? 0 : 1;

          return aValue.compareTo(bValue);
        }),
      _ReviewSort.revisados =>
        list..sort((a, b) {
          final aValue = a.reviewed ? 0 : 1;
          final bValue = b.reviewed ? 0 : 1;

          return aValue.compareTo(bValue);
        }),
    };

    return list;
  }

  Widget _reviewCard(ReviewListEntry entry) {
    return RepasoReviewCard(
      entry: entry,
      onRepasoDataChanged: _load,
      onReviewed: entry.card != null
          ? () => _patchCard(entry.card!['id'].toString(), {'reviewed': true})
          : null,
      onRepasar: entry.card != null
          ? () =>
                _patchCard(entry.card!['id'].toString(), {'review_again': true})
          : null,
      onDelete: entry.card != null
          ? () => _deleteCard(entry.card!['id'].toString())
          : null,
      onReviewedHighlight: entry.highlight != null
          ? () => _patchHighlight(entry.highlight!.id, {'reviewed': true})
          : null,
      onRepasarHighlight: entry.highlight != null
          ? () => _patchHighlight(entry.highlight!.id, {'review_again': true})
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final border = Theme.of(context).dividerColor;

    final counts = RepasoCounts.fromEntries(_entries);
    final visible = _visibleEntries();

    final shown = _showAll ? visible : visible.take(5).toList();

    final seed = coverGradientSeed(widget.book);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF18213A).withValues(alpha: 0.025),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==========================================
            // BOOK HEADER
            // ==========================================
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final compactHeader = headerConstraints.maxWidth < 520;
                    final meta = Text(
                      '${counts.resaltados} resaltados'
                      ' · ${counts.tarjetas} tarjetas'
                      ' · ${counts.resumenes} resúmenes'
                      ' · ${counts.puntos} puntos'
                      ' · ${counts.fragmentos} fragmentos',
                      maxLines: compactHeader ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                    final progress = counts.trackable > 0
                        ? Column(
                            crossAxisAlignment: compactHeader
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${counts.reviewed} de ${counts.trackable}',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              SizedBox(
                                width: compactHeader ? double.infinity : 105,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: counts.reviewed / counts.trackable,
                                    minHeight: 6,
                                    backgroundColor:
                                        scheme.surfaceContainerHighest,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : null;
                    final chevron = AnimatedRotation(
                      turns: _expanded ? -0.25 : 0.25,
                      duration: const Duration(milliseconds: 160),
                      child: MIcon(
                        MargenLucide.chevronRight,
                        size: 20,
                        color: scheme.primary,
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 20, 16),
                      child: compactHeader
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    _BookCoverThumb(
                                      book: widget.book,
                                      seed: seed,
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Text(
                                        widget.book.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: onSurface,
                                          fontSize: 17,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    chevron,
                                  ],
                                ),
                                const SizedBox(height: 10),
                                meta,
                                if (progress != null) ...[
                                  const SizedBox(height: 12),
                                  progress,
                                ],
                              ],
                            )
                          : Row(
                              children: [
                                _BookCoverThumb(book: widget.book, seed: seed),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.book.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: onSurface,
                                          fontSize: 17,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      meta,
                                    ],
                                  ),
                                ),
                                if (progress != null) ...[
                                  const SizedBox(width: 18),
                                  progress,
                                ],
                                const SizedBox(width: 14),
                                chevron,
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),

            if (_expanded) ...[
              Divider(height: 1, thickness: 1, color: border),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ==========================================
                    // METRICS
                    // ==========================================
                    _BookMetrics(counts: counts),

                    const SizedBox(height: 20),

                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(
                          color: _RepasoColors.purple,
                        ),
                      ),

                    if (!_loading && visible.isEmpty)
                      const BookifiCallout(
                        'Sin contenido de repaso para este libro.',
                      ),

                    // ==========================================
                    // REVIEW ROWS
                    // ==========================================
                    if (!_loading && visible.isNotEmpty)
                      Column(
                        children: [
                          for (var i = 0; i < shown.length; i++) ...[
                            _reviewCard(shown[i]),
                            if (i != shown.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),

                    if (visible.length > 5) ...[
                      const SizedBox(height: 12),

                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAll = !_showAll;
                            });
                          },
                          icon: Icon(
                            _showAll
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _RepasoColors.muted,
                          ),
                          label: Text(
                            _showAll
                                ? 'Ver menos elementos'
                                : 'Ver más elementos',
                            style: const TextStyle(
                              color: _RepasoColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookMetrics extends StatelessWidget {
  const _BookMetrics({required this.counts});

  final RepasoCounts counts;

  @override
  Widget build(BuildContext context) {
    final ui = context.repaso;
    final metrics = <Widget>[
      _BookMetricCard(
        value: '${counts.resaltados}',
        label: 'Resaltados',
        icon: MargenLucide.bookmark,
        accent: ui.purple,
        background: ui.purpleSoft,
      ),
      _BookMetricCard(
        value: '${counts.tarjetas}',
        label: 'Tarjetas',
        icon: MargenLucide.notebookTabs,
        accent: ui.blue,
        background: ui.blueSoft,
      ),
      _BookMetricCard(
        value: '${counts.resumenes}',
        label: 'Resúmenes',
        icon: MargenLucide.fileText,
        accent: ui.purple,
        background: ui.purpleSoft,
      ),
      _BookMetricCard(
        value: '${counts.puntos}',
        label: 'Puntos importantes',
        icon: MargenLucide.star,
        accent: ui.orange,
        background: ui.orangeSoft,
      ),
      _BookMetricCard(
        value: '${counts.fragmentos}',
        label: 'Fragmentos',
        icon: MargenLucide.scanLine,
        accent: ui.cyan,
        background: ui.cyanSoft,
      ),
      if (counts.progressPercent != null)
        _BookMetricCard(
          value: '${counts.progressPercent}%',
          label: 'Progreso de repaso',
          icon: MargenLucide.clock,
          accent: ui.teal,
          background: ui.tealSoft,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;

        double width;

        if (constraints.maxWidth >= 1100) {
          // Four cards like the reference.
          width = (constraints.maxWidth - spacing * 3) / 4;
        } else if (constraints.maxWidth >= 680) {
          width = (constraints.maxWidth - spacing) / 2;
        } else {
          width = constraints.maxWidth;
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }
}

class _BookMetricCard extends StatelessWidget {
  const _BookMetricCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    required this.background,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: MIcon(icon, size: 21, color: accent),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepasoGeneratedQuestionsSection extends ConsumerWidget {
  const _RepasoGeneratedQuestionsSection({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(repasoQaCatalogProvider);
    final scheme = Theme.of(context).colorScheme;
    final border = Theme.of(context).dividerColor;

    return catalogAsync.when(
      loading: () => const SizedBox(
        height: 4,
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (catalog) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: catalog.total == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PREGUNTAS DE REPASO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTokens.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No tienes preguntas generadas todavía.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'PREGUNTAS DE REPASO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTokens.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${catalog.total} preguntas disponibles',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        BookifiPrimaryButton(
                          label: 'Ver preguntas generadas (${catalog.total})',
                          onPressed: () => context.push('/repaso/preguntas'),
                        ),
                        BookifiGhostButton(
                          label: 'Comenzar repaso',
                          onPressed: () =>
                              openRepasoSessionAll(context, ref, books),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _BookCoverThumb extends StatelessWidget {
  const _BookCoverThumb({required this.book, required this.seed});

  final Book book;
  final Color seed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(_RepasoColors.purple, seed, 0.25)!,
              Color.lerp(_RepasoColors.blue, seed, 0.20)!,
            ],
          ),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(5),
        child: Text(
          book.title.isEmpty ? '·' : book.title[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
