import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui/app_snackbar.dart';
import '../../services/library_ask_service.dart';
import '../shared/bookifi_ui.dart';

class LibraryAskTab extends ConsumerStatefulWidget {
  const LibraryAskTab({super.key});

  @override
  ConsumerState<LibraryAskTab> createState() => _LibraryAskTabState();
}

class _LibraryAskTabState extends ConsumerState<LibraryAskTab> {
  final _question = TextEditingController();
  var _busy = false;
  LibraryAskResult? _result;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _question.text.trim();
    if (q.length < 4) return;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final semantic = ref.read(semanticSearchServiceProvider);
      final svc = ref.read(libraryAskServiceProvider);
      final result = await svc.ask(
        userId: userId,
        question: q,
        search: semantic.search,
      );
      setState(() => _result = result);
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
          controller: _question,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Preguntar a mi biblioteca',
            suffixIcon: IconButton(
              onPressed: _busy ? null : _ask,
              icon: const Icon(Icons.psychology_outlined),
            ),
          ),
          onSubmitted: _busy ? null : (_) => _ask(),
        ),
        const SizedBox(height: 8),
        Text(
          'La respuesta usa solo extractos de tus libros, con libro y página como fuente.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_result != null) ...[
          const SizedBox(height: 12),
          BookifiCard(
            padding: const EdgeInsets.all(14),
            child: Text(_result!.answer),
          ),
          const SizedBox(height: 12),
          Text(
            'Fuentes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _result!.sources.length,
              itemBuilder: (_, i) {
                final s = _result!.sources[i];
                return ListTile(
                  title: Text('${s.bookTitle} · p.${s.pageNumber}'),
                  subtitle: Text(s.snippet),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () {
                    context.push('/libro/${s.bookId}?page=${s.pageNumber}');
                  },
                );
              },
            ),
          ),
        ] else
          const Spacer(),
        if (_result != null && _result!.insufficientEvidence)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => showAppSnackBar(
                'Prueba reformular la pregunta o añade más contenido a tus libros.',
              ),
              child: const Text('Ampliar búsqueda'),
            ),
          ),
      ],
    );
  }
}
