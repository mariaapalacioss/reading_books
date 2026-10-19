import 'package:flutter/material.dart';

import '../reader/reader_page.dart';
import '../reader/reader_search_focus.dart';
import 'book_workspace_nav.dart';

/// Envuelve el lector existente con la navegación Leer | Estudiar | Practicar.
class BookWorkspaceLeerShell extends StatelessWidget {
  const BookWorkspaceLeerShell({
    super.key,
    required this.bookId,
    this.initialPage,
    this.searchFocus,
  });

  final String bookId;
  final int? initialPage;
  final ReaderSearchFocus? searchFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: BookWorkspaceNav(
            bookId: bookId,
            current: BookWorkspaceMode.leer,
            page: initialPage,
          ),
        ),
        Expanded(
          child: ReaderPage(
            bookId: bookId,
            initialPage: initialPage,
            searchFocus: searchFocus,
          ),
        ),
      ],
    );
  }
}
