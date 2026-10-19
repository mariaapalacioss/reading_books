import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';

enum BookWorkspaceMode { leer, estudiar, practicar }

extension BookWorkspaceModeX on BookWorkspaceMode {
  String get label => switch (this) {
    BookWorkspaceMode.leer => 'Leer',
    BookWorkspaceMode.estudiar => 'Estudiar',
    BookWorkspaceMode.practicar => 'Practicar',
  };

  String get queryValue => name;
}

BookWorkspaceMode bookWorkspaceModeFromQuery(String? raw) {
  return switch (raw) {
    'estudiar' => BookWorkspaceMode.estudiar,
    'practicar' => BookWorkspaceMode.practicar,
    _ => BookWorkspaceMode.leer,
  };
}

String bookWorkspaceLocation({
  required String bookId,
  required BookWorkspaceMode mode,
  int? page,
}) {
  final uri = Uri(
    path: '/libro/$bookId',
    queryParameters: {
      if (page != null) 'page': '$page',
      if (mode != BookWorkspaceMode.leer) 'view': mode.queryValue,
    },
  );
  return uri.toString();
}

class BookWorkspaceNav extends StatelessWidget {
  const BookWorkspaceNav({
    super.key,
    required this.bookId,
    required this.current,
    this.page,
  });

  final String bookId;
  final BookWorkspaceMode current;
  final int? page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<BookWorkspaceMode>(
        segments: BookWorkspaceMode.values
            .map(
              (m) => ButtonSegment(
                value: m,
                label: Text(m.label, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
        selected: {current},
        onSelectionChanged: (set) {
          final mode = set.first;
          if (mode == current) return;
          context.go(bookWorkspaceLocation(bookId: bookId, mode: mode, page: page));
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppTokens.purple;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTokens.purple;
            }
            return null;
          }),
        ),
      ),
    );
  }
}
