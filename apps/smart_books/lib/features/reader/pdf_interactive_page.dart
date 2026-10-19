import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfPageLayout;

import '../../data/models/highlight.dart';
import '../../data/models/text_item.dart';
import '../../domain/pdf_page_layout.dart';
import '../../domain/region_select.dart';
import '../../domain/rects.dart';
import '../../services/pdf_page_render.dart';
import '../../services/platform_ocr.dart';
import 'reader_margin_note.dart';

typedef PdfSelection = ({
  String quote,
  List<NormRect> rects,
  Offset anchor,
  Uint8List? previewPixels,
  int? previewWidth,
  int? previewHeight,
});

class PdfInteractivePage extends StatefulWidget {
  const PdfInteractivePage({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.pageText,
    required this.items,
    required this.highlights,
    required this.showAi,
    required this.onSelection,
    required this.onHighlightTap,
    this.marginNotes = const [],
    this.onMarginNoteTap,
    this.onRegionBusy,
    this.transformationController,
    this.searchMatchRects,
    this.onSearchMatchLayout,
  });

  final PdfDocument document;
  final int pageNumber;
  final String pageText;
  final List<TextItem> items;
  final List<Highlight> highlights;
  final bool showAi;
  final ValueChanged<PdfSelection?> onSelection;
  final ValueChanged<Highlight> onHighlightTap;
  final List<ReaderMarginNote> marginNotes;
  final ValueChanged<ReaderMarginNote>? onMarginNoteTap;
  final ValueChanged<bool>? onRegionBusy;
  final TransformationController? transformationController;
  final List<NormRect>? searchMatchRects;
  final void Function(ReaderPdfLayout layout, Size viewportSize)?
  onSearchMatchLayout;

  @override
  State<PdfInteractivePage> createState() => PdfInteractivePageState();
}

class PdfInteractivePageState extends State<PdfInteractivePage> {
  static const _searchFill = Color(0x66FFEB3B);
  static const _searchBorder = Color(0xFFF9A825);

  NormRect? _selectionPdfRect;
  Object? _searchLayoutNotifiedFor;
  NormRect? _dragMarquee;
  ({double x, double y})? _dragStart;
  var _busy = false;

  void clearActiveSelection() {
    if (_selectionPdfRect == null &&
        _dragMarquee == null &&
        _dragStart == null) {
      return;
    }
    setState(() {
      _selectionPdfRect = null;
      _dragMarquee = null;
      _dragStart = null;
    });
  }

