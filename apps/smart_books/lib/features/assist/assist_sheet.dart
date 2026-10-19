import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/models/highlight.dart';
import 'assist_panel.dart';

/// Sheet móvil; delega en [AssistPanel].
class AssistSheet extends StatelessWidget {
  const AssistSheet({
    super.key,
    required this.book,
    required this.page,
    required this.chapters,
    this.quote,
    this.pageHasText = true,
    this.selectionPreviewPixels,
    this.selectionPreviewWidth,
    this.selectionPreviewHeight,
    this.autoExplain = false,
    this.highlights = const [],
    this.onClose,
  });

  final Book book;
  final int page;
  final List<Chapter> chapters;
  final List<Highlight> highlights;
  final String? quote;
  final bool pageHasText;
  final Uint8List? selectionPreviewPixels;
  final int? selectionPreviewWidth;
  final int? selectionPreviewHeight;
  final bool autoExplain;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return AssistPanel(
      book: book,
      page: page,
      chapters: chapters,
      highlights: highlights,
      quote: quote,
      pageHasText: pageHasText,
      embedded: false,
      selectionPreviewPixels: selectionPreviewPixels,
      selectionPreviewWidth: selectionPreviewWidth,
      selectionPreviewHeight: selectionPreviewHeight,
      autoExplain: autoExplain,
      onClose: onClose,
    );
  }
}
