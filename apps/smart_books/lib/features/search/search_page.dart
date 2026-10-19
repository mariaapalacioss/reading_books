import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../shared/bookifi_ui.dart';
import 'library_ask_tab.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: BookifiPage(
        scroll: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Buscar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Texto exacto'),
                Tab(text: 'Conceptos'),
                Tab(text: 'Preguntar'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _ExactTextSearchTab(),
                  _ConceptSearchTab(),
                  LibraryAskTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExactTextSearchTab extends ConsumerStatefulWidget {
  const _ExactTextSearchTab();

  @override
  ConsumerState<_ExactTextSearchTab> createState() =>
      _ExactTextSearchTabState();
}

class _ExactTextSearchTabState extends ConsumerState<_ExactTextSearchTab> {
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
    return Column(
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
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _hitsList(_hits, _query.text.trim())),
      ],
    );
  }
}

class _ConceptSearchTab extends ConsumerStatefulWidget {
  const _ConceptSearchTab();

  @override
  ConsumerState<_ConceptSearchTab> createState() => _ConceptSearchTabState();
}

class _ConceptSearchTabState extends ConsumerState<_ConceptSearchTab> {
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
      final hits = await ref.read(semanticSearchServiceProvider).search(q);
      setState(() => _hits = hits);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          decoration: InputDecoration(
            labelText: 'Conceptos relacionados',
            hintText: 'p. ej. inflación, derivadas, capítulo 3…',
            suffixIcon: IconButton(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.hub_outlined),
            ),
          ),
          onSubmitted: (_) => _run(),
        ),
        Text(
          'Amplía la búsqueda exacta con términos relacionados en tus libros.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _hitsList(_hits, _query.text.trim())),
      ],
    );
  }
}

Widget _hitsList(List<Map<String, dynamic>> hits, String query) {
  return ListView.builder(
    itemCount: hits.length,
    itemBuilder: (context, i) {
      final hit = hits[i];
      final books = hit['books'] as Map<String, dynamic>?;
      final title = books?['title']?.toString() ?? hit['book_id'].toString();
      final page = hit['page_number'];
      final snippet = (hit['text'] as String? ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return ListTile(
        title: Text('$title · p. $page'),
        subtitle: Text(
          snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet,
        ),
        onTap: () {
          context.push(
            '/libro/${hit['book_id']}?page=$page',
            extra: {'searchQuery': query, 'searchSnippet': snippet},
          );
        },
      );
    },
  );
}
