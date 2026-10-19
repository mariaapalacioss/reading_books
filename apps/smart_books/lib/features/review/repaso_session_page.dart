import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../data/models/book.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../shared/bookifi_ui.dart';
import 'repaso_models.dart';
import 'repaso_qa_store.dart';
import 'repaso_questions_catalog.dart';
import 'repaso_session_route.dart';

class RepasoSessionPage extends ConsumerStatefulWidget {
  const RepasoSessionPage({super.key, this.extra, this.allExtra});

  final RepasoSessionExtra? extra;
  final RepasoSessionAllExtra? allExtra;

  static RepasoSessionPage fromRoute(GoRouterState state) {
    final extra = state.extra;
    if (extra is RepasoSessionAllExtra) {
      return RepasoSessionPage(allExtra: extra);
    }
    if (extra is RepasoSessionExtra) {
      return RepasoSessionPage(extra: extra);
    }
    return const RepasoSessionPage();
  }

  @override
  ConsumerState<RepasoSessionPage> createState() => _RepasoSessionPageState();
}

class _RepasoSessionPageState extends ConsumerState<RepasoSessionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  var _index = 0;
  var _showBack = false;
  var _loading = true;
  String? _error;

  List<RepasoFlashcard> _cards = [];
  ReviewListEntry? _entry;
  String? _bookId;
  void Function()? _onReviewed;
  void Function()? _onRepasar;
  Map<String, String> _bookIdByStudyCardId = {};

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.allExtra != null) {
      _cards = widget.allExtra!.cards;
      _bookIdByStudyCardId = widget.allExtra!.bookIdByStudyCardId;
      _bookId = null;
      _entry = ReviewListEntry(
        id: 'all-generated-qa',
        sourceType: ReviewSourceType.tarjeta,
        bookId: '',
        bookTitle: 'Todas las preguntas',
        title: 'Preguntas de repaso',
        excerpt: '${_cards.length} preguntas',
      );
      _onReviewed = () => _markCurrentReviewed();
      _onRepasar = () => _markCurrentPending();
    } else if (widget.extra != null) {
      final e = widget.extra!;
      _cards = e.cards;
      _entry = e.entry;
      _bookId = e.bookId;
      _onReviewed = e.onReviewed ?? () => _markCurrentReviewed();
      _onRepasar = e.onRepasar ?? () => _markCurrentPending();
    } else {
      setState(() {
        _loading = false;
        _error = 'No se pudo abrir la sesión de repaso.';
      });
      return;
    }

    if (_cards.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No hay preguntas de repaso disponibles.';
      });
      return;
    }

    setState(() => _loading = false);
  }

  Future<void> _markCurrentReviewed() async {
    final id = _cards[_index].studyCardId;
    if (id == null) return;
    await ref.read(booksRepositoryProvider).patchStudyCard(id, {
      'reviewed': true,
      'review_again': false,
    });
    bumpRepasoReloadTick(ref);
  }

  Future<void> _markCurrentPending() async {
    final id = _cards[_index].studyCardId;
    if (id == null) return;
    await ref.read(booksRepositoryProvider).patchStudyCard(id, {
      'review_again': true,
    });
    bumpRepasoReloadTick(ref);
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  RepasoFlashcard get _current => _cards[_index];

  void _resetFlip() {
    if (_showBack) {
      _flipCtrl.reverse();
      _showBack = false;
    }
  }

  void _toggleFlip() {
    if (_showBack) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _showBack = !_showBack);
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _cards.length) return;
    _resetFlip();
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _cards.isEmpty || _entry == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Repaso'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? 'Sin preguntas'),
          ),
        ),
      );
    }

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final card = _current;
    final total = _cards.length;
    final bookId =
        _bookId ??
        (card.studyCardId != null
            ? _bookIdByStudyCardId[card.studyCardId!]
            : null);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Repaso de preguntas'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pregunta ${_index + 1} de $total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (_index + 1) / total,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                    backgroundColor: AppTokens.purple.withValues(alpha: 0.12),
                    color: AppTokens.purple,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _toggleFlip,
                      child: AnimatedBuilder(
                        animation: _flipCtrl,
                        builder: (context, child) {
                          final angle = _flipCtrl.value * math.pi;
                          final isUnder = angle > math.pi / 2;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateY(angle),
                            child: isUnder
                                ? Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..rotateY(math.pi),
                                    child: RepasoSessionFace(
                                      label: 'Respuesta',
                                      text: card.answer,
                                      accent: AppTokens.purple,
                                      hint: 'Toca para volver a la pregunta',
                                      source: card,
                                    ),
                                  )
                                : RepasoSessionFace(
                                    label: 'Pregunta',
                                    text: card.question,
                                    accent: AppTokens.cyan,
                                    hint: 'Toca para ver la respuesta',
                                    source: card,
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      BookifiGhostButton(
                        label: 'Anterior',
                        compact: true,
                        onPressed: _index > 0 ? () => _go(-1) : null,
                      ),
                      const Spacer(),
                      Text(
                        '${_index + 1} / $total',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                      const Spacer(),
                      BookifiGhostButton(
                        label: 'Siguiente',
                        compact: true,
                        onPressed: _index < total - 1 ? () => _go(1) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (card.pageNumber != null &&
                      bookId != null &&
                      bookId.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          context.push(
                            '/libro/$bookId?page=${card.pageNumber}',
                          );
                        },
                        icon: MIcon(
                          MargenLucide.fileText,
                          size: 16,
                          color: AppTokens.purple,
                        ),
                        label: Text(
                          'Abrir PDF ${card.pageNumber}',
                          style: TextStyle(
                            color: AppTokens.purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      BookifiGhostButton(
                        label: 'Seguir pendiente',
                        compact: true,
                        onPressed: () {
                          _onRepasar?.call();
                          if (mounted) context.pop();
                        },
                      ),
                      BookifiPrimaryButton(
                        label: 'Marcar revisado',
                        onPressed: () {
                          _onReviewed?.call();
                          if (mounted) context.pop();
                        },
                      ),
                    ],
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

class RepasoSessionFace extends StatelessWidget {
  const RepasoSessionFace({
    super.key,
    required this.label,
    required this.text,
    required this.accent,
    required this.hint,
    required this.source,
  });

  final String label;
  final String text;
  final Color accent;
  final String hint;
  final RepasoFlashcard source;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
        boxShadow: AppTokens.cardShadow(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          RepasoSessionSourceBlock(source: source),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class RepasoSessionSourceBlock extends StatelessWidget {
  const RepasoSessionSourceBlock({super.key, required this.source});

  final RepasoFlashcard source;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTokens.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fuente: ${source.sourceType.label}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTokens.purple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Archivo: ${source.bookTitle}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (source.chapterTitle != null && source.chapterTitle!.isNotEmpty)
            Text(
              'Capítulo: ${source.chapterTitle}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: muted),
            ),
          if (source.pageNumber != null)
            Text(
              'PDF ${source.pageNumber}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

Future<void> openRepasoSessionFromGroup(
  BuildContext context,
  WidgetRef ref,
  RepasoQaGroup group,
) async {
  final repo = ref.read(booksRepositoryProvider);
  List<Map<String, dynamic>> rows;
  if (group.sourceKey.startsWith('orphan:')) {
    final id = group.sourceKey.replaceFirst('orphan:', '');
    final cards = await repo.listStudyCards(group.bookId);
    Map<String, dynamic>? row;
    for (final c in cards) {
      if (c['id']?.toString() == id) {
        row = c;
        break;
      }
    }
    rows = row == null
        ? []
        : [
            {
              ...row,
              '_book_title': group.bookTitle,
              if (group.chapterTitle != null)
                '_chapter_title': group.chapterTitle,
            },
          ];
  } else {
    rows = await listPersistedQaForSource(
      repo,
      bookId: group.bookId,
      sourceKey: group.sourceKey,
      bookTitle: group.bookTitle,
      chapterTitle: group.chapterTitle,
    );
  }
  if (!context.mounted || rows.isEmpty) return;
  final cards = flashcardsFromQaRows(rows, group.toEntry().sourceType);
  await context.push<void>(
    '/repaso/sesion',
    extra: RepasoSessionExtra(
      entry: group.toEntry(),
      bookId: group.bookId,
      cards: cards,
    ),
  );
}

Future<void> openRepasoSessionAll(
  BuildContext context,
  WidgetRef ref,
  List<Book> books,
) async {
  final repo = ref.read(booksRepositoryProvider);
  final rows = await loadAllPersistedQaRows(repo, books);
  if (!context.mounted || rows.isEmpty) return;
  final cards = flashcardsFromQaRows(rows, ReviewSourceType.tarjeta);
  final bookIds = <String, String>{};
  for (final row in rows) {
    final sid = row['id']?.toString();
    final bid = row['book_id']?.toString();
    if (sid != null && bid != null) bookIds[sid] = bid;
  }
  await context.push<void>(
    '/repaso/sesion',
    extra: RepasoSessionAllExtra(cards: cards, bookIdByStudyCardId: bookIds),
  );
}
