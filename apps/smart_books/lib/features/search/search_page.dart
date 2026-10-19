import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../shared/bookifi_ui.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _query = TextEditingController();
  var _busy = false;
  List<Map<String, dynamic>> _hits = [];
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await ref.read(booksRepositoryProvider).textSearchLibrary(q);
      setState(() => _hits = hits);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = BookifiPage(
      scroll: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: 'Texto en tus libros',
              suffixIcon: IconButton(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _run(),
          ),
          const SizedBox(height: 8),
          Text(
            'Búsqueda semántica: requiere la función edge del proyecto web (limitación de servidor).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _hits.length,
              itemBuilder: (_, i) {
                final hit = _hits[i];
                final books = hit['books'] as Map<String, dynamic>?;
                final title =
                    books?['title']?.toString() ?? hit['book_id'].toString();
                final page = hit['page_number'];
                final snippet = (hit['text'] as String? ?? '')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                return ListTile(
                  title: Text('$title · p. $page'),
                  subtitle: Text(
                    snippet.length > 160
                        ? '${snippet.substring(0, 160)}…'
                        : snippet,
                  ),
                  onTap: () {
                    final query = _query.text.trim();
                    context.push(
                      '/libro/${hit['book_id']}?page=$page',
                      extra: {'searchQuery': query, 'searchSnippet': snippet},
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
    return content;
  }
}