  @override
  void didUpdateWidget(covariant PdfInteractivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber) {
      clearActiveSelection();
    }
    if (widget.searchMatchRects != oldWidget.searchMatchRects) {
      _searchLayoutNotifiedFor = null;
    }
  }

  void _scheduleSearchLayoutNotice(ReaderPdfLayout layout, Size viewport) {
    final rects = widget.searchMatchRects;
    if (rects == null || rects.isEmpty || widget.onSearchMatchLayout == null) {
      return;
    }
    final token = Object.hash(
      widget.pageNumber,
      rects.length,
      rects.first.hashCode,
    );
    if (_searchLayoutNotifiedFor == token) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.searchMatchRects == null || widget.searchMatchRects!.isEmpty) {
        return;
      }
      _searchLayoutNotifiedFor = token;
      widget.onSearchMatchLayout!(layout, viewport);
    });
  }

  ReaderPdfLayout _pageLayout(double w, double h) {
    final page = widget.document.pages[widget.pageNumber - 1];
    final pw = page.width > 0 ? page.width : 612.0;
    final ph = page.height > 0 ? page.height : 792.0;
    return layoutPdfPageInBox(
      boxWidth: w,
      boxHeight: h,
      pageWidth: pw,
      pageHeight: ph,
    );
  }

  Offset _scenePoint(Offset viewportLocal) {
    final tc = widget.transformationController;
    if (tc != null) {
      return tc.toScene(viewportLocal);
    }
    return viewportLocal;
  }

  Offset _normalizedFromViewport(Offset viewportLocal, ReaderPdfLayout layout) {
    return layout.toNormalized(_scenePoint(viewportLocal));
  }

  NormRect _normRectFromDrag(double x0, double y0, double x1, double y1) {
    return normRectFromPoints(
      x0.clamp(0.0, 1.0),
      y0.clamp(0.0, 1.0),
      x1.clamp(0.0, 1.0),
      y1.clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final pageLayout = _pageLayout(w, h);
        final overlayRect = _dragMarquee ?? _selectionPdfRect;
        final viewport = Size(w, h);
        _scheduleSearchLayoutNotice(pageLayout, viewport);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _busy ? null : (e) => _onPointerDown(e, pageLayout),
          onPointerMove: _busy ? null : (e) => _onPointerMove(e, pageLayout),
          onPointerUp: _busy ? null : (e) => _onPointerUp(e, pageLayout),
          child: InteractiveViewer(
            transformationController: widget.transformationController,
            minScale: 0.5,
            maxScale: 4,
            panEnabled: _dragStart == null,
            scaleEnabled: _dragStart == null,
            child: SizedBox(
              width: w,
              height: h,
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PdfPageView(
                      document: widget.document,
                      pageNumber: widget.pageNumber,
                    ),
                    if (widget.showAi) ..._highlightLayers(pageLayout),
                    ..._marginNoteLayers(pageLayout),
                    ..._searchMatchLayers(pageLayout),
                    if (overlayRect != null)
                      _selectionLayer(overlayRect, pageLayout),
                    if (_busy)
                      const ColoredBox(
                        color: Color(0x44000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _searchMatchLayers(ReaderPdfLayout layout) {
    final rects = widget.searchMatchRects;
    if (rects == null || rects.isEmpty) return const [];
    return [
      for (final r in rects)
        Positioned.fromRect(
          rect: layout.normRectToLocal(r),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _searchFill,
                border: Border.all(color: _searchBorder, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _selectionLayer(NormRect r, ReaderPdfLayout layout) {
    final box = layout.normRectToLocal(r);
    return Positioned(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.deepPurple, width: 2),
            color: Colors.deepPurple.withValues(alpha: 0.15),
          ),
        ),
      ),
    );
  }

  List<Widget> _marginNoteLayers(ReaderPdfLayout layout) {
    final onTap = widget.onMarginNoteTap;
    if (onTap == null || widget.marginNotes.isEmpty) return [];
    return widget.marginNotes
        .where((n) => n.pageNumber == widget.pageNumber && n.rects.isNotEmpty)
        .map((note) {
          var maxRight = 0.0;
          var minTop = 1.0;
          for (final r in note.rects) {
            final box = layout.normRectToLocal(r);
            if (box.right > maxRight) maxRight = box.right;
            if (box.top < minTop) minTop = box.top;
          }
          return Positioned(
            left: maxRight + 4,
            top: minTop,
            child: GestureDetector(
              onTap: () => onTap(note),
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFFFB020),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.sticky_note_2, size: 18, color: Colors.white),
                ),
              ),
            ),
          );
        })
        .toList();
  }

  List<Widget> _highlightLayers(ReaderPdfLayout layout) {
    return widget.highlights
        .where((hl) => hl.pageNumber == widget.pageNumber && !hl.dismissed)
        .map((hl) {
          final rects = hl.rects ?? [];
          return Stack(
            children: [
              for (final r in rects)
                Positioned.fromRect(
                  rect: layout.normRectToLocal(
                    NormRect(x: r['x']!, y: r['y']!, w: r['w']!, h: r['h']!),
                  ),
                  child: GestureDetector(
                    onTap: () => widget.onHighlightTap(hl),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _colorFor(hl.category).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          );
        })
        .toList();
  }

  void _onPointerDown(PointerDownEvent e, ReaderPdfLayout layout) {
    if (e.buttons != 1) return;
    final scene = _scenePoint(e.localPosition);
    if (!layout.contains(scene)) return;
    setState(() {
      _selectionPdfRect = null;
      final norm = layout.toNormalized(scene);
      _dragStart = (x: norm.dx, y: norm.dy);
      _dragMarquee = _normRectFromDrag(norm.dx, norm.dy, norm.dx, norm.dy);
    });
  }

  void _onPointerMove(PointerMoveEvent e, ReaderPdfLayout layout) {
    final start = _dragStart;
    if (start == null) return;
    final norm = _normalizedFromViewport(e.localPosition, layout);
    setState(
      () =>
          _dragMarquee = _normRectFromDrag(start.x, start.y, norm.dx, norm.dy),
    );
  }

  Future<void> _onPointerUp(PointerUpEvent e, ReaderPdfLayout layout) async {
    final region = _dragMarquee;
    _dragStart = null;
    setState(() => _dragMarquee = null);

    if (region == null || region.w < 0.01 || region.h < 0.01) {
      return;
    }

    await _finishCapture(region, _scenePoint(e.localPosition));
  }

  Future<void> _finishCapture(NormRect region, Offset anchorScene) async {
    setState(() => _busy = true);
    widget.onRegionBusy?.call(true);
    try {
      final rendered = await renderPdfPage(widget.document, widget.pageNumber);
      if (rendered == null) {
        widget.onSelection(null);
        return;
      }
      final crop = cropBgraRegion(
        pixels: rendered.pixels,
        width: rendered.width,
        height: rendered.height,
        region: region,
      );
      if (crop == null) {
        widget.onSelection(null);
        return;
      }

      final words = await recognizeBgraPage(
        width: crop.width,
        height: crop.height,
        pixels: crop.pixels,
      );
      var quote = words
          .map((w) => w.text)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (quote.length < 8 && widget.items.isNotEmpty) {
        final picked = textFromRegion(
          widget.items,
          region,
          pageText: widget.pageText,
        );
        if (picked.quote.length >= 8) quote = picked.quote;
      }

      if (quote.length < 8) {
        quote = quote.isEmpty ? 'Recorte visual del PDF' : 'Recorte: $quote';
      }
      if (quote.length < 8) {
        widget.onSelection(null);
        return;
      }

      setState(() => _selectionPdfRect = region);
      widget.onSelection((
        quote: quote,
        rects: [region],
        anchor: anchorScene,
        previewPixels: crop.pixels,
        previewWidth: crop.width,
        previewHeight: crop.height,
      ));
    } finally {
      widget.onRegionBusy?.call(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _colorFor(String category) {
    return switch (category) {
      'definicion' => Colors.amber,
      'dato' => Colors.lightBlue,
      'conclusion' => Colors.purple,
      'contexto' => Colors.grey,
      'manual' => Colors.green,
      _ => Colors.orange,
    };
  }
}
