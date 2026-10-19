import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../services/ocr_job_service.dart';
import '../../services/pdf_extractor.dart';
import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/models/highlight.dart';
import '../../data/models/text_item.dart';
import '../../domain/pdf_page_layout.dart';
import '../../domain/rects.dart';
import '../../domain/search_page_match.dart';
import 'reader_search_focus.dart';
import '../../app/app_shell.dart';
import '../../app/margen_scaffold.dart';
import '../../core/ui/friendly_errors.dart';
import '../assist/assist_panel.dart';
import '../assist/assist_sheet.dart';
import '../review/repaso_feedback.dart';
import '../review/repaso_qa_store.dart';
import '../shared/bookifi_ui.dart';
import 'book_context_bar.dart';
import 'pdf_interactive_page.dart';
import 'reader_layout.dart';
import 'selection_crop_preview.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    this.initialPage,
    this.searchFocus,
  });

  final String bookId;
  final int? initialPage;
  final ReaderSearchFocus? searchFocus;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _assistPanelKey = GlobalKey<AssistPanelState>();
  final _pdfInteractiveKey = GlobalKey<PdfInteractivePageState>();
  PdfDocument? _document;
  var _page = 1;
  var _loading = true;
  String? _error;
  Book? _book;
  List<Chapter> _chapters = [];
  Set<int> _bookmarks = {};
  List<Highlight> _highlights = [];
  String _pageText = '';
  List<TextItem> _items = [];
  List<NormRect>? _searchMatchRects;
  String? _searchFocusAppliedKey;
  String? _selectionQuote;
  Uint8List? _selectionPreviewPixels;
  int? _selectionPreviewWidth;
  int? _selectionPreviewHeight;
  late final void Function(OcrEvent) _onOcr;
  Timer? _ocrRefreshDebounce;
  var _lastOcrDone = 0;
  final _pdfTransform = TransformationController();
  var _zoom = 1.0;
  var _readerImmersive = false;

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocus != widget.searchFocus) {
      _clearSearchHighlight();
      if (widget.searchFocus != null) {
        unawaited(_applySearchFocusIfNeeded());
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _onOcr = _handleOcrEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ocrJobServiceProvider).subscribe(_onOcr);
      ref.read(ocrJobServiceProvider).setPrimaryBook(widget.bookId);
    });
    _load();
  }

  Future<void> _handleOcrEvent(OcrEvent event) async {
    if (event.bookId != widget.bookId || !mounted) return;
    if (event.error != null) {
      final book = await ref
          .read(booksRepositoryProvider)
          .getBook(widget.bookId);
      if (book != null && mounted) setState(() => _book = book);
      return;
    }
    if (event.done > 0 &&
        event.done <= _lastOcrDone &&
        event.done != event.total)
      return;
    if (event.done > 0) _lastOcrDone = event.done;
    _ocrRefreshDebounce?.cancel();
    _ocrRefreshDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final book = await ref
          .read(booksRepositoryProvider)
          .getBook(widget.bookId);
      if (book == null || !mounted) return;
      setState(() => _book = book);
      await _loadPageText();
    });
  }

  String? _readerStatusDetail(Book book) {
    final detail = book.statusDetail;
    if (detail == null || detail.trim().isEmpty) return null;
    if (detail.contains('PostgrestException') ||
        detail.contains('23505') ||
        detail.contains('duplicate key')) {
      return 'Reconociendo texto del PDF…';
    }
    return detail;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(booksRepositoryProvider);
      var book = await repo.getBook(widget.bookId);
      if (book == null) throw Exception('Libro no encontrado');
      final staleOcrError =
          book.statusDetail?.contains('23505') == true ||
          book.statusDetail?.contains('duplicate key') == true ||
          book.statusDetail?.contains('PostgrestException') == true;
      if (staleOcrError &&
          (book.status == 'needs_ocr' || book.status == 'extracting')) {
        await repo.updateBook(book.id, {
          'status': 'extracting',
          'status_detail': 'Reanudando lectura…',
        });
        book = (await repo.getBook(widget.bookId)) ?? book;
      }
      final chapters = await repo.listChapters(widget.bookId);
      final marks = await repo.listBookmarks(widget.bookId);
      _highlights = await repo.listHighlights(widget.bookId);
      final PdfDocument doc;
      if (book.isLocalStorage) {
        final bytes = await repo.downloadPdfBytes(book.storagePath);
        doc = await PdfDocument.openData(bytes, sourceName: book.storagePath);
      } else {
        final url = await repo.signedPdfUrl(book.storagePath);
        if (url == null) throw Exception('No se pudo abrir el PDF.');
        doc = await PdfDocument.openUri(Uri.parse(url));
      }
      final page = (widget.initialPage ?? book.currentPage).clamp(
        1,
        book.pageCount,
      );
      setState(() {
        _book = book;
        _chapters = chapters;
        _bookmarks = marks
            .map((m) => (m['page_number'] as num).toInt())
            .toSet();
        _page = page;
        _document?.dispose();
        _document = doc;
        _loading = false;
      });
      ref.read(ocrJobServiceProvider).setPrimaryBook(book.id);
      _prioritizeChapterOcr(book, chapters, page);
      unawaited(ref.read(ocrJobServiceProvider).ensureOcr(book));
      if (book.status == 'ready' ||
          book.status == 'partial' ||
          book.status == 'analyzed') {
        unawaited(ref.read(analysisServiceProvider).ensureAnalysis(book));
      }
      await _loadPageText();
    } catch (e) {
      setState(() {
        _error = friendlyUserError(e, logTag: 'reader');
        _loading = false;
      });
    }
  }

  void _prioritizeChapterOcr(Book book, List<Chapter> chapters, int page) {
    Chapter? ch;
    for (final c in chapters) {
      if (page >= c.startPage && page <= c.endPage) {
        ch = c;
        break;
      }
    }
    if (ch == null) return;
    final pages = List.generate(
      ch.endPage - ch.startPage + 1,
      (i) => ch!.startPage + i,
    );
    ref.read(ocrJobServiceProvider).prioritizePages(book.id, pages);
  }

  Future<void> _loadPageText() async {
    final repo = ref.read(booksRepositoryProvider);
    final row = await repo.getPage(widget.bookId, _page);
    if (!mounted) return;

    var pageText = row?['text'] as String? ?? '';
    final rawItems = row?['items'];
    var items = rawItems is List
        ? rawItems
              .map(
                (e) => TextItem.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList()
        : <TextItem>[];

    final doc = _document;
    if (doc != null && items.isEmpty && pageText.trim().length >= 20) {
      try {
        final extracted = await extractPageFromDocument(doc, _page);
        if (extracted.items.isNotEmpty) {
          items = extracted.items;
          if (extracted.text.trim().isNotEmpty) {
            pageText = extracted.text;
          }
          final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
          final book = _book;
          if (userId != null && book != null) {
            unawaited(
              repo.upsertPages(
                bookId: book.id,
                userId: userId,
                pages: [
                  (
                    page: _page,
                    text: pageText,
                    items: items,
                    printedLabel: extracted.printedLabel,
                    charCount: pageText.length,
                  ),
                ],
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[READER] extractPageFromDocument failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _pageText = pageText;
      _items = items;
    });
    await _applySearchFocusIfNeeded();
  }

  Future<void> _applySearchFocusIfNeeded() async {
    final focus = widget.searchFocus;
    if (focus == null) return;

    final key = '${widget.bookId}:$_page:${focus.query}:${focus.snippet ?? ''}';
    if (_searchFocusAppliedKey == key) return;

    final match = findSearchMatchOnPage(
      pageText: _pageText,
      items: _items,
      query: focus.query,
      snippet: focus.snippet,
    );

    if (!mounted) return;
    _searchFocusAppliedKey = key;
    setState(() => _searchMatchRects = match?.rects);
  }

  void _clearSearchHighlight() {
    _searchMatchRects = null;
    _searchFocusAppliedKey = null;
  }

  void _centerViewportOnSearchMatch(ReaderPdfLayout layout, Size viewport) {
    final rects = _searchMatchRects;
    if (rects == null || rects.isEmpty) return;
    final bounds = unionNormRects(rects);
    final box = layout.normRectToLocal(bounds);
    final center = box.center;
    final scale = _zoom.clamp(0.5, 4.0);
    final tx = -center.dx * scale + viewport.width / 2;
    final ty = -center.dy * scale + viewport.height / 2;
    _pdfTransform.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  Future<void> _persistPage() async {
    final book = _book;
    if (book == null) return;
    await ref.read(booksRepositoryProvider).updateBook(book.id, {
      'current_page': _page,
      'last_read_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _setPage(int next) async {
    final book = _book;
    if (book == null) return;
    _finalizeSelectionUi();
    _clearSearchHighlight();
    setState(() {
      _page = next.clamp(1, book.pageCount);
      _resetPdfZoom();
    });
    await _persistPage();
    await _loadPageText();
    _prioritizeChapterOcr(book, _chapters, _page);
  }

  void _resetPdfZoom() {
    _pdfTransform.value = Matrix4.identity();
    _zoom = 1.0;
  }

  void _setZoom(double next) {
    final clamped = next.clamp(0.5, 4.0);
    _pdfTransform.value = Matrix4.identity()..scale(clamped);
    setState(() => _zoom = clamped);
  }

  void _clearSelection() {
    _selectionQuote = null;
    _selectionPreviewPixels = null;
    _selectionPreviewWidth = null;
    _selectionPreviewHeight = null;
  }

  void _finalizeSelectionUi() {
    _pdfInteractiveKey.currentState?.clearActiveSelection();
    _clearSelection();
  }

  void _applySelection(PdfSelection sel) {
    setState(() {
      _selectionQuote = sel.quote;
      _selectionPreviewPixels = sel.previewPixels;
      _selectionPreviewWidth = sel.previewWidth;
      _selectionPreviewHeight = sel.previewHeight;
    });
  }

  Future<void> _createHighlight(String quote, List<NormRect> rects) async {
    final book = _book;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (book == null || userId == null) return;
    String? chapterId;
    for (final ch in _chapters) {
      if (_page >= ch.startPage && _page <= ch.endPage) {
        chapterId = ch.id;
        break;
      }
    }
    final repo = ref.read(booksRepositoryProvider);
    final hl = await repo.createManualHighlight(
      bookId: book.id,
      userId: userId,
      chapterId: chapterId,
      pageNumber: _page,
      quote: quote,
      rects: rects.map((r) => r.toJson()).toList(),
    );
    final title = quote.length > 72 ? '${quote.substring(0, 69)}…' : quote;
    await repo.insertStudyCard({
      'book_id': book.id,
      'user_id': userId,
      'chapter_id': chapterId,
      'page_number': _page,
      'kind': 'capture',
      'source': 'capture',
      'title': title.isEmpty ? 'Resaltado p. $_page' : title,
      'body': quote,
      'quote': quote,
      'context_question': repasoSourceKeyFragmentSet(book.id, [hl.id]),
    });
    if (!mounted) return;
    setState(() => _highlights = [..._highlights, hl]);
    _finalizeSelectionUi();
    notifyRepasoSaved(ref);
  }

  void _onPdfSelection(PdfSelection? sel) {
    if (sel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo leer texto en esa zona. Prueba otra área o espera el OCR.',
          ),
        ),
      );
      return;
    }
    _openSelectionMenu(sel);
  }

  void _openSelectionMenu(PdfSelection sel) {
    final isWide = useWideLayout(context);
    if (isWide) {
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sel.previewPixels != null &&
                      sel.previewWidth != null &&
                      sel.previewHeight != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectionCropPreview(
                        pixels: sel.previewPixels!,
                        width: sel.previewWidth!,
                        height: sel.previewHeight!,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      sel.quote,
                      maxLines: 4,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  ),
                  BookifiGhostButton(
                    label: 'Resaltar',
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _createHighlight(sel.quote, sel.rects);
                    },
                  ),
                  const SizedBox(height: 8),
                  BookifiPrimaryButton(
                    label: 'Explicar con IA',
                    icon: Icons.auto_awesome,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _applySelection(sel);
                      _finalizeSelectionUi();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _assistPanelKey.currentState?.explainSelection();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  BookifiGhostButton(
                    label: 'Cancelar',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _finalizeSelectionUi();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(sel.quote, maxLines: 3)),
            ListTile(
              leading: const Icon(Icons.highlight),
              title: const Text('Resaltar'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createHighlight(sel.quote, sel.rects);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Explicar con IA'),
              onTap: () {
                Navigator.pop(ctx);
                _applySelection(sel);
                _finalizeSelectionUi();
                _openAssist(quote: sel.quote, explain: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancelar'),
              onTap: () {
                Navigator.pop(ctx);
                _finalizeSelectionUi();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAssist({String? quote, bool explain = false}) {
    final book = _book;
    if (book == null) return;
    if (useWideLayout(context)) {
      if (quote != null) setState(() => _selectionQuote = quote);
      if (explain) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _assistPanelKey.currentState?.explainSelection();
        });
      }
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: false,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final top = media.padding.top + 8;
        final height = (media.size.height - top) * 0.92;
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: SizedBox(
            height: height,
            child: AssistSheet(
              book: book,
              page: _page,
              chapters: _chapters,
              highlights: _highlights,
              quote: quote ?? _selectionQuote,
              pageHasText: _pageText.trim().isNotEmpty,
              selectionPreviewPixels: _selectionPreviewPixels,
              selectionPreviewWidth: _selectionPreviewWidth,
              selectionPreviewHeight: _selectionPreviewHeight,
              autoExplain: explain,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ocrRefreshDebounce?.cancel();
    ref.read(ocrJobServiceProvider).unsubscribe(_onOcr);
    ref.read(ocrJobServiceProvider).setPrimaryBook(null);
    _pdfTransform.dispose();
    _document?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MargenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _book == null || _document == null) {
      return MargenScaffold(body: Center(child: Text(_error ?? 'Error')));
    }
    final book = _book!;
    final doc = _document!;
    final isWide = useWideLayout(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PrevIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextIntent(),
      },
      child: Actions(
        actions: {
          _PrevIntent: CallbackAction<_PrevIntent>(
            onInvoke: (_) {
              if (_page > 1) _setPage(_page - 1);
              return null;
            },
          ),
          _NextIntent: CallbackAction<_NextIntent>(
            onInvoke: (_) {
              if (_page < book.pageCount) _setPage(_page + 1);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: MargenScaffold(
            showBottomNav: !isWide,
            bookContextBar: BookContextBar(
              title: book.title,
              onBackToLibrary: () => context.go('/'),
              page: _page,
              pageCount: book.pageCount,
              onPrevPage: () {
                if (_page > 1) _setPage(_page - 1);
              },
              onNextPage: () {
                if (_page < book.pageCount) _setPage(_page + 1);
              },
              onOpenAssist: () => _openAssist(),
              bookmarked: _bookmarks.contains(_page),
              onToggleBookmark: () async {
                final userId = ref
                    .read(supabaseClientProvider)
                    .auth
                    .currentUser
                    ?.id;
                if (userId == null) return;
                final exists = _bookmarks.contains(_page);
                await ref
                    .read(booksRepositoryProvider)
                    .toggleBookmark(book.id, userId, _page, exists);
                setState(() {
                  if (exists) {
                    _bookmarks.remove(_page);
                  } else {
                    _bookmarks.add(_page);
                  }
                });
              },
            ),
            body: ReaderLayout(
              isWide: isWide,
              immersive: _readerImmersive,
              chapters: _chapters,
              currentPage: _page,
              onChapter: (ch) => _setPage(ch.startPage),
              onAssist: () => _openAssist(),
              assistPanel: isWide
                  ? AssistPanel(
                      key: _assistPanelKey,
                      book: book,
                      page: _page,
                      chapters: _chapters,
                      highlights: _highlights,
                      quote: _selectionQuote,
                      pageHasText: _pageText.trim().length >= 40,
                      embedded: true,
                      selectionPreviewPixels: _selectionPreviewPixels,
                      selectionPreviewWidth: _selectionPreviewWidth,
                      selectionPreviewHeight: _selectionPreviewHeight,
                    )
                  : null,
              readerTop: _ReaderModeHeader(
                statusDetail: _readerStatusDetail(book),
              ),
              readerBottom: _ReaderPageControls(
                page: _page,
                pageCount: book.pageCount,
                zoom: _zoom,
                immersive: _readerImmersive,
                onPrev: () => _setPage(_page - 1),
                onNext: () => _setPage(_page + 1),
                onJumpToPage: (n) => _setPage(n),
                onZoomOut: () => _setZoom(_zoom - 0.15),
                onZoomIn: () => _setZoom(_zoom + 0.15),
                onFit: _resetPdfZoom,
                onToggleImmersive: () =>
                    setState(() => _readerImmersive = !_readerImmersive),
              ),
              body: PdfInteractivePage(
                key: _pdfInteractiveKey,
                document: doc,
                pageNumber: _page,
                pageText: _pageText,
                items: _items,
                highlights: _highlights,
                showAi: book.showAiHighlights,
                transformationController: _pdfTransform,
                searchMatchRects: _searchMatchRects,
                onSearchMatchLayout: _centerViewportOnSearchMatch,
                onSelection: _onPdfSelection,
                onHighlightTap: (hl) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(hl.explanationEs ?? hl.quote)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrevIntent extends Intent {
  const _PrevIntent();
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _ReaderModeHeader extends StatelessWidget {
  const _ReaderModeHeader({required this.statusDetail});

  final String? statusDetail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          const BookifiChip('Captura de zona', teal: true),
          const Spacer(),
          if (statusDetail != null && statusDetail!.isNotEmpty)
            Flexible(
              child: Text(
                statusDetail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTokens.teal),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderPageControls extends StatelessWidget {
  const _ReaderPageControls({
    required this.page,
    required this.pageCount,
    required this.zoom,
    required this.onPrev,
    required this.onNext,
    required this.onJumpToPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onToggleImmersive,
    this.immersive = false,
  });

  final int page;
  final int pageCount;
  final double zoom;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onToggleImmersive;
  final bool immersive;

  Future<void> _promptPageJump(BuildContext context) async {
    final ctrl = TextEditingController(text: '$page');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ir a página'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Número de página',
              hintText: '1–$pageCount',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Ir'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (result == null) return;
    final clamped = result.clamp(1, pageCount);
    onJumpToPage(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.85)
            : const Color(0xFFF8FAFC),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolbarIconButton(
            tooltip: 'Página anterior',
            icon: MargenLucide.chevronLeft,
            onPressed: page > 1 ? onPrev : null,
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _promptPageJump(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.25)
                      : Colors.white,
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '$page / $pageCount',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          _ToolbarIconButton(
            tooltip: 'Página siguiente',
            icon: MargenLucide.chevronRight,
            onPressed: page < pageCount ? onNext : null,
          ),
          const _ToolbarDivider(),
          _ToolbarIconButton(
            tooltip: 'Alejar',
            icon: MargenLucide.minus,
            onPressed: onZoomOut,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${(zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          _ToolbarIconButton(
            tooltip: 'Acercar',
            icon: MargenLucide.plus,
            onPressed: onZoomIn,
          ),
          const _ToolbarDivider(),
          _ToolbarIconButton(
            tooltip: 'Ajustar página',
            icon: MargenLucide.fitPage,
            onPressed: onFit,
          ),
          _ToolbarIconButton(
            tooltip: immersive
                ? 'Salir de pantalla completa'
                : 'Pantalla completa',
            icon: MargenLucide.fullscreen,
            onPressed: onToggleImmersive,
          ),
        ],
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
    );
  }
}

class _ToolbarIconButton extends StatefulWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: IconButton(
        tooltip: widget.tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: widget.onPressed,
        style: IconButton.styleFrom(
          backgroundColor: _hover && enabled
              ? AppTokens.purple.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        icon: MIcon(
          widget.icon,
          size: 20,
          color: enabled ? null : Theme.of(context).disabledColor,
        ),
      ),
    );
  }
}
